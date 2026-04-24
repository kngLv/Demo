import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
  private let appGroupID = "group.com.lvkang.appdemo20260420.sh"
  private let selectionAppsKey = "timed_selection_apps"
  private let selectionCategoriesKey = "timed_selection_categories"
  private let selectionDomainsKey = "timed_selection_domains"
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

    let categoryTokens: Set<ActivityCategoryToken> = {
      guard
        let data = defaults.data(forKey: selectionCategoriesKey),
        let value = try? decoder.decode(Set<ActivityCategoryToken>.self, from: data)
      else { return [] }
      return value
    }()

    let domainTokens: Set<WebDomainToken> = {
      guard
        let data = defaults.data(forKey: selectionDomainsKey),
        let value = try? decoder.decode(Set<WebDomainToken>.self, from: data)
      else { return [] }
      return value
    }()

    let blockedApps = Set(appTokens.map { Application(token: $0) })
    store.application.blockedApplications = blockedApps.isEmpty ? nil : blockedApps
    store.shield.applications = nil
    store.shield.applicationCategories = categoryTokens.isEmpty
      ? nil
      : ShieldSettings.ActivityCategoryPolicy.specific(categoryTokens)
    store.shield.webDomains = domainTokens.isEmpty ? nil : domainTokens
  }

  private func clearAllRestrictions() {
    store.application.blockedApplications = nil
    store.shield.applications = nil
    store.shield.applicationCategories = nil
    store.shield.webDomainCategories = nil
    store.shield.webDomains = nil
  }
}
