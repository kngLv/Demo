import DeviceActivity
import FamilyControls
import Flutter
import ManagedSettings
import SwiftUI
import UIKit

@available(iOS 15.0, *)
final class ScreenTimeManager {
  static let shared = ScreenTimeManager()

  private let appGroupID = "group.com.lvkang.appdemo20260420.sh"
  private let selectionAppsKey = "timed_selection_apps"
  private let selectionCategoriesKey = "timed_selection_categories"
  private let selectionDomainsKey = "timed_selection_domains"
  private let timedStatusModeKey = "timed_status_mode"
  private let timedStatusMinutesKey = "timed_status_minutes"
  private let timedStatusStartMinuteKey = "timed_status_start_minute"
  private let timedStatusEndMinuteKey = "timed_status_end_minute"
  private let timedStatusUpdatedAtKey = "timed_status_updated_at"
  private let countdownActivityName = DeviceActivityName("TimedHide.Countdown")
  private let dailyActivityName = DeviceActivityName("TimedHide.DailyWindow")

  private let store = ManagedSettingsStore()
  // 保存用户当前选中的应用/分类 token
  private var selection = FamilyActivitySelection()

  private init() {}

  private func authErrorMessage(_ error: Error) -> String {
    let nsError = error as NSError
    return "屏幕使用时间授权失败：\(error.localizedDescription) [\(nsError.domain):\(nsError.code)]"
  }

  // 申请 Screen Time 授权（个人模式）
  func requestAuthorization(result: @escaping FlutterResult) {
    if #available(iOS 16.0, *) {
      Task {
        do {
          try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
          result("授权成功")
        } catch {
          result(
            FlutterError(
              code: "AUTH_FAILED",
              message: self.authErrorMessage(error),
              details: nil
            )
          )
        }
      }
      return
    }

