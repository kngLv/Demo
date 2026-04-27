//
//  ScreenTimeReportExtension.swift
//  ScreenTimeReportExtension
//
//  Created by 吕康 on 2026/4/27.
//

import DeviceActivity
import ExtensionKit
import SwiftUI

@main
struct ScreenTimeReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        // Create a report for each DeviceActivityReport.Context that your app supports.
        TotalActivityReport { totalActivity in
            TotalActivityView(totalActivity: totalActivity)
        }
        // Add more reports here...
    }
}
