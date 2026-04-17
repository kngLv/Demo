import FamilyControls
import Flutter
import ManagedSettings
import SwiftUI
import UIKit

@available(iOS 15.0, *)
final class ScreenTimeManager {
  static let shared = ScreenTimeManager()

  private let store = ManagedSettingsStore()
  // 保存用户当前选中的应用/分类 token
  private var selection = FamilyActivitySelection()

  private init() {}

  // 申请 Screen Time 授权（个人模式）
  func requestAuthorization(result: @escaping FlutterResult) {
    Task {
      do {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        result("授权成功")
      } catch {
        result(
          FlutterError(
            code: "AUTH_FAILED",
            message: "屏幕使用时间授权失败：\(error.localizedDescription)",
            details: nil
          )
        )
      }
    }
  }

  // 弹出系统应用选择器，选择要限制的应用
  func pickApplications(from viewController: UIViewController, result: @escaping FlutterResult) {
    let picker = ScreenTimePickerViewController(initialSelection: selection) { [weak self] action, pickedSelection in
      guard let self else { return }
      viewController.dismiss(animated: true)
      switch action {
      case .cancel:
        result("已取消")
      case .done:
        self.selection = pickedSelection
        let appCount = pickedSelection.applicationTokens.count
        let categoryCount = pickedSelection.categoryTokens.count
        result("已选择应用 \(appCount) 个，分类 \(categoryCount) 个")
      }
    }

    viewController.present(picker, animated: true)
  }

  // 对已选 token 应用限制（shield）
  func applyRestriction(result: @escaping FlutterResult) {
    let hasSelection =
      !selection.applicationTokens.isEmpty
      || !selection.categoryTokens.isEmpty
      || !selection.webDomainTokens.isEmpty
    if !hasSelection {
      result(
        FlutterError(
          code: "EMPTY_SELECTION",
          message: "尚未选择应用或分类，请先选择应用。",
          details: nil
        )
      )
      return
    }

    store.shield.applications = selection.applicationTokens
    store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.specific(
      selection.categoryTokens
    )
    store.shield.webDomainCategories = ShieldSettings.ActivityCategoryPolicy.specific(
      selection.webDomainTokens
    )
    result("限制已生效")
  }

  // 清除所有限制
  func clearRestriction(result: @escaping FlutterResult) {
    store.shield.applications = nil
    store.shield.applicationCategories = nil
    store.shield.webDomainCategories = nil
    result("限制已解除")
  }
}

@available(iOS 15.0, *)
private enum PickerAction {
  case done
  case cancel
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