    AuthorizationCenter.shared.requestAuthorization { authResult in
      switch authResult {
      case .success:
        result("授权成功")
      case .failure(let error):
        result(
          FlutterError(
            code: "AUTH_FAILED",
            message: self.authErrorMessage(error),
            details: nil
          )
        )
      }
    }
  }

  // 弹出系统应用选择器，选择要限制的应用
  func pickApplications(from viewController: UIViewController, result: @escaping FlutterResult) {
    pickApplicationsNative(from: viewController) { message in
      result(message)
    }
  }

  // 原生侧复用的选择器调用（不依赖 FlutterResult）
  func pickApplicationsNative(from viewController: UIViewController, completion: @escaping (String) -> Void) {
    let presenter = viewController.presentedViewController ?? viewController
    let picker = ScreenTimePickerViewController(initialSelection: selection) { [weak self] action, pickedSelection in
      guard let self else { return }
      presenter.dismiss(animated: true)
      switch action {
      case .cancel:
        completion("已取消")
      case .done:
        self.selection = pickedSelection
        let appCount = pickedSelection.applicationTokens.count
        let categoryCount = pickedSelection.categoryTokens.count
        completion("已选择应用 \(appCount) 个，分类 \(categoryCount) 个")
      }
    }

    presenter.present(picker, animated: true)
  }

  // 对已选 token 应用限制（shield）
  func applyRestriction(result: @escaping FlutterResult) {
    if !hasSelection() {
      result(
        FlutterError(
          code: "EMPTY_SELECTION",
          message: "尚未选择应用或分类，请先选择应用。",
          details: nil
        )
      )
      return
    }

    applySelectionRestriction()
    result("限制已生效")
  }

  // 方案：定时隐藏（倒计时 / 每日固定时段）
  func configureTimedRestriction(arguments: [String: Any], result: @escaping FlutterResult) {
    guard hasSelection() else {
      result(
        FlutterError(
          code: "EMPTY_SELECTION",
          message: "请先选择要隐藏的应用。",
          details: nil
        )
      )
      return
    }

    guard let mode = arguments["mode"] as? String else {
      result(
        FlutterError(
          code: "INVALID_ARGS",
          message: "缺少 mode 参数。",
          details: nil
        )
      )
      return
    }

    if mode == "countdown" {
      guard let minutes = arguments["minutes"] as? Int, minutes > 0 else {
        result(
          FlutterError(
            code: "INVALID_ARGS",
            message: "minutes 必须是大于等于 1 的整数。",
            details: nil
          )
        )
        return
      }
      do {
        try saveTimedSelectionToSharedStore()
        stopSystemTimedMonitoring()
        try startCountdownMonitoring(minutes: minutes)
        // 立即生效，后台结束由 Monitor Extension 在 intervalDidEnd 中清理。
        applySelectionRestriction()
        saveTimedStatus(
          mode: "countdown",
          minutes: minutes,
          startMinute: nil,
          endMinute: nil
        )
        result("已开启系统倒计时隐藏：\(minutes) 分钟")
      } catch {
        result(
          FlutterError(
            code: "SCHEDULE_FAILED",
            message: "配置系统倒计时失败：\(error.localizedDescription)",
            details: nil
          )
        )
      }
      return
    }

    if mode == "dailyWindow" {
      guard
        let startMinute = arguments["startMinute"] as? Int,
        let endMinute = arguments["endMinute"] as? Int,
        startMinute >= 0, startMinute < 1440,
        endMinute >= 0, endMinute < 1440,
        startMinute != endMinute
      else {
        result(
          FlutterError(
            code: "INVALID_ARGS",
            message: "startMinute/endMinute 参数不合法。",
            details: nil
          )
        )
        return
      }

      do {
        try saveTimedSelectionToSharedStore()
        stopSystemTimedMonitoring()
        try startDailyWindowMonitoring(startMinute: startMinute, endMinute: endMinute)
        // 当前时刻也同步一次，避免等待系统下次触发。
        if isNowInWindow(startMinute: startMinute, endMinute: endMinute) {
          applySelectionRestriction()
        } else {
          clearAllRestrictions()
        }
        saveTimedStatus(
          mode: "dailyWindow",
          minutes: nil,
          startMinute: startMinute,
          endMinute: endMinute
        )
        result("已开启系统每日时段隐藏：\(timeLabel(minute: startMinute)) - \(timeLabel(minute: endMinute))")
      } catch {
        result(
          FlutterError(
            code: "SCHEDULE_FAILED",
            message: "配置系统每日时段失败：\(error.localizedDescription)",
            details: nil
          )
        )
      }
      return
    }

    result(
      FlutterError(
        code: "INVALID_ARGS",
        message: "不支持的 mode：\(mode)",
        details: nil
      )
    )
  }

  func getTimedRestrictionStatus(result: @escaping FlutterResult) {
    guard let defaults = UserDefaults(suiteName: appGroupID) else {
      result(
        FlutterError(
          code: "APP_GROUP_UNAVAILABLE",
          message: "无法访问 App Group：\(appGroupID)",
          details: nil
        )
      )
      return
    }
    guard let mode = defaults.string(forKey: timedStatusModeKey) else {
      result([
        "enabled": false,
      ])
      return
    }
    var payload: [String: Any] = [
      "enabled": true,
      "mode": mode,
      "selectedAppCount": selection.applicationTokens.count,
      "selectedCategoryCount": selection.categoryTokens.count,
    ]
    if defaults.object(forKey: timedStatusMinutesKey) != nil {
      payload["minutes"] = defaults.integer(forKey: timedStatusMinutesKey)
    }
    if defaults.object(forKey: timedStatusStartMinuteKey) != nil {
      payload["startMinute"] = defaults.integer(forKey: timedStatusStartMinuteKey)
    }
    if defaults.object(forKey: timedStatusEndMinuteKey) != nil {
      payload["endMinute"] = defaults.integer(forKey: timedStatusEndMinuteKey)
    }
    if let ts = defaults.object(forKey: timedStatusUpdatedAtKey) as? Double {
      payload["updatedAt"] = ts
    }
    result(payload)
  }

  func cancelTimedRestriction(result: @escaping FlutterResult) {
    stopSystemTimedMonitoring()
    clearTimedStatus()
    clearAllRestrictions()
    result("已取消定时隐藏")
  }

  // 清除所有限制
  func clearRestriction(result: @escaping FlutterResult) {
    stopSystemTimedMonitoring()
    clearTimedStatus()
    clearAllRestrictions()
    result("限制已解除")
  }

  func openRestrictionCenter(from viewController: UIViewController, result: @escaping FlutterResult) {
    guard #available(iOS 16.0, *) else {
      result(
        FlutterError(
          code: "UNSUPPORTED_IOS",
          message: "该功能需要 iOS 16.0 及以上版本。",
          details: nil
        )
      )
      return
    }

    let centerView = RestrictionCenterView(
      initialAppTokens: Array(selection.applicationTokens),
      initialCategoryCount: selection.categoryTokens.count,
      initialTimedStatus: timedStatusText(),
      onAddApp: { [weak self, weak viewController] refresh in
        guard let self, let viewController else { return }
        self.pickApplicationsNative(from: viewController) { _ in
          refresh(
            Array(self.selection.applicationTokens),
            self.selection.categoryTokens.count,
            self.timedStatusText()
          )
        }
      },
      onApplyNow: { [weak self] update in
        self?.applyRestriction(result: { value in
          update(String(describing: value))
        })
      },
      onSetCountdown: { [weak self] minutes, update in
        self?.configureTimedRestriction(
          arguments: ["mode": "countdown", "minutes": minutes],
          result: { value in
            update(String(describing: value))
          }
        )
      },
      onSetDailyWindow: { [weak self] startMinute, endMinute, update in
        self?.configureTimedRestriction(
          arguments: ["mode": "dailyWindow", "startMinute": startMinute, "endMinute": endMinute],
          result: { value in
            update(String(describing: value))
          }
        )
      },
      onCancelTimed: { [weak self] update in
        self?.cancelTimedRestriction(result: { value in
          update(String(describing: value))
        })
      },
      onRefreshTimedStatus: { [weak self] update in
        guard let self else { return }
        update(self.timedStatusText())
      }
    )
    let host = UIHostingController(rootView: centerView)
    host.modalPresentationStyle = .pageSheet
    viewController.present(host, animated: true)
    result("已打开应用限制与定时页面")
  }

  // 展示系统使用时长报告（需要 iOS 16+）
  func showUsageReport(from viewController: UIViewController, daysAgo: Int, result: @escaping FlutterResult) {
    guard #available(iOS 16.0, *) else {
      result(
        FlutterError(
          code: "UNSUPPORTED_IOS",
          message: "使用时长报告需要 iOS 16.0 及以上版本。",
          details: nil
        )
      )
      return
    }

    let hasSelection =
      !selection.applicationTokens.isEmpty
      || !selection.categoryTokens.isEmpty
      || !selection.webDomainTokens.isEmpty
    if !hasSelection {
      result(
        FlutterError(
          code: "EMPTY_SELECTION",
          message: "请先选择要查看时长的应用或分类。",
          details: nil
        )
      )
      return
    }

    let report = ScreenTimeReportView(filter: usageFilter(daysAgo: daysAgo), onClose: {
      viewController.dismiss(animated: true)
    })
    let host = UIHostingController(rootView: report)
    host.modalPresentationStyle = .formSheet
    let presenter = viewController.presentedViewController ?? viewController
    presenter.present(host, animated: true)
    result("已打开使用时长报告")
  }

  // 方案 1：原生定制页面（顶部选择+日期切换+报告入口）
  func openNativeUsageDashboard(from viewController: UIViewController, result: @escaping FlutterResult) {
    guard #available(iOS 16.0, *) else {
      result(
        FlutterError(
          code: "UNSUPPORTED_IOS",
          message: "使用时长报告需要 iOS 16.0 及以上版本。",
          details: nil
        )
      )
      return
    }

    let dashboard = NativeUsageDashboardView(
      initialSummary: selectionSummaryText(),
      onAddApp: { [weak self, weak viewController] refresh in
        guard let self, let viewController else { return }
        self.pickApplicationsNative(from: viewController) { _ in
          refresh(self.selectionSummaryText())
        }
      },
      onShowReport: { [weak self, weak viewController] daysAgo in
        guard let self, let viewController else { return }
        self.showUsageReport(from: viewController, daysAgo: daysAgo) { _ in }
      }
    )
    let host = UIHostingController(rootView: dashboard)
    host.modalPresentationStyle = UIModalPresentationStyle.pageSheet
    viewController.present(host, animated: true)
    result("已打开原生定制页")
  }

  private func selectionSummaryText() -> String {
    "应用 \(selection.applicationTokens.count) 个，分类 \(selection.categoryTokens.count) 个"
  }

  private func hasSelection() -> Bool {
    !selection.applicationTokens.isEmpty
      || !selection.categoryTokens.isEmpty
      || !selection.webDomainTokens.isEmpty
  }

  private func applySelectionRestriction() {
    let blockedApps = Set(selection.applicationTokens.map { Application(token: $0) })
    store.application.blockedApplications = blockedApps.isEmpty ? nil : blockedApps
    // App 级别改为 blockedApplications，避免仍然只是 shield 覆盖效果。
    store.shield.applications = nil
    store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.specific(
      selection.categoryTokens
    )
    store.shield.webDomains = selection.webDomainTokens
  }

  private func clearAllRestrictions() {
    store.application.blockedApplications = nil
    store.shield.applications = nil
    store.shield.applicationCategories = nil
    store.shield.webDomainCategories = nil
    store.shield.webDomains = nil
  }

  private func stopSystemTimedMonitoring() {
    let center = DeviceActivityCenter()
    center.stopMonitoring([countdownActivityName, dailyActivityName])
  }

  private func isNowInWindow(startMinute: Int, endMinute: Int) -> Bool {
    let now = Date()
    let components = Calendar.current.dateComponents([.hour, .minute], from: now)
    let nowMinute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
    if startMinute < endMinute {
      return nowMinute >= startMinute && nowMinute < endMinute
    }
    return nowMinute >= startMinute || nowMinute < endMinute
  }

  private func timeLabel(minute: Int) -> String {
    String(format: "%02d:%02d", minute / 60, minute % 60)
  }

  private func startCountdownMonitoring(minutes: Int) throws {
    let calendar = Calendar.current
    let now = Date()
    // 从“下一整分钟”开始，避免 start/end 被系统判定为同一时间窗口。
    let nextMinute = calendar.date(byAdding: .minute, value: 1, to: now) ?? now
    let start = calendar.date(
      from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nextMinute)
    ) ?? nextMinute
    let end = calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
    guard end > start else {
      throw NSError(
        domain: "ScreenTimeManager",
        code: -2,
        userInfo: [NSLocalizedDescriptionKey: "倒计时结束时间必须晚于开始时间"]
      )
    }
    let startComp = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: start
    )
    let endComp = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: end
    )
    let schedule = DeviceActivitySchedule(
      intervalStart: startComp,
      intervalEnd: endComp,
      repeats: false
    )
    try DeviceActivityCenter().startMonitoring(countdownActivityName, during: schedule)
  }

  private func startDailyWindowMonitoring(startMinute: Int, endMinute: Int) throws {
    let startHour = startMinute / 60
    let startMin = startMinute % 60
    let endHour = endMinute / 60
    let endMin = endMinute % 60
    var startComp = DateComponents()
    startComp.hour = startHour
    startComp.minute = startMin
    var endComp = DateComponents()
    endComp.hour = endHour
    endComp.minute = endMin
    let schedule = DeviceActivitySchedule(
      intervalStart: startComp,
      intervalEnd: endComp,
      repeats: true
    )
    try DeviceActivityCenter().startMonitoring(dailyActivityName, during: schedule)
  }

  private func saveTimedSelectionToSharedStore() throws {
    guard let defaults = UserDefaults(suiteName: appGroupID) else {
      throw NSError(
        domain: "ScreenTimeManager",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "无法访问 App Group：\(appGroupID)"]
      )
    }
    let encoder = PropertyListEncoder()
    defaults.set(try encoder.encode(selection.applicationTokens), forKey: selectionAppsKey)
    defaults.set(try encoder.encode(selection.categoryTokens), forKey: selectionCategoriesKey)
    defaults.set(try encoder.encode(selection.webDomainTokens), forKey: selectionDomainsKey)
  }

  private func saveTimedStatus(
    mode: String,
    minutes: Int?,
    startMinute: Int?,
    endMinute: Int?
  ) {
    guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
    defaults.set(mode, forKey: timedStatusModeKey)
    if let minutes {
      defaults.set(minutes, forKey: timedStatusMinutesKey)
    } else {
      defaults.removeObject(forKey: timedStatusMinutesKey)
    }
    if let startMinute {
      defaults.set(startMinute, forKey: timedStatusStartMinuteKey)
    } else {
      defaults.removeObject(forKey: timedStatusStartMinuteKey)
    }
    if let endMinute {
      defaults.set(endMinute, forKey: timedStatusEndMinuteKey)
    } else {
      defaults.removeObject(forKey: timedStatusEndMinuteKey)
    }
    defaults.set(Date().timeIntervalSince1970, forKey: timedStatusUpdatedAtKey)
  }

  private func clearTimedStatus() {
    guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
    defaults.removeObject(forKey: timedStatusModeKey)
    defaults.removeObject(forKey: timedStatusMinutesKey)
    defaults.removeObject(forKey: timedStatusStartMinuteKey)
    defaults.removeObject(forKey: timedStatusEndMinuteKey)
    defaults.removeObject(forKey: timedStatusUpdatedAtKey)
  }

  private func timedStatusText() -> String {
    guard let defaults = UserDefaults(suiteName: appGroupID) else {
      return "状态读取失败：无法访问 App Group"
    }
    guard let mode = defaults.string(forKey: timedStatusModeKey) else {
      return "当前未开启系统定时隐藏"
    }
    if mode == "countdown" {
      let minutes = defaults.integer(forKey: timedStatusMinutesKey)
      return "当前计划：倒计时 \(minutes) 分钟"
    }
    if mode == "dailyWindow" {
      let start = defaults.integer(forKey: timedStatusStartMinuteKey)
      let end = defaults.integer(forKey: timedStatusEndMinuteKey)
      return "当前计划：每日 \(timeLabel(minute: start)) - \(timeLabel(minute: end))"
    }
    return "当前计划：未知模式 \(mode)"
  }

  @available(iOS 16.0, *)
  private var usageFilter: DeviceActivityFilter {
    usageFilter(daysAgo: 0)
  }

  @available(iOS 16.0, *)
  private func usageFilter(daysAgo: Int) -> DeviceActivityFilter {
    let calendar = Calendar.current
    let now = Date()
    let target = calendar.date(byAdding: .day, value: -max(0, daysAgo), to: now) ?? now
    let startOfDay = calendar.startOfDay(for: target)
    let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) ?? now
    return DeviceActivityFilter(
      segment: .daily(during: DateInterval(start: startOfDay, end: min(endOfDay, now))),
      users: .all,
      devices: .init([.iPhone]),
      applications: selection.applicationTokens,
      categories: selection.categoryTokens,
      webDomains: selection.webDomainTokens
    )
  }
}

