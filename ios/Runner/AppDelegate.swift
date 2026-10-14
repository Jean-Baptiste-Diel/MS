import UIKit
import AVFoundation
import CallKit
import Flutter
import GoogleMaps
import Firebase
import PushKit
import StoreKit
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate {
  /// Retenu par l'AppDelegate : un registry local serait desalloue et
  /// l'appareil ne recevrait jamais de push VoIP.
  private var voipRegistry: PKPushRegistry?

  /// Canal « appel décroché / refusé » vers Flutter, et dernier appel décroché.
  /// Le module d'appel envoie à Flutter les infos du DERNIER appel affiché par
  /// PushKit, pas celles de l'appel décroché : après un appel précédent (ou un
  /// appel reçu par FCM), l'app recevait l'identifiant d'un ancien appel, le
  /// croyait déjà rejoint et ne rejoignait pas → décroché sans son, et l'appel
  /// continuait quand l'autre raccrochait. Ici on a l'appel exact.
  private var acceptedCallChannel: FlutterMethodChannel?
  private var acceptedCall: [String: Any]?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    GeneratedPluginRegistrant.register(with: self)
    registerAudioRouteChannel()
    registerAcceptedCallChannel()
    registerAppStoreChannel()
    GMSServices.provideAPIKey("AIzaSyBtos9vMzqgH_Z9USy6eYMBtftzvhDYZhI")

    // PushKit : seul canal qui reveille une app iOS terminee pour un appel.
    registerForVoIPPushes()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Sortie audio pendant un appel (écouteur / haut-parleur / Bluetooth)

  /// CallKit possède la session audio (Agora configuré pour ne pas y toucher) :
  /// setEnableSpeakerphone d'Agora est alors sans effet. La sortie est basculée
  /// ici, directement sur la session audio.
  private var audioRouteChannel: FlutterMethodChannel?

  private func registerAudioRouteChannel() {
    guard let registrar = self.registrar(forPlugin: "MisonAudioRoute") else { return }
    let channel = FlutterMethodChannel(name: "mison/audio_route", binaryMessenger: registrar.messenger())
    audioRouteChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      do {
        switch call.method {
        case "setSpeaker":
          let speakerOn = (call.arguments as? Bool) ?? true
          try self.setRoute(speakerOn ? "speaker" : "earpiece")
          result(nil)
        case "setRoute":
          try self.setRoute((call.arguments as? String) ?? "earpiece")
          result(nil)
        case "getRoutes":
          result(self.currentRoutes())
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "AUDIO_ROUTE", message: error.localizedDescription, details: nil))
      }
    }
    // Casque Bluetooth connecté / déconnecté pendant l'appel : Dart rafraîchit.
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.audioRouteChannel?.invokeMethod("routeChanged", arguments: nil)
    }
  }

  private static let bluetoothPorts: Set<AVAudioSession.Port> = [.bluetoothHFP, .bluetoothA2DP, .bluetoothLE]

  private func bluetoothInput() -> AVAudioSessionPortDescription? {
    AVAudioSession.sharedInstance().availableInputs?.first { $0.portType == .bluetoothHFP }
  }

  private func currentRoutes() -> [String: Any] {
    let session = AVAudioSession.sharedInstance()
    let output = session.currentRoute.outputs.first
    let current: String
    switch output?.portType {
    case .builtInSpeaker?: current = "speaker"
    case .headphones?, .usbAudio?: current = "wired"
    case let port? where AppDelegate.bluetoothPorts.contains(port): current = "bluetooth"
    default: current = "earpiece"
    }
    let bt = bluetoothInput()
    let btOutput = session.currentRoute.outputs.first { AppDelegate.bluetoothPorts.contains($0.portType) }
    return [
      "current": current,
      "bluetooth": bt != nil || btOutput != nil,
      "bluetoothName": bt?.portName ?? btOutput?.portName ?? "",
    ]
  }

  private func setRoute(_ route: String) throws {
    let session = AVAudioSession.sharedInstance()
    switch route {
    case "speaker":
      try session.overrideOutputAudioPort(.speaker)
    case "bluetooth":
      try session.overrideOutputAudioPort(.none)
      if let bt = bluetoothInput() { try session.setPreferredInput(bt) }
    default: // écouteur du téléphone
      try session.overrideOutputAudioPort(.none)
      if let mic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
        try session.setPreferredInput(mic)
      }
    }
  }

  // MARK: - Mise à jour : fiche App Store dans l'app

  /// Apple ne permet pas d'installer une mise à jour depuis l'app : on ouvre
  /// la fiche App Store de MISON par-dessus l'app (bouton « Mettre à jour »
  /// d'Apple), sans la quitter.
  private func registerAppStoreChannel() {
    guard let registrar = self.registrar(forPlugin: "MisonAppStore") else { return }
    let channel = FlutterMethodChannel(name: "mison/app_store", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "open", let appId = call.arguments as? String,
            let root = self?.window?.rootViewController else {
        result(FlutterMethodNotImplemented)
        return
      }
      var top = root
      while let presented = top.presentedViewController { top = presented }
      let store = SKStoreProductViewController()
      store.delegate = self
      store.loadProduct(withParameters: [SKStoreProductParameterITunesItemIdentifier: appId]) { loaded, error in
        if loaded {
          top.present(store, animated: true)
          result(nil)
        } else {
          result(FlutterError(code: "APP_STORE", message: error?.localizedDescription, details: nil))
        }
      }
    }
  }

  // MARK: - Appel décroché alors que l'app était fermée

  /// App fermée : l'iPhone la relance quand on décroche depuis l'écran
  /// d'appel, mais l'événement « appel accepté » part avant que Flutter
  /// l'écoute. L'app le redemande ici au démarrage pour ouvrir l'appel.
  private func registerAcceptedCallChannel() {
    guard let registrar = self.registrar(forPlugin: "MisonAcceptedCall") else { return }
    let channel = FlutterMethodChannel(name: "mison/accepted_call", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getAcceptedCall" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.acceptedCall)
    }
    acceptedCallChannel = channel
  }

  // MARK: - PushKit (VoIP)

  private func registerForVoIPPushes() {
    let registry = PKPushRegistry(queue: DispatchQueue.main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP else { return }
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    // Consomme cote Dart via FlutterCallkitIncoming.getDevicePushTokenVoIP()
    // pour l'envoyer au backend.
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP else { return }
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else { completion(); return }

    let info = payload.dictionaryPayload
    let orderId = (info["order_id"] as? String) ?? (info["id"] as? String) ?? UUID().uuidString
    let callerName = (info["caller_name"] as? String)
      ?? (info["nameCaller"] as? String)
      ?? "Appel entrant"
    let channel = (info["channel"] as? String) ?? ""

    // iOS exige de signaler l'appel a CallKit immediatement, sinon le systeme
    // tue l'application.
    // Identifiant UNIQUE par appel : avec celui de la commande, un nouvel appel
    // sur la meme commande etait refuse par iOS tant que le precedent n'etait
    // pas libere (ca sonnait sans rien afficher). La commande est dans extra.
    let callData = Data(id: UUID().uuidString, nameCaller: callerName, handle: orderId, type: 0)
    callData.appName = "MISON"
    callData.duration = 30000
    callData.configureAudioSession = true
    callData.iconName = ""
    callData.extra = ["order_id": orderId, "channel": channel] as NSDictionary

    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(
      callData,
      fromPushKit: true
    )
    completion()
  }

  // MARK: - FCM data-only (fallback quand PushKit n'est pas configure)

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    if let type = userInfo["type"] as? String, type == "INCOMING_CALL",
       let orderId = userInfo["order_id"] as? String, !orderId.isEmpty,
       let callerName = userInfo["caller_name"] as? String {

      let channel = userInfo["channel"] as? String ?? ""

      // Skip if this device initiated the call (SharedPreferences key on iOS).
      // Marqueur valable 2 min : un appel sortant mal termine ne doit pas
      // empecher ce telephone de sonner ensuite pour la meme commande.
      let outgoingId = UserDefaults.standard.string(forKey: "flutter.outgoing_call_order_id")
      let outgoingAtMs = (UserDefaults.standard.object(forKey: "flutter.outgoing_call_at") as? NSNumber)?.doubleValue ?? 0
      let isOwnRecentCall = outgoingId == orderId
        && Date().timeIntervalSince1970 * 1000 - outgoingAtMs < 120_000
      if !isOwnRecentCall, let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance {
        DispatchQueue.main.async {
          let callData = Data(id: UUID().uuidString, nameCaller: callerName, handle: orderId, type: 0)
          callData.appName = "MISON"
          callData.duration = 30000
          callData.configureAudioSession = true
          callData.iconName = ""
          callData.extra = ["order_id": orderId, "channel": channel] as NSDictionary
          plugin.showCallkitIncoming(callData, fromPushKit: false)
        }
      }
    }
    // Always call super so Firebase can run the Dart background handler
    super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
  }
}

