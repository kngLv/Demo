# Demo 项目实现文档（iOS Screen Time 应用限制/定时/使用时长）

本文档用于把当前项目完整复刻到另一个 Flutter+iOS 项目中。内容覆盖：

- 已实现功能
- 架构与调用链路
- 关键代码与参数
- Xcode/Apple Developer 配置
- 扩展（Monitor/Report）配置步骤
- 常见报错与排查
- 新项目复用步骤（可直接照做）

---

## 1. 项目目标与能力边界

### 1.1 当前已实现目标

1. 申请 Screen Time 授权（FamilyControls）。
2. 选择要管理的应用（FamilyActivityPicker）。
3. 立即隐藏/限制选中的应用（ManagedSettings）。
4. 系统后台定时隐藏：
   - 倒计时模式（最小 15 分钟）
   - 每日时段模式（5 分钟粒度）
5. 在原生页面查看当前定时配置、是否生效、剩余时间（倒计时）。
6. 使用时长报告入口（iOS 17+）：
   - 原生定制页入口
   - Flutter 桥接页入口
   - 系统报告页入口
7. 支持跨进程共享状态（App + Extension 通过 App Group）。

### 1.2 平台能力边界（非常重要）

1. `FamilyActivityPicker` 只能在真机使用，模拟器通常为空或不可用。
2. Screen Time 相关能力需要 Apple Developer Team + capability 开通。
3. 使用时长报告扩展（DeviceActivityReportExtension）在本项目按 `iOS 17+` 处理。
4. 选择结果中的应用名称/图标由系统隐私策略决定，不保证总能解析出完整可读信息。

---

## 2. 代码结构总览

### 2.1 Flutter 层

- `lib/main.dart`
  - 主页面按钮触发 iOS 原生方法
  - `MethodChannel('app_demo/screen_time')`
  - 包含 `FlutterBridgeReportPage`

### 2.2 iOS 主应用（Runner）

- `ios/Runner/AppDelegate.swift`
  - 注册 MethodChannel
  - 分发 Flutter 方法到 `ScreenTimeManager`

- `ios/Runner/ScreenTimeManager.swift`
  - 核心业务实现：授权、选应用、限制、定时、状态、报告页面
  - 内置多个 SwiftUI 视图（限制中心、原生报告页、选择器容器）

### 2.3 iOS 扩展

- `ios/ScreenTimeMonitorExtension/DeviceActivityMonitorExtension.swift`
  - 系统调度回调：区间开始时应用限制，结束时解除限制

- `ios/ScreenTimeReportExtension/*`
  - 报告扩展实现（TotalActivity）
  - `ScreenTimeReportExtension.swift`
  - `TotalActivityReport.swift`
  - `TotalActivityView.swift`

### 2.4 工程配置文件

- `ios/Runner/Runner.entitlements`
- `ios/ScreenTimeMonitorExtension/ScreenTimeMonitorExtension.entitlements`
- `ios/ScreenTimeReportExtension/ScreenTimeReportExtension.entitlements`
- `ios/Runner.xcodeproj/project.pbxproj`（target、bundle id、签名、嵌入扩展）

---

## 3. Flutter -> iOS 方法清单（接口契约）

MethodChannel: `app_demo/screen_time`

| 方法名 | 参数 | 说明 |
|---|---|---|
| `requestAuthorization` | 无 | 申请 Screen Time 授权 |
| `pickApplications` | 无 | 打开系统应用选择器 |
| `openRestrictionCenter` | 无 | 打开“应用限制与定时”原生页 |
| `applyRestriction` | 无 | 立即限制已选应用 |
| `configureTimedRestriction` | `mode=countdown,dailyWindow` | 配置系统定时 |
| `getTimedRestrictionStatus` | 无 | 查询当前定时状态 |
| `cancelTimedRestriction` | 无 | 取消定时并解除限制 |
| `clearRestriction` | 无 | 清空所有限制 |
| `openNativeUsageDashboard` | 无 | 打开原生使用时长页（iOS 17+） |
| `showUsageReport` | 无 | 打开系统报告页（今天，iOS 17+） |
| `showUsageReportForDay` | `daysAgo:int` | 按天查看报告（iOS 17+） |

`configureTimedRestriction` 参数约定：

1. 倒计时：`{"mode":"countdown","minutes":15...480}`
2. 每日时段：`{"mode":"dailyWindow","startMinute":0...1439,"endMinute":0...1439}`（且开始结束不能相同）

---

## 4. 核心实现逻辑

## 4.1 授权

- 文件：`ScreenTimeManager.requestAuthorization`
- iOS 16+ 使用 async/await：
  - `AuthorizationCenter.shared.requestAuthorization(for: .individual)`
- 旧系统走 completion 版本
- 失败统一返回 `AUTH_FAILED`

## 4.2 选择应用

- 文件：`ScreenTimeManager.pickApplicationsNative`
- 通过 `FamilyActivityPicker` 选择应用/分类/域名 token
- 当前限制逻辑只对“具体应用 token”生效，分类仅记录统计
- 选择完成后：
  1. 更新内存 `selection`
  2. 保存应用名映射（能拿到则保存）
  3. 保存 token 到 App Group（供扩展读取）