@available(iOS 15.0, *)
private enum PickerAction {
  case done
  case cancel
}

@available(iOS 16.0, *)
private struct ScreenTimeReportView: View {
  let filter: DeviceActivityFilter
  let onClose: () -> Void

  var body: some View {
    NavigationView {
      DeviceActivityReport(.totalActivity, filter: filter)
        .navigationTitle("使用时长")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("关闭") { onClose() }
          }
        }
    }
  }
}

@available(iOS 16.0, *)
private struct NativeUsageDashboardView: View {
  @State private var selectedDaysAgo = 0
  @State private var summaryText: String
  let onAddApp: (@escaping (String) -> Void) -> Void
  let onShowReport: (Int) -> Void

  init(
    initialSummary: String,
    onAddApp: @escaping (@escaping (String) -> Void) -> Void,
    onShowReport: @escaping (Int) -> Void
  ) {
    _summaryText = State(initialValue: initialSummary)
    self.onAddApp = onAddApp
    self.onShowReport = onShowReport
  }

  var body: some View {
    NavigationView {
      VStack(alignment: .leading, spacing: 12) {
        Text("已选：\(summaryText)")
          .font(.subheadline)
        HStack {
          Button("添加 App") {
            onAddApp { newText in
              summaryText = newText
            }
          }
          Spacer()
        }
        Picker("日期", selection: $selectedDaysAgo) {
          ForEach(0..<7, id: \.self) { offset in
            Text(label(for: offset)).tag(offset)
          }
        }
        .pickerStyle(.menu)
        Button("打开使用时长报告") {
          onShowReport(selectedDaysAgo)
        }
        Spacer()
      }
      .padding(16)
      .navigationTitle("原生定制页")
    }
  }

