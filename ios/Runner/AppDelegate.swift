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
    GMSServices.provideAPIKey("AIzaSyBtos9vMzqgH_Z9USy6eYMBtftzvhDYZhI")

    // PushKit : seul canal qui reveille une app iOS terminee pour un appel.
    registerForVoIPPushes()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Haut-parleur pendant un appel

  /// CallKit possede la session audio (Agora configure pour ne pas y toucher) :
  /// setEnableSpeakerphone d'Agora est alors sans effet. La sortie est basculee
  /// ici, directement sur la session audio.
  private func registerAudioRouteChannel() {
    guard let registrar = self.registrar(forPlugin: "MisonAudioRoute") else { return }
    let channel = FlutterMethodChannel(name: "mison/audio_route", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "setSpeaker" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let speakerOn = (call.arguments as? Bool) ?? true
      do {
        try AVAudioSession.sharedInstance().overrideOutputAudioPort(speakerOn ? .speaker : .none)
        result(nil)
      } catch {
        result(FlutterError(code: "AUDIO_ROUTE", message: error.localizedDescription, details: nil))
      }
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
    callData.appName = "Mison"
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
          callData.appName = "Mison"
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
