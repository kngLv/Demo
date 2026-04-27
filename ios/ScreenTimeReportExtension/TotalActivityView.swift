//
//  TotalActivityView.swift
//  ScreenTimeReportExtension
//
//  Created by 吕康 on 2026/4/27.
//

import SwiftUI

struct TotalActivityView: View {
    let totalActivity: String
    
    var body: some View {
        VStack(spacing: 10) {
            Text("总使用时长")
                .font(.headline)
            Text(totalActivity)
                .font(.title3)
                .fontWeight(.semibold)
            Text("若显示“暂无使用数据”，可切换到昨天/前天再试。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .background(Color(.systemBackground))
    }
}

// In order to support previews for your extension's custom views, make sure its source files are
// members of your app's Xcode target as well as members of your extension's target. You can use
// Xcode's File Inspector to modify a file's Target Membership.
#Preview {
    TotalActivityView(totalActivity: "1h 23m")
}