  private func label(for daysAgo: Int) -> String {
    if daysAgo == 0 { return "今天" }
    if daysAgo == 1 { return "昨天" }
    return "\(daysAgo) 天前"
  }
}

@available(iOS 16.0, *)
private struct RestrictionCenterView: View {
  @State private var appTokens: [ApplicationToken]
  @State private var categoryCount: Int
  @State private var timedStatus: String
  @State private var opStatus = "准备就绪"
  @State private var mode: RestrictionTimedMode = .countdown
  @State private var countdownMinutes: Double = 60
  @State private var startMinute = 22 * 60
  @State private var endMinute = 7 * 60

  let onAddApp: (@escaping ([ApplicationToken], Int, String) -> Void) -> Void
  let onApplyNow: (@escaping (String) -> Void) -> Void
  let onSetCountdown: (Int, @escaping (String) -> Void) -> Void
  let onSetDailyWindow: (Int, Int, @escaping (String) -> Void) -> Void
  let onCancelTimed: (@escaping (String) -> Void) -> Void
  let onRefreshTimedStatus: (@escaping (String) -> Void) -> Void

  init(
    initialAppTokens: [ApplicationToken],
    initialCategoryCount: Int,
    initialTimedStatus: String,
    onAddApp: @escaping (@escaping ([ApplicationToken], Int, String) -> Void) -> Void,
    onApplyNow: @escaping (@escaping (String) -> Void) -> Void,
    onSetCountdown: @escaping (Int, @escaping (String) -> Void) -> Void,
    onSetDailyWindow: @escaping (Int, Int, @escaping (String) -> Void) -> Void,
    onCancelTimed: @escaping (@escaping (String) -> Void) -> Void,
    onRefreshTimedStatus: @escaping (@escaping (String) -> Void) -> Void
  ) {
    _appTokens = State(initialValue: initialAppTokens)
    _categoryCount = State(initialValue: initialCategoryCount)
    _timedStatus = State(initialValue: initialTimedStatus)
    self.onAddApp = onAddApp
    self.onApplyNow = onApplyNow
    self.onSetCountdown = onSetCountdown
    self.onSetDailyWindow = onSetDailyWindow
    self.onCancelTimed = onCancelTimed
    self.onRefreshTimedStatus = onRefreshTimedStatus
  }

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          Text("当前隐藏目标").font(.headline)
          if appTokens.isEmpty {
            Text("暂无已选应用，分类 \(categoryCount) 个")
              .foregroundColor(.secondary)
          } else {
            ForEach(Array(appTokens.enumerated()), id: \.offset) { index, token in
              VStack(alignment: .leading, spacing: 2) {
                Label(token)
                  .labelStyle(.titleAndIcon)
                Text("应用 \(index + 1)：\(String(describing: token))")
                  .font(.caption2)
                  .foregroundColor(.secondary)
              }
            }
            Text("分类 \(categoryCount) 个")
              .foregroundColor(.secondary)
            Text("若名称/图标未展示，表示系统未返回可读信息，已用 token 摘要兜底。")
              .font(.caption2)
              .foregroundColor(.secondary)
          }

