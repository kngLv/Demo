import FamilyControls
import Flutter
import ManagedSettings
import SwiftUI
import UIKit

@available(iOS 15.0, *)
final class ScreenTimeManager {
  static let shared = ScreenTimeManager()

  private let store = ManagedSettingsStore()
  private var selection = FamilyActivitySelection()

  private init() {}

  func requestAuthorization(result: @escaping FlutterResult) {
    Task {
      do {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        result("authorized")
      } catch {
        result(
          FlutterError(
            code: "AUTH_FAILED",
            message: "Screen Time authorization failed: \(error.localizedDescription)",
            details: nil
          )
        )
      }
    }
  }

  func pickApplications(from viewController: UIViewController, result: @escaping FlutterResult) {
    let picker = ScreenTimePickerViewController(initialSelection: selection) { [weak self] action, pickedSelection in
      guard let self else { return }
      viewController.dismiss(animated: true)
      switch action {
      case .cancel:
        result("cancelled")
      case .done:
        self.selection = pickedSelection
        let appCount = pickedSelection.applicationTokens.count
        let categoryCount = pickedSelection.categoryTokens.count
        result("selected apps: \(appCount), categories: \(categoryCount)")
      }
    }

    viewController.present(picker, animated: true)
  }

  func applyRestriction(result: @escaping FlutterResult) {
    let hasSelection =
      !selection.applicationTokens.isEmpty
      || !selection.categoryTokens.isEmpty
      || !selection.webDomainTokens.isEmpty
    if !hasSelection {
      result(
        FlutterError(
          code: "EMPTY_SELECTION",
          message: "No selected apps or categories. Please pick applications first.",
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
    result("restriction applied")
  }

  func clearRestriction(result: @escaping FlutterResult) {
    store.shield.applications = nil
    store.shield.applicationCategories = nil
    store.shield.webDomainCategories = nil
    result("restriction cleared")
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
        .navigationTitle("Pick Apps")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { onCancel(selection) }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { onDone(selection) }
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
