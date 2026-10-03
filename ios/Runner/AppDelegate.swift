import UIKit
import AVFoundation
import Flutter
import GoogleMaps
import Firebase
import PushKit
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate {
  /// Retenu par l'AppDelegate : un registry local serait desalloue et
  /// l'appareil ne recevrait jamais de push VoIP.
  private var voipRegistry: PKPushRegistry?

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

  // MARK: - Appel décroché alors que l'app était fermée

  /// App fermée : l'iPhone la relance quand on décroche depuis l'écran
  /// d'appel, mais l'événement « appel accepté » part avant que Flutter
  /// l'écoute. L'app le redemande ici au démarrage pour ouvrir l'appel.
  private func registerAcceptedCallChannel() {
    guard let registrar = self.registrar(forPlugin: "MisonAcceptedCall") else { return }
    let channel = FlutterMethodChannel(name: "mison/accepted_call", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "getAcceptedCall" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(SwiftFlutterCallkitIncomingPlugin.sharedInstance?.getAcceptedCall()?.toJSON())
    }
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
    let callData = Data(id: orderId, nameCaller: callerName, handle: orderId, type: 0)
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

      // Skip if this device initiated the call (SharedPreferences key on iOS)
      let outgoingId = UserDefaults.standard.string(forKey: "flutter.outgoing_call_order_id")
      if outgoingId != orderId, let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance {
        DispatchQueue.main.async {
          let callData = Data(id: orderId, nameCaller: callerName, handle: orderId, type: 0)
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
