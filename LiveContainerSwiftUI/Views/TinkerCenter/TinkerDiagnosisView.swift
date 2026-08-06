import SwiftUI
import Foundation

private enum TinkerIssueCategory: String {
    case jit = "JIT"
    case signing = "签名/证书"
    case container = "容器"
    case bit32 = "32 位"
    case graphics = "图形"
    case memory = "内存"
    case unknown = "未知"

    static func classify(_ error: String) -> TinkerIssueCategory {
        let text = error.lowercased()
        if text.contains("jit") || text.contains("jitless") {
            return .jit
        }
        if text.contains("certificate") || text.contains("sign") || text.contains("签名") || text.contains("证书") {
            return .signing
        }
        if text.contains("container") || text.contains("bookmark") || text.contains("容器") {
            return .container
        }
        if text.contains("32-bit") || text.contains("32 bit") {
            return .bit32
        }
        if text.contains("metal") || text.contains("opengl") || text.contains("render") || text.contains("graphics") {
            return .graphics
        }
        if text.contains("memory") || text.contains("insufficient") || text.contains("内存") {
            return .memory
        }
        return .unknown
    }
}

private struct TinkerSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let apply: (LCAppModel) -> Void
}

private enum TinkerHealthStatus: String {
    case pass = "通过"
    case warn = "注意"
    case fail = "失败"
}

private struct TinkerHealthCheck: Identifiable {
    let id = UUID()
    let name: String
    let status: TinkerHealthStatus
    let detail: String
}

private struct TinkerRetryConfig {
    let name: String
    let jit: Bool
    let classic: Bool
    let tweakOff: Bool
    let spoofSDK: Bool
}

struct TinkerDiagnosisView: View {
    @EnvironmentObject var sharedModel: SharedModel
    @State private var selectedForBatch: Set<String> = []

    private var diagnosisApps: [LCAppModel] {
        let apps = sharedModel.apps + sharedModel.hiddenApps
        return apps.filter { app in
            let status = app.appInfo.tinkerStatus ?? "Untested"
            let history = (app.appInfo.tinkerHistory as? [[AnyHashable: Any]]) ?? []
            return status != "Untested" || !history.isEmpty
        }
    }

    var body: some View {
        List {
            Section("批量测试") {
                if !savedBatchPaths.isEmpty {
                    let remaining = max(0, savedBatchPaths.count - batchIndex)
                    Text("队列剩余 \(remaining) 个 App")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("测试下一个") {
                        continueBatch()
                    }
                }

                ForEach(diagnosisApps, id: \.id) { app in
                    Toggle(isOn: isSelected(app)) {
                        Text(app.displayName)
                    }
                }

                Button("开始批量测试") {
                    startBatch()
                }
                .disabled(selectedForBatch.isEmpty)
            }

            if diagnosisApps.isEmpty {
                Text("还没有可诊断的 App，先启动几次再回来")
                    .foregroundStyle(.secondary)
            }

            ForEach(diagnosisApps, id: \.id) { app in
                NavigationLink {
                    TinkerDiagnosisDetailView(app: app)
                } label: {
                    TinkerDiagnosisRow(app: app)
                }
            }
        }
    }

    private var savedBatchPaths: [String] {
        UserDefaults.standard.stringArray(forKey: "TinkerBatchQueue") ?? []
    }

    private var batchIndex: Int {
        UserDefaults.standard.integer(forKey: "TinkerBatchIndex")
    }

    private func isSelected(_ app: LCAppModel) -> Binding<Bool> {
        Binding(
            get: { selectedForBatch.contains(app.id) },
            set: { selected in
                if selected {
                    selectedForBatch.insert(app.id)
                } else {
                    selectedForBatch.remove(app.id)
                }
            }
        )
    }

    private func startBatch() {
        let paths = diagnosisApps
            .filter { selectedForBatch.contains($0.id) }
            .compactMap { $0.appInfo.relativeBundlePath as String? }
        guard !paths.isEmpty else { return }
        UserDefaults.standard.set(paths, forKey: "TinkerBatchQueue")
        UserDefaults.standard.set(0, forKey: "TinkerBatchIndex")
        launchBatch(at: 0)
    }

    private func continueBatch() {
        launchBatch(at: batchIndex)
    }

