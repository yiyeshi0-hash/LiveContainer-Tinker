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

struct TinkerDiagnosisView: View {
    @EnvironmentObject var sharedModel: SharedModel

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
                if !latestError.isEmpty {
                    Text(latestError)
                        .font(.caption)
                        .foregroundStyle(.red)
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

    private func boolText(_ value: Bool) -> String {
        value ? "On" : "Off"
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