          HStack {
            Button("添加/更新应用") {
              onAddApp { newApps, newCategories, newTimedStatus in
                appTokens = newApps
                categoryCount = newCategories
                timedStatus = newTimedStatus
                opStatus = "已更新选择：应用 \(newApps.count) 个，分类 \(newCategories) 个"
              }
            }
            Spacer()
            Button("立即应用限制") {
              onApplyNow { text in
                opStatus = text
              }
            }
          }

          Divider()
          Text("定时隐藏").font(.headline)
          Picker("模式", selection: $mode) {
            Text("倒计时").tag(RestrictionTimedMode.countdown)
            Text("每日时段").tag(RestrictionTimedMode.dailyWindow)
          }
          .pickerStyle(.segmented)

          if mode == .countdown {
            Text("时长：\(Int(countdownMinutes)) 分钟")
            Slider(value: $countdownMinutes, in: 1...480, step: 1)
            Button("开启倒计时隐藏") {
              onSetCountdown(Int(countdownMinutes)) { text in
                opStatus = text
                onRefreshTimedStatus { timedStatus = $0 }
              }
            }
          } else {
            HStack {
              Text("开始")
              Picker("开始", selection: $startMinute) {
                ForEach(Array(stride(from: 0, to: 1440, by: 30)), id: \.self) { minute in
                  Text(Self.hhmm(minute)).tag(minute)
                }
              }
            }
            HStack {
              Text("结束")
              Picker("结束", selection: $endMinute) {
                ForEach(Array(stride(from: 0, to: 1440, by: 30)), id: \.self) { minute in
                  Text(Self.hhmm(minute)).tag(minute)
                }
              }
            }
            Button("开启每日时段隐藏") {
              onSetDailyWindow(startMinute, endMinute) { text in
                opStatus = text
                onRefreshTimedStatus { timedStatus = $0 }
              }
            }
          }