    private func launchBatch(at index: Int) {
        let paths = savedBatchPaths
        guard index < paths.count else {
            UserDefaults.standard.removeObject(forKey: "TinkerBatchQueue")
            UserDefaults.standard.removeObject(forKey: "TinkerBatchIndex")
            return
        }
        let allApps = sharedModel.apps + sharedModel.hiddenApps
        guard let app = allApps.first(where: {
            ($0.appInfo.relativeBundlePath as String?) == paths[index]
        }) else {
            UserDefaults.standard.set(index + 1, forKey: "TinkerBatchIndex")
            continueBatch()
            return
        }
        UserDefaults.standard.set(index + 1, forKey: "TinkerBatchIndex")
        Task {
            try? await app.runApp()
        }
    }
}

private struct TinkerDiagnosisRow: View {
    let app: LCAppModel

    private var history: [[AnyHashable: Any]] {
        (app.appInfo.tinkerHistory as? [[AnyHashable: Any]]) ?? []
    }

    private var latestError: String {
        history.last?[AnyHashable("error")] as? String ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(app.displayName)
                    .font(.headline)
                Spacer()
                Text(app.appInfo.tinkerStatus ?? "Untested")
                    .font(.caption.bold())
                    .foregroundStyle(statusColor)
            }

            Text(app.appInfo.bundleIdentifier() ?? "Unknown")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("稳定性 \(stabilityScore)/100")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !latestError.isEmpty {
                Text(TinkerIssueCategory.classify(latestError).rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 4)
    }

    private var stabilityScore: Int {
        guard !history.isEmpty else { return 0 }
        let total = history.reduce(0.0) { partial, item in
            switch item[AnyHashable("status")] as? String {
            case "Works": return partial + 1
            case "Partial": return partial + 0.5
            case "Broken": return partial
            default: return partial
            }
        }
        return Int(total / Double(history.count) * 100)
    }

    private var statusColor: Color {
        switch app.appInfo.tinkerStatus ?? "Untested" {
        case "Works": .green
        case "Partial": .orange
        case "Broken": .red
        default: .secondary
        }
    }
}

private struct TinkerDiagnosisDetailView: View {
    let app: LCAppModel

    @State private var refreshToken = UUID()
    @State private var retryIndex = 0

    private static let retryConfigs: [TinkerRetryConfig] = [
        TinkerRetryConfig(name: "JIT On + Classic 0", jit: true, classic: false, tweakOff: false, spoofSDK: false),
        TinkerRetryConfig(name: "JIT On + Classic 1", jit: true, classic: true, tweakOff: false, spoofSDK: false),
        TinkerRetryConfig(name: "JIT On + 关 Tweak", jit: true, classic: false, tweakOff: true, spoofSDK: false),
        TinkerRetryConfig(name: "JIT On + SDK 伪装", jit: true, classic: false, tweakOff: false, spoofSDK: true),
        TinkerRetryConfig(name: "JIT Off + Classic 0", jit: false, classic: false, tweakOff: true, spoofSDK: false),
        TinkerRetryConfig(name: "JIT Off + Classic 1", jit: false, classic: true, tweakOff: true, spoofSDK: false),
    ]

    private var history: [[AnyHashable: Any]] {
        (app.appInfo.tinkerHistory as? [[AnyHashable: Any]]) ?? []
    }

    private var latestHistory: [AnyHashable: Any]? {
        history.last
    }

    private var latestError: String {
        latestHistory?[AnyHashable("error")] as? String ?? ""
    }

    private var issueCategory: TinkerIssueCategory {
        TinkerIssueCategory.classify(latestError)
    }

