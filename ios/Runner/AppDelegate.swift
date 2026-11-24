import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// True while this phone hosts a room.
  private var hosting = false
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NotificationCenter.default.addObserver(
      self, selector: #selector(didEnterBackground),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(willEnterForeground),
      name: UIApplication.willEnterForegroundNotification, object: nil)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MwgNative") else { return }
    let channel = FlutterMethodChannel(name: "mwg/native", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "startHosting":
        self?.hosting = true
        result(true)
      case "stopHosting":
        self?.hosting = false
        self?.endBackgroundTask()
        result(true)
      case "openCameraApp":
        // iOS has no public way to open the Camera app; the game shows its
        // own scanner instead.
        result(false)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// iOS suspends apps a few seconds after they go to the background. While
  /// hosting, ask for the extra time iOS allows (usually about 30 seconds) so
  /// a friend who taps the invite right away can still get in.
  @objc private func didEnterBackground() {
    guard hosting, backgroundTask == .invalid else { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "HostRoom") { [weak self] in
      self?.endBackgroundTask()
    }
  }

  @objc private func willEnterForeground() {
    endBackgroundTask()
  }

  private func endBackgroundTask() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }
}