## 4.3 立即限制

- 文件：`applySelectionRestriction()`
- 关键行为：
  - `store.application.blockedApplications = Set(Application(token: ...))`
  - 清空 `store.shield.*`，避免分类盾导致“变灰/不一致体验”

## 4.4 定时限制（系统后台调度）

- 入口：`configureTimedRestriction`
- 调度框架：`DeviceActivityCenter.startMonitoring(...)`

### 倒计时模式

1. 要求 `minutes >= 15`
2. 调度开始点取“下一整分钟”，避免 schedule 太短/无效
3. `repeats = false`
4. 立即在前台先应用一次限制
5. 结束时由 Monitor Extension 的 `intervalDidEnd` 解除限制

### 每日时段模式

1. 支持跨天区间（例如 22:00 -> 07:00）
2. `repeats = true`
3. 配置后立即判断当前是否在窗口内：
   - 在窗口内：立即限制
   - 不在窗口内：立即解除

## 4.5 状态持久化与恢复

App Group: `group.com.lvkang.appdemo20260420.sh`

UserDefaults(suiteName) 存储键（核心）：

- `timed_selection_apps`
- `timed_selection_categories`
- `timed_selection_domains`
- `timed_selection_app_names`
- `timed_status_mode`
- `timed_status_minutes`
- `timed_status_start_minute`
- `timed_status_end_minute`
- `timed_status_countdown_end_at`
- `timed_status_updated_at`

作用：

1. App 重启后恢复上次选择和计划。
2. Monitor Extension 可读取相同数据执行后台限制。

## 4.6 监控扩展（后台生效关键）

- 文件：`DeviceActivityMonitorExtension.swift`
- 回调：
  - `intervalDidStart` -> 应用限制
  - `intervalDidEnd` -> 清除限制

没有这个扩展，系统后台到点时无法可靠执行切换。

## 4.7 使用时长报告

- App 侧：`DeviceActivityReport(.totalActivity, filter: ...)`
- Report Extension 侧：
  - 定义 `DeviceActivityReport.Context.totalActivity = "TotalActivity"`
  - 汇总 `totalActivityDuration`
- 两端 `Context` 字符串必须一致（本项目是 `TotalActivity`）

---

## 5. Xcode Target 与职责

在 `Runner.xcworkspace` 中主要有 3 个 Target：

1. `Runner`
   - 主 App（Flutter 宿主）
2. `ScreenTimeMonitorExtension`
   - 设备活动监控扩展，处理后台定时开始/结束
3. `ScreenTimeReportExtension`
   - 使用时长报告 UI 扩展

`RunnerTests` 只是测试 target，不参与线上能力。

---

## 6. 签名与 Capability 配置（必须按 target 分开配置）

以下步骤是“可跑起来”的关键。

### 6.1 Apple Developer 账号与协议

