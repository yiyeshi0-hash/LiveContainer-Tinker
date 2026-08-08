import SwiftUI
import Foundation

extension LCAppModel: Identifiable {
    public var id: String {
        (appInfo.relativeBundlePath as String?) ?? UUID().uuidString
    }
}

struct TinkerCenterView: View {
    @EnvironmentObject var sharedModel: SharedModel

    private let statuses = ["All", "Works", "Partial", "Broken", "Untested"]
    private let statusColors: [String: Color] = [
        "Works": .green,
        "Partial": .orange,
        "Broken": .red,
        "Untested": .secondary,
    ]

    @State private var searchText = ""
    @State private var selectedStatus = "All"
    @State private var editingApp: LCAppModel?
    @State private var refreshToken = UUID()
    @State private var mode = 0

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var allApps: [LCAppModel] {
        sharedModel.apps + sharedModel.hiddenApps
    }

    private var filteredApps: [LCAppModel] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return allApps.filter { app in
            let status = app.appInfo.tinkerStatus ?? "Untested"
            let statusMatch = selectedStatus == "All" || status == selectedStatus
            guard statusMatch else { return false }
            guard !keyword.isEmpty else { return true }
            let name = app.displayName
            let bundleID = app.appInfo.bundleIdentifier() ?? ""
            let tags = app.appInfo.tinkerTags ?? ""
            return name.localizedCaseInsensitiveContains(keyword) ||
                bundleID.localizedCaseInsensitiveContains(keyword) ||
                tags.localizedCaseInsensitiveContains(keyword)
        }
        .sorted { ($0.appInfo.lastLaunched ?? .distantPast) > ($1.appInfo.lastLaunched ?? .distantPast) }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Text("LiveContainer-Tinker v\(appVersion)")
                        .font(.caption.weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Picker("Mode", selection: $mode) {
                    Text("App").tag(0)
                    Text("IPA").tag(1)
                    Text("诊断").tag(2)
                    Text("云构建").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if mode == 0 {
                    List {
                        Section {
                            NavigationLink {
                                LCLiveLogView()
                            } label: {
                                Label("实时日志", systemImage: "terminal")
                            }
                        }

                        Section {
                            TextField("搜索 App、Bundle ID 或标签", text: $searchText)
                        }

                        Section {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(statuses, id: \.self) { status in
                                        Button {
                                            selectedStatus = status
                                        } label: {
                                            Text(status)
                                                .font(.subheadline.weight(.medium))
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(
                                                    selectedStatus == status ? Color.accentColor : Color(.systemGray6),
                                                    in: Capsule()
                                                )
                                                .foregroundStyle(selectedStatus == status ? Color.white : Color.primary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        Section {
                            Text("\(filteredApps.count) 个 App")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(filteredApps.indices, id: \.self) { index in
                            let app = filteredApps[index]
                            Button {
                                editingApp = app
                            } label: {
                                TinkerAppRow(app: app, statusColor: statusColors[app.appInfo.tinkerStatus ?? "Untested"] ?? .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .id(refreshToken)
                } else {
                    if mode == 1 {
                        TinkerIPAScanView()
                    } else if mode == 2 {
                        TinkerDiagnosisView()
                    } else {
                        LCCloudBuildView()
                    }
                }
            }
            .navigationTitle("折腾中心")
            .sheet(item: $editingApp) { app in
                TinkerAppEditor(app: app) {
                    refreshToken = UUID()
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

private struct TinkerAppRow: View {
    let app: LCAppModel
    let statusColor: Color

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

            HStack {
                Text("v\(app.version)")
                if let date = app.appInfo.lastLaunched {
                    Text("· \(Self.dateString(date))")
                }
                if app.appInfo.isHidden {
                    Text("· Hidden")
                }
                if app.appInfo.isShared {
                    Text("· Shared")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let tags = app.appInfo.tinkerTags, !tags.isEmpty {
                Text(tags)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

private struct TinkerAppEditor: View {
    @Environment(\.dismiss) private var dismiss

    let app: LCAppModel
    let onSaved: () -> Void

    @State private var status: String
    @State private var notes: String
    @State private var tags: String

    init(app: LCAppModel, onSaved: @escaping () -> Void) {
        self.app = app
        self.onSaved = onSaved
        _status = State(initialValue: app.appInfo.tinkerStatus ?? "Untested")
        _notes = State(initialValue: app.appInfo.tinkerNotes ?? "")
        _tags = State(initialValue: app.appInfo.tinkerTags ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section("App") {
                    Text(app.displayName)
                    Text(app.appInfo.bundleIdentifier() ?? "Unknown")
                        .foregroundStyle(.secondary)
                }

                Section("兼容状态") {
                    Picker("状态", selection: $status) {
                        ForEach(["Untested", "Works", "Partial", "Broken"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    TextField("标签，用逗号分隔", text: $tags)
                }

                Section("备注") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }

                Section("启动历史") {
                    let history = (app.appInfo.tinkerHistory as? [[AnyHashable: Any]]) ?? []
                    if history.isEmpty {
                        Text("暂无记录")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(history.indices, id: \.self) { index in
                        let item = history[index]
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item[AnyHashable("status")] as? String ?? "Unknown")
                                .font(.headline)
                            if let date = item[AnyHashable("date")] as? Date {
                                Text(Self.dateString(date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("JIT: \((item[AnyHashable("jit")] as? Bool ?? false) ? "Yes" : "No") · Classic: \(item[AnyHashable("classicMode")] as? Int ?? 0)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let container = item[AnyHashable("container")] as? String, !container.isEmpty {
                                Text("Container: \(container)")
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

                Section {
                    Button("启动 App") {
                        Task {
                            try? await app.runApp()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(app.displayName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        app.appInfo.tinkerStatus = status
                        app.appInfo.tinkerNotes = notes
                        app.appInfo.tinkerTags = tags
                        app.objectWillChange.send()
                        onSaved()
                        dismiss()
                    }
                }
            }
        }
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct TinkerIPAScanResult: Identifiable {
    let id = UUID()
    let displayName: String
    let bundleID: String
    let version: String
    let minimumOS: String
    let executable: String
    let architecture: String
    let runtimeSummary: String
    let frameworks: [String]
    let fileCount: Int
    let totalSize: Int64
}

enum TinkerIPAScanner {
    static func scan(url: URL) throws -> TinkerIPAScanResult {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let result = extract(url.path, temp.path, Progress.discreteProgress(totalUnitCount: 100))
        guard result == 0 else {
            throw NSError(domain: "TinkerIPAScanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "IPA 解压失败"])
        }

        let files = try FileManager.default.subpathsOfDirectory(atPath: temp.path)
        let appEntry = files.first { $0.hasSuffix(".app") || $0.contains(".app/") }
        let appRoot = appEntry?
            .components(separatedBy: "/")
            .first(where: { $0.hasSuffix(".app") })
        guard let appRoot, appRoot.hasSuffix(".app") else {
            throw NSError(domain: "TinkerIPAScanner", code: 2, userInfo: [NSLocalizedDescriptionKey: "IPA 里没有找到 .app"])
        }

        let appDir = temp.appendingPathComponent(appRoot)
        let infoURL = appDir.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw NSError(domain: "TinkerIPAScanner", code: 3, userInfo: [NSLocalizedDescriptionKey: "Info.plist 解析失败"])
        }

        let executable = plist["CFBundleExecutable"] as? String ?? ""
        let architecture = executableArchitecture(appDir.appendingPathComponent(executable))
        let frameworks = listFrameworks(appDir)
        let runtimeSummary = runtimeSummary(appDir)
        let totalSize = files.reduce(Int64(0)) { total, path in
            let full = temp.appendingPathComponent(path)
            let size = (try? FileManager.default.attributesOfItem(atPath: full.path)[.size] as? Int64) ?? 0
            return total + size
        }

        return TinkerIPAScanResult(
            displayName: plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String ?? "Unknown",
            bundleID: plist["CFBundleIdentifier"] as? String ?? "Unknown",
            version: plist["CFBundleShortVersionString"] as? String ?? "Unknown",
            minimumOS: plist["MinimumOSVersion"] as? String ?? "Unknown",
            executable: executable,
            architecture: architecture,
            runtimeSummary: runtimeSummary,
            frameworks: frameworks,
            fileCount: files.count,
            totalSize: totalSize
        )
    }

    private static func executableArchitecture(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "Unknown" }
        let bytes = [UInt8](data.prefix(4))
        guard bytes.count == 4 else { return "Unknown" }
        let magic = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        switch magic {
        case 0xfeedfacf: return "arm64"
        case 0xfeedface: return "32-bit Mach-O"
        case 0xcafebabe, 0xbebafeca: return "Universal"
        default: return "Unknown"
        }
    }

    private static func listFrameworks(_ appDir: URL) -> [String] {
        let frameworksURL = appDir.appendingPathComponent("Frameworks")
        guard let entries = try? FileManager.default.contentsOfDirectory(at: frameworksURL, includingPropertiesForKeys: nil) else {
            return []
        }
        return entries
            .map { $0.lastPathComponent }
            .filter { $0.hasSuffix(".framework") || $0.hasSuffix(".dylib") }
            .sorted()
    }

    private static func runtimeSummary(_ appDir: URL) -> String {
        let fm = FileManager.default
        let runtimesURL = appDir.appendingPathComponent("java_runtimes")
        guard let entries = try? fm.contentsOfDirectory(atPath: runtimesURL.path) else {
            return "未找到 JRE"
        }

        let runtimeNames = entries.filter {
            $0.localizedCaseInsensitiveContains("openjdk") ||
            $0.localizedCaseInsensitiveContains("jre") ||
            $0.localizedCaseInsensitiveContains("jdk")
        }
        guard !runtimeNames.isEmpty else { return "未找到 JRE" }

        var healthy = 0
        var nested = 0
        for name in runtimeNames {
            let root = runtimesURL.appendingPathComponent(name)
            let nestedRoot = root.appendingPathComponent(name)
            let releaseExists = fm.fileExists(atPath: root.appendingPathComponent("release").path)
            let jvmExists = fm.fileExists(atPath: root.appendingPathComponent("lib/libjvm.dylib").path) ||
                fm.fileExists(atPath: root.appendingPathComponent("lib/server/libjvm.dylib").path)
            let nestedReleaseExists = fm.fileExists(atPath: nestedRoot.appendingPathComponent("release").path)

            if releaseExists && jvmExists {
                healthy += 1
            } else if nestedReleaseExists {
                nested += 1
            }
        }

        if nested > 0 {
            return "JRE \(runtimeNames.count) 个，发现 \(nested) 个嵌套目录"
        }
        if healthy > 0 {
            return "JRE \(healthy) 个正常"
        }
        return "JRE 目录存在但结构未知"
    }
}

struct TinkerIPAResultCard: View {
    let result: TinkerIPAScanResult
    let installURL: URL
    let onInstall: (() -> Void)?

    init(result: TinkerIPAScanResult, installURL: URL, onInstall: (() -> Void)? = nil) {
        self.result = result
        self.installURL = installURL
        self.onInstall = onInstall
    }

    var body: some View {
        Section("应用信息") {
            TinkerInfoRow(label: "名称", value: result.displayName)
            TinkerInfoRow(label: "Bundle ID", value: result.bundleID)
            TinkerInfoRow(label: "版本", value: result.version)
            TinkerInfoRow(label: "最低系统", value: result.minimumOS)
            TinkerInfoRow(label: "可执行文件", value: result.executable)
            TinkerInfoRow(label: "架构", value: result.architecture)
        }

        Section("包结构") {
            TinkerInfoRow(label: "文件数", value: "\(result.fileCount)")
            TinkerInfoRow(label: "解压大小", value: String(format: "%.2f MB", Double(result.totalSize) / 1_000_000))
            TinkerInfoRow(label: "运行时", value: result.runtimeSummary)
            if result.frameworks.isEmpty {
                Text("未发现内嵌 Frameworks")
                    .font(.caption)
            } else {
                ForEach(result.frameworks, id: \.self) { framework in
                    Text(framework)
                        .font(.caption)
                }
            }
        }

        if let onInstall {
            Section {
                Button {
                    onInstall()
                } label: {
                    Label("安装到 LiveContainer", systemImage: "square.and.arrow.down.on.square")
                }
            }
        }
    }
}

private struct TinkerIPAScanView: View {
    @State private var showImporter = false
    @State private var result: TinkerIPAScanResult?
    @State private var installURL: URL?
    @State private var isScanning = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("选择 IPA 文件", systemImage: "doc.badge.plus")
                }

                if isScanning {
                    ProgressView("正在解析 IPA")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            if let result, let installURL {
                TinkerIPAResultCard(result: result, installURL: installURL) {
                    install(installURL)
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.ipa, .tipa]
        ) { result in
            handleImport(result)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            scan(url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func scan(_ url: URL) {
        isScanning = true
        errorMessage = nil
        self.result = nil
        self.installURL = nil
        let accessing = url.startAccessingSecurityScopedResource()

        Task {
            do {
                let localURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("tinker-ipa-\(UUID().uuidString).ipa")
                try? FileManager.default.removeItem(at: localURL)
                try FileManager.default.copyItem(at: url, to: localURL)
                let scanResult = try await Task.detached(priority: .userInitiated) {
                    try TinkerIPAScanner.scan(url: localURL)
                }.value
                result = scanResult
                installURL = localURL
            } catch {
                errorMessage = error.localizedDescription
            }
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
            isScanning = false
        }
    }

    private func install(_ url: URL) {
        NotificationCenter.default.post(name: NSNotification.InstallAppNotification, object: ["url": url])
    }
}

struct TinkerInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}