    private var healthChecks: [TinkerHealthCheck] {
        var checks: [TinkerHealthCheck] = []
        let fm = FileManager.default

        if let bundlePath = app.appInfo.bundlePath() {
            if fm.fileExists(atPath: bundlePath) {
                checks.append(TinkerHealthCheck(name: "App 目录", status: .pass, detail: bundlePath))
            } else {
                checks.append(TinkerHealthCheck(name: "App 目录", status: .fail, detail: "找不到 App 目录"))
            }

            let infoPath = URL(fileURLWithPath: bundlePath).appendingPathComponent("Info.plist").path
            if fm.fileExists(atPath: infoPath) {
                checks.append(TinkerHealthCheck(name: "Info.plist", status: .pass, detail: "存在"))
            } else {
                checks.append(TinkerHealthCheck(name: "Info.plist", status: .fail, detail: "缺失"))
            }

            if let info = NSDictionary(contentsOfFile: infoPath),
               let execName = info["CFBundleExecutable"] as? String {
                let execPath = URL(fileURLWithPath: bundlePath).appendingPathComponent(execName).path
                if fm.fileExists(atPath: execPath) {
                    checks.append(TinkerHealthCheck(name: "可执行文件", status: .pass, detail: execName))
                } else {
                    checks.append(TinkerHealthCheck(name: "可执行文件", status: .fail, detail: "\(execName) 缺失"))
                }
            }
        } else {
            checks.append(TinkerHealthCheck(name: "App 目录", status: .fail, detail: "Bundle Path 为空"))
        }

        if let dataUUID = app.appInfo.dataUUID {
            let privateContainer = LCPath.dataPath.appendingPathComponent(dataUUID)
            let sharedContainer = LCPath.lcGroupDataPath.appendingPathComponent(dataUUID)
            if fm.fileExists(atPath: privateContainer.path) || fm.fileExists(atPath: sharedContainer.path) {
                checks.append(TinkerHealthCheck(name: "数据容器", status: .pass, detail: dataUUID))
            } else {
                checks.append(TinkerHealthCheck(name: "数据容器", status: .warn, detail: "首次启动会自动创建"))
            }
        } else {
            checks.append(TinkerHealthCheck(name: "数据容器", status: .warn, detail: "尚未分配默认容器"))
        }

        checks.append(TinkerHealthCheck(
            name: "JIT",
            status: app.appInfo.isJITNeeded ? .warn : .pass,
            detail: app.appInfo.isJITNeeded ? "需要 JIT，请确认已启用" : "不强制 JIT"
        ))

        checks.append(TinkerHealthCheck(
            name: "Tweak 注入",
            status: app.appInfo.dontInjectTweakLoader ? .warn : .pass,
            detail: app.appInfo.dontInjectTweakLoader ? "已禁用注入" : "正常"
        ))

        checks.append(TinkerHealthCheck(
            name: "SDK 伪装",
            status: app.appInfo.spoofSDKVersion ? .pass : .warn,
            detail: app.appInfo.spoofSDKVersion ? "已启用" : "未启用"
        ))

        return checks
    }

    private var stabilityScore: Int {
        guard !history.isEmpty else { return 0 }
        let total = history.reduce(0.0) { partial, item in
            switch item[AnyHashable("status")] as? String {
            case "Works": return partial + 1
            case "Partial": return partial + 0.5
            case "Broken": return partial
            default: return partial
            }
        }
        return Int(total / Double(history.count) * 100)
    }

    private var suggestions: [TinkerSuggestion] {
        var result: [TinkerSuggestion] = []

        if issueCategory == .jit || app.appInfo.tinkerStatus == "Broken" {
            result.append(TinkerSuggestion(
                title: "启用 JIT",
                detail: "把该 App 设为需要 JIT，并关闭“忽略 JIT”选项。",
                apply: { app in
                    app.appInfo.isJITNeeded = true
                    UserDefaults.standard.set(false, forKey: "LCIgnoreJITOnLaunch")
                    app.objectWillChange.send()
                }
            ))
        }

        if issueCategory == .signing {
            result.append(TinkerSuggestion(
                title: "刷新证书",
                detail: "去设置页重新导入或刷新 SideStore/AltStore 证书。",
                apply: { _ in }
            ))
        }

        if issueCategory == .container {
            result.append(TinkerSuggestion(
                title: "重建默认容器",
                detail: "重新创建一个数据容器，避免容器缺失或损坏。",
                apply: { app in
                    let newName = UUID().uuidString
                    app.appInfo.dataUUID = newName
                    app.objectWillChange.send()
                }
            ))
        }

        if issueCategory == .graphics {
            result.append(TinkerSuggestion(
                title: "切换 Classic 模式",
                detail: "部分图形问题可以通过 Classic 启动模式绕过。",
                apply: { app in
                    app.appInfo.classicMode = true
                    app.objectWillChange.send()
                }
            ))
        }

        result.append(TinkerSuggestion(
            title: "关闭 Tweak 注入",
            detail: "Tweak 可能导致启动崩溃，先禁用注入再测试。",
            apply: { app in
                app.appInfo.dontInjectTweakLoader = true
                app.appInfo.dontLoadTweakLoader = true
                app.objectWillChange.send()
            }
        ))

        result.append(TinkerSuggestion(
            title: "启用 SDK 伪装",
            detail: "有些旧 App 在 iOS 27 上需要伪装旧 SDK 才能启动。",
            apply: { app in
                app.appInfo.spoofSDKVersion = true
                app.objectWillChange.send()
            }
        ))

        return result
    }

