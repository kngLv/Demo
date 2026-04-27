import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
  private let appGroupID = "group.com.lvkang.appdemo20260420.sh"
  private let selectionAppsKey = "timed_selection_apps"
  private let store = ManagedSettingsStore()

  override func intervalDidStart(for activity: DeviceActivityName) {
    super.intervalDidStart(for: activity)
    applySelectionRestrictions()
  }

  override func intervalDidEnd(for activity: DeviceActivityName) {
    super.intervalDidEnd(for: activity)
    clearAllRestrictions()
  }

  private func applySelectionRestrictions() {
    guard let defaults = UserDefaults(suiteName: appGroupID) else {
      clearAllRestrictions()
      return
    }

    let decoder = PropertyListDecoder()

    let appTokens: Set<ApplicationToken> = {
      guard
        let data = defaults.data(forKey: selectionAppsKey),
        let value = try? decoder.decode(Set<ApplicationToken>.self, from: data)
      else { return [] }
      return value
    }()

    let blockedApps = Set(appTokens.map { Application(token: $0) })
    store.application.blockedApplications = blockedApps.isEmpty ? nil : blockedApps
    store.shield.applications = nil
    store.shield.applicationCategories = nil
    store.shield.webDomainCategories = nil
    store.shield.webDomains = nil
  }

  private func clearAllRestrictions() {
    store.application.blockedApplications = nil
    store.shield.applications = nil
    store.shield.applicationCategories = nil
    store.shield.webDomainCategories = nil
    store.shield.webDomains = nil
  }
}
