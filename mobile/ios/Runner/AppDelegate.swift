import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  let flutterEngine = FlutterEngine(name: "linkpad")
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    flutterEngine.run()
    FlutterMethodChannel(name: "linkpad/permissions", binaryMessenger: flutterEngine.binaryMessenger)
      .setMethodCallHandler { call, result in
        guard call.method == "openSettings" else { result(FlutterMethodNotImplemented); return }
        guard let url = URL(string: UIApplication.openSettingsURLString) else { result(false); return }
        UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
      }
    GeneratedPluginRegistrant.register(with: flutterEngine)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

@objc class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
             options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene,
          let delegate = UIApplication.shared.delegate as? AppDelegate else { return }
    let window = UIWindow(windowScene: windowScene)
    window.rootViewController = FlutterViewController(
      engine: delegate.flutterEngine, nibName: nil, bundle: nil)
    self.window = window
    delegate.window = window
    window.makeKeyAndVisible()
  }

  private func lifecycle(_ state: String) {
    guard let delegate = UIApplication.shared.delegate as? AppDelegate else { return }
    delegate.flutterEngine.lifecycleChannel.sendMessage("AppLifecycleState.\(state)")
  }

  func sceneDidBecomeActive(_ scene: UIScene) { lifecycle("resumed") }
  func sceneWillResignActive(_ scene: UIScene) { lifecycle("inactive") }
  func sceneWillEnterForeground(_ scene: UIScene) { lifecycle("inactive") }
  func sceneDidEnterBackground(_ scene: UIScene) { lifecycle("paused") }
  func sceneDidDisconnect(_ scene: UIScene) { lifecycle("detached") }
}