    var body: some View {
        List {
            Section("最新状态") {
                TinkerInfoRow(label: "状态", value: app.appInfo.tinkerStatus ?? "Untested")
                TinkerInfoRow(label: "分类", value: issueCategory.rawValue)
                TinkerInfoRow(label: "稳定性", value: "\(stabilityScore)/100")
                if !latestError.isEmpty {
                    Text(latestError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("启动前体检") {
                ForEach(healthChecks) { check in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(check.name)
                            Spacer()
                            Text(check.status.rawValue)
                                .font(.caption.bold())
                                .foregroundStyle(healthColor(check.status))
                        }
                        Text(check.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("环境对比") {
                let comparison = environmentComparison()
                if comparison.isEmpty {
                    Text("还没有足够的历史记录")
                        .foregroundStyle(.secondary)
                }
                ForEach(comparison, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                }
            }

            Section("修复建议") {
                ForEach(suggestions) { suggestion in
                    Button {
                        suggestion.apply(app)
                        refreshToken = UUID()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(suggestion.title)
                                .font(.headline)
                            Text(suggestion.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("自动修复重试") {
                let configs = Self.retryConfigs
                let index = retryIndex % configs.count
                Text("下一套配置：\(configs[index].name)")
                    .font(.headline)
                Text("每次点击会应用配置并启动，返回后查看是否 Works。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("应用并启动") {
                    launchRetry()
                }
            }

            Section("崩溃历史") {
                if history.isEmpty {
                    Text("暂无记录")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(history.reversed().enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item[AnyHashable("status")] as? String ?? "Unknown")
                            .font(.headline)
                        if let date = item[AnyHashable("date")] as? Date {
                            Text(Self.dateString(date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let error = item[AnyHashable("error")] as? String, !error.isEmpty {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(3)
                        }
                    }
                }
            }
        }
        .id(refreshToken)
        .navigationTitle(app.displayName)
        .onAppear {
            retryIndex = UserDefaults.standard.integer(forKey: retryKey)
        }
    }

    private func environmentComparison() -> [String] {
        let works = history.last { ($0[AnyHashable("status")] as? String) == "Works" }
        let broken = history.last { app in
            let status = app[AnyHashable("status")] as? String
            return status == "Broken" || status == "Partial"
        }

        var lines: [String] = []
        if let works {
            lines.append("上次 Works: JIT \(boolText(works[AnyHashable("jit")] as? Bool ?? false)) · Classic \(works[AnyHashable("classicMode")] as? Int ?? 0)")
        }
        if let broken {
            lines.append("上次失败: JIT \(boolText(broken[AnyHashable("jit")] as? Bool ?? false)) · Classic \(broken[AnyHashable("classicMode")] as? Int ?? 0)")
        }
        if let works, let broken {
            let worksJIT = works[AnyHashable("jit")] as? Bool ?? false
            let brokenJIT = broken[AnyHashable("jit")] as? Bool ?? false
            let worksClassic = works[AnyHashable("classicMode")] as? Int ?? 0
            let brokenClassic = broken[AnyHashable("classicMode")] as? Int ?? 0
            if worksJIT != brokenJIT {
                lines.append("差异: JIT \(boolText(worksJIT)) -> \(boolText(brokenJIT))")
            }
            if worksClassic != brokenClassic {
                lines.append("差异: Classic \(worksClassic) -> \(brokenClassic)")
            }
        }
        return lines
    }

    private func launchRetry() {
        let configs = Self.retryConfigs
        let index = retryIndex % configs.count
        applyRetry(configs[index])
        retryIndex = (index + 1) % configs.count
        UserDefaults.standard.set(retryIndex, forKey: retryKey)
        Task {
            try? await app.runApp()
        }
    }

    private var retryKey: String {
        "TinkerRetryIndex.\((app.appInfo.relativeBundlePath as String?) ?? app.appInfo.bundleIdentifier() ?? "")"
    }

    private func applyRetry(_ config: TinkerRetryConfig) {
        app.appInfo.isJITNeeded = config.jit
        app.appInfo.classicMode = config.classic
        app.appInfo.dontInjectTweakLoader = config.tweakOff
        app.appInfo.dontLoadTweakLoader = config.tweakOff
        app.appInfo.spoofSDKVersion = config.spoofSDK
        app.objectWillChange.send()
    }

    private func boolText(_ value: Bool) -> String {
        value ? "On" : "Off"
    }

    private func healthColor(_ status: TinkerHealthStatus) -> Color {
        switch status {
        case .pass: .green
        case .warn: .orange
        case .fail: .red
        }
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
