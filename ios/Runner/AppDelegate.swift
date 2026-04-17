import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "app_demo/screen_time",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        self.handleScreenTimeCall(call: call, result: result)
      }
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleScreenTimeCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 15.0, *) else {
      result(
        FlutterError(
          code: "UNSUPPORTED_IOS",
          message: "Requires iOS 15.0 or later.",
          details: nil
        )
      )
      return
    }

    let manager = ScreenTimeManager.shared

    switch call.method {
    case "requestAuthorization":
      manager.requestAuthorization(result: result)
    case "pickApplications":
      guard let root = window?.rootViewController else {
        result(
          FlutterError(
            code: "NO_ROOT_VIEW_CONTROLLER",
            message: "No root view controller available.",
            details: nil
          )
        )
        return
      }
      manager.pickApplications(from: root, result: result)
    case "applyRestriction":
      manager.applyRestriction(result: result)
    case "clearRestriction":
      manager.clearRestriction(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