extension AppDelegate: SKStoreProductViewControllerDelegate {
  func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
    viewController.dismiss(animated: true)
  }
}

// MARK: - Actions CallKit sur l'appel exact

extension AppDelegate: CallkitIncomingAppDelegate {
  func onAccept(_ call: Call, _ action: CXAnswerCallAction) {
    let json = call.data.toJSON()
    acceptedCall = json
    // App ouverte : Flutter rejoint tout de suite. App fermée : Flutter n'écoute
    // pas encore, il redemande l'appel avec getAcceptedCall au démarrage.
    acceptedCallChannel?.invokeMethod("accepted", arguments: json)
    action.fulfill()
  }

  func onDecline(_ call: Call, _ action: CXEndCallAction) {
    acceptedCallChannel?.invokeMethod("declined", arguments: call.data.toJSON())
    action.fulfill()
  }

  func onEnd(_ call: Call, _ action: CXEndCallAction) {
    if (acceptedCall?["id"] as? String)?.lowercased() == call.uuid.uuidString.lowercased() {
      acceptedCall = nil
    }
    action.fulfill()
  }

  func onTimeOut(_ call: Call) {}

  func didActivateAudioSession(_ audioSession: AVAudioSession) {}

  func didDeactivateAudioSession(_ audioSession: AVAudioSession) {}
}