          HStack {
            Button("取消定时隐藏") {
              onCancelTimed { text in
                opStatus = text
                onRefreshTimedStatus { timedStatus = $0 }
              }
            }
            Spacer()
            Button("刷新状态") {
              onRefreshTimedStatus { timedStatus = $0 }
            }
          }
          Text("系统调度：\(timedStatus)")
          Text("操作结果：\(opStatus)").foregroundColor(.secondary)
        }
        .padding(16)
      }
      .navigationTitle("应用限制与定时")
    }
  }

  private static func hhmm(_ minute: Int) -> String {
    String(format: "%02d:%02d", minute / 60, minute % 60)
  }
}

@available(iOS 16.0, *)
private enum RestrictionTimedMode {
  case countdown
  case dailyWindow
}

@available(iOS 16.0, *)
private extension DeviceActivityReport.Context {
  static let totalActivity = Self("TotalActivity")
}

@available(iOS 15.0, *)
private struct ScreenTimePickerRootView: View {
  @State private var selection: FamilyActivitySelection
  let onDone: (FamilyActivitySelection) -> Void
  let onCancel: (FamilyActivitySelection) -> Void

  init(
    initialSelection: FamilyActivitySelection,
    onDone: @escaping (FamilyActivitySelection) -> Void,
    onCancel: @escaping (FamilyActivitySelection) -> Void
  ) {
    _selection = State(initialValue: initialSelection)
    self.onDone = onDone
    self.onCancel = onCancel
  }

  var body: some View {
    NavigationView {
      FamilyActivityPicker(selection: $selection)
        .navigationTitle("选择应用")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("取消") { onCancel(selection) }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("完成") { onDone(selection) }
          }
        }
    }
  }
}

@available(iOS 15.0, *)
private final class ScreenTimePickerViewController: UIViewController {
  private let onFinish: (PickerAction, FamilyActivitySelection) -> Void
  private let initialSelection: FamilyActivitySelection

  init(
    initialSelection: FamilyActivitySelection,
    onFinish: @escaping (PickerAction, FamilyActivitySelection) -> Void
  ) {
    self.initialSelection = initialSelection
    self.onFinish = onFinish
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .fullScreen
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    let rootView = ScreenTimePickerRootView(
      initialSelection: initialSelection,
      onDone: { [weak self] selection in
        guard let self else { return }
        self.onFinish(.done, selection)
      },
      onCancel: { [weak self] selection in
        guard let self else { return }
        self.onFinish(.cancel, selection)
      }
    )
    let host = UIHostingController(rootView: rootView)
    addChild(host)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(host.view)
    NSLayoutConstraint.activate([
      host.view.topAnchor.constraint(equalTo: view.topAnchor),
      host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
    host.didMove(toParent: self)
  }
}