1. 使用付费开发者团队（Personal Team 不支持 Family Controls）。
2. 登录 [Apple Developer](https://developer.apple.com/account/)。
3. 若提示 PLA 更新，先同意最新协议，否则会报 `PLA Update available`。

### 6.2 Bundle Identifier 规范

示例：

1. App: `com.yourcompany.yourapp`
2. Monitor: `com.yourcompany.yourapp.ScreenTimeMonitorExtension`
3. Report: `com.yourcompany.yourapp.ScreenTimeReportExtension`

要求：全局唯一，不能用 `com.example.*`。

### 6.3 各 target 签名

在 Xcode 中分别选中 `Runner` / `ScreenTimeMonitorExtension` / `ScreenTimeReportExtension`：

1. 勾选 `Automatically manage signing`
2. Team 选同一个付费团队
3. 检查各自 Bundle ID 唯一且匹配

### 6.4 Capability 添加规则

#### Runner target

1. `Family Controls (Development)`
2. `App Groups`（勾选同一 group）

#### ScreenTimeMonitorExtension target

1. `Family Controls (Development)`
2. `App Groups`（必须与 Runner 相同）

#### ScreenTimeReportExtension target

1. `Family Controls (Development)`
2. 是否加 App Groups：本项目报告扩展不依赖共享存储，可不加；若要共享数据可加同一个 group

### 6.5 App Group 要点

本项目使用：`group.com.lvkang.appdemo20260420.sh`

必须满足：

1. Apple Developer 后台先创建/启用该 App Group ID
2. Runner 和 Monitor Extension 都勾选这个 group
3. entitlement 文件里值与后台完全一致

否则常见报错：

- profile 不支持 `com.apple.security.application-groups`
- profile 不支持 `group.xxx`

### 6.6 设备注册

真机调试时，若提示设备未注册：

1. Xcode `Window > Devices and Simulators`
2. 连接设备并点击 `Register Device`
3. 回到 target 的 Signing 页面重试

---

## 7. extension embedding 检查

在 `Runner target > Build Phases > Embed App Extensions` 中应包含：

1. `ScreenTimeMonitorExtension.appex`
2. `ScreenTimeReportExtension.appex`

若未嵌入，安装时可能失败，或运行时提示扩展缺失。

---

## 8. 版本兼容建议

### iOS 16.x

1. 授权/选应用/立即限制/系统定时（Monitor）可用。
2. 使用时长报告扩展在当前实现按 iOS 17+ 处理。

### iOS 17+

1. 上述功能全部可用。
2. 可使用 `showUsageReport*` 和原生 usage dashboard。

---

## 9. 常见问题与对应原因

### 9.1 `Cannot find 'ScreenTimeManager' in scope`

原因：`ScreenTimeManager.swift` 未加入 Runner target membership 或文件未编译进主 target。

处理：

1. 选中该文件 -> File Inspector -> Target Membership 勾选 `Runner`。
2. Product > Clean Build Folder 后重编译。

### 9.2 `AUTH_FAILED Couldn't communicate with a helper application`

常见原因：

1. 用了模拟器
2. 未开通 Family Controls capability
3. 签名/profile 不完整

### 9.3 `No profiles for ... were found`

原因：自动签名关闭、Bundle ID 不唯一、设备未注册、扩展 target 未签名。

处理：

1. 三个 target 全开自动签名
2. 使用唯一 Bundle ID
3. 注册设备
4. 清理 DerivedData 后重建

### 9.4 `Provisioning profile doesn't include App Groups capability`

原因：后台未给 App ID 开启 App Groups 或 profile 未刷新。

处理：

1. Developer 后台启用 App Groups
2. Xcode 重新拉取 profile（切换一次 team 或重试 signing）

### 9.5 `The activity's schedule is too short`

原因：系统对后台调度最短时长有限制。

本项目处理：倒计时最小时长限制为 15 分钟。

### 9.6 模拟器选择应用为空

这是系统能力限制，`FamilyActivityPicker` 需真机环境。

### 9.7 选中的应用名称/图标显示不稳定

由于 Screen Time token 与隐私策略限制，不保证每个 token 都能稳定解析到可读名称和图标。

---

## 10. 新项目复刻步骤（逐步执行）

以下步骤可让你在新 Flutter 项目快速复刻。

1. 创建 Flutter 项目，先确保 iOS 真机可运行。
2. 在 iOS 工程新增两类 extension：
   - Device Activity Monitor Extension
   - Device Activity Report Extension
3. 在主 App 新增 `ScreenTimeManager.swift`，并在 `AppDelegate.swift` 注册 method channel。
4. Flutter 页面按需添加按钮并调用方法。
5. 新建/修改 entitlement：
   - Runner: FamilyControls + AppGroups
   - Monitor: FamilyControls + AppGroups
   - Report: FamilyControls（可按需加 AppGroups）
6. 在 Apple Developer：
   - 处理 PLA
   - 为三个 Bundle ID 开 capability
   - 创建并绑定 App Group
   - 确保设备已注册
7. 在 Xcode 三个 target：
   - 自动签名
   - Team 一致
   - Bundle ID 唯一
8. 检查 `Embed App Extensions` 已包含 monitor/report。
9. 真机安装后流程验证：
   - 授权 -> 选应用 -> 立即限制
   - 倒计时 15 分钟
   - 每日时段跨天场景
   - 使用时长报告（iOS 17+）
10. 如遇签名错，优先在 Xcode `Product > Run` 让其自动修复一次，再回 Flutter 跑。

---

## 11. 当前项目关键参数（便于迁移时替换）

1. Method Channel：`app_demo/screen_time`
2. App Group：`group.com.lvkang.appdemo20260420.sh`
3. Report Context：`TotalActivity`
4. Bundle ID：
   - Runner: `com.lvkang.appdemo20260420`
   - Monitor: `com.lvkang.appdemo20260420.ScreenTimeMonitorExtension`
   - Report: `com.lvkang.appdemo20260420.ScreenTimeReportExtension`

迁移时建议统一替换为你自己的命名空间。

---

## 12. 验收清单（交付前自测）

1. 真机可以完成授权，无 `AUTH_FAILED`。
2. 可以正常弹出并完成应用选择。
3. 立即限制后，目标应用被系统限制（灰显/隐藏表现由系统行为决定）。
4. 倒计时 15 分钟可生效，结束后自动解除。
5. 每日时段在边界时间点行为正确（含跨天）。
6. 重启 App 后，第三页仍可读取上次计划与选择状态。
7. iOS 17+ 可打开报告页并看到非空/可解释数据（若当天无数据可切换前几天）。

---

## 13. 维护建议

1. 把 App Group、Bundle ID、MethodChannel 抽成常量集中管理，避免多处手写不一致。
2. 新增一个“环境检查”方法（签名能力、系统版本、扩展可用性）用于启动时自检。
3. 若后续要上架，需申请 `Family Controls (Distribution)`，仅 Development capability 不够发布。
4. 若要做“历史统计页”，建议增加本地缓存层，把报告结果按天落地。

---

如需，我下一步可以再补一份“新项目最小代码模板”（包含可直接复制的 `AppDelegate`、`ScreenTimeManager`、Flutter 调用页骨架），用于 30 分钟内起一个可跑版本。
