import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 注册 Flutter 与 iOS 原生的通信通道
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

  // 分发 Flutter 端发来的方法调用
  private func handleScreenTimeCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 15.0, *) else {
      result(
        FlutterError(
          code: "UNSUPPORTED_IOS",
          message: "需要 iOS 15.0 及以上版本。",
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
            message: "未找到根视图控制器。",
            details: nil
          )
        )
        return
      }
      manager.pickApplications(from: root, result: result)
    case "openRestrictionCenter":
      guard let root = window?.rootViewController else {
        result(
          FlutterError(
            code: "NO_ROOT_VIEW_CONTROLLER",
            message: "未找到根视图控制器。",
            details: nil
          )
        )
        return
      }
      manager.openRestrictionCenter(from: root, result: result)
    case "openNativeUsageDashboard":
      guard let root = window?.rootViewController else {
        result(
          FlutterError(
            code: "NO_ROOT_VIEW_CONTROLLER",
            message: "未找到根视图控制器。",
            details: nil
          )
        )
        return
      }
      manager.openNativeUsageDashboard(from: root, result: result)
    case "showUsageReportForDay":
      guard let root = window?.rootViewController else {
        result(
          FlutterError(
            code: "NO_ROOT_VIEW_CONTROLLER",
            message: "未找到根视图控制器。",
            details: nil
          )
        )
        return
      }
      let args = call.arguments as? [String: Any]
      let daysAgo = args?["daysAgo"] as? Int ?? 0
      manager.showUsageReport(from: root, daysAgo: daysAgo, result: result)
    case "applyRestriction":
      manager.applyRestriction(result: result)
    case "configureTimedRestriction":
      let args = call.arguments as? [String: Any] ?? [:]
      manager.configureTimedRestriction(arguments: args, result: result)
    case "getTimedRestrictionStatus":
      manager.getTimedRestrictionStatus(result: result)
    case "cancelTimedRestriction":
      manager.cancelTimedRestriction(result: result)
    case "showUsageReport":
      guard let root = window?.rootViewController else {
        result(
          FlutterError(
            code: "NO_ROOT_VIEW_CONTROLLER",
            message: "未找到根视图控制器。",
            details: nil
          )
        )
        return
      }
      manager.showUsageReport(from: root, daysAgo: 0, result: result)
    case "clearRestriction":
      manager.clearRestriction(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
