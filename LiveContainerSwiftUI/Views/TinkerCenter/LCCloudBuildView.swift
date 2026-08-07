import SwiftUI
import Security

private struct GHWorkflow: Codable, Identifiable {
    let id: Int
    let name: String
    let path: String
}

private struct GHWorkflowList: Codable {
    let workflows: [GHWorkflow]
}

private struct GHRun: Codable, Identifiable {
    let id: Int
    let name: String?
    let displayTitle: String?
    let headBranch: String?
    let status: String?
    let conclusion: String?
    let createdAt: String?
    let htmlUrl: String?
    let runNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case displayTitle = "display_title"
        case headBranch = "head_branch"
        case status
        case conclusion
        case createdAt = "created_at"
        case htmlUrl = "html_url"
        case runNumber = "run_number"
    }

    var title: String {
        displayTitle ?? name ?? "Run #\(runNumber ?? id)"
    }

    var statusText: String {
        if let conclusion {
            switch conclusion {
            case "success": return "成功"
            case "failure": return "失败"
            case "cancelled": return "已取消"
            case "timed_out": return "超时"
            case "action_required": return "需要操作"
            default: return conclusion
            }
        }
        switch status {
        case "queued": return "排队中"
        case "in_progress": return "构建中"
        case "completed": return "已完成"
        default: return status ?? "未知"
        }
    }

    var statusColor: Color {
        if conclusion == "success" { return .green }
        if conclusion == "failure" || conclusion == "cancelled" || conclusion == "timed_out" {
            return .red
        }
        if status == "in_progress" { return .orange }
        return .secondary
    }
}

private struct GHRunList: Codable {
    let workflowRuns: [GHRun]

    enum CodingKeys: String, CodingKey {
        case workflowRuns = "workflow_runs"
    }
}

private struct GHArtifact: Codable, Identifiable {
    let id: Int
    let name: String
    let sizeInBytes: Int64?
    let expired: Bool?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sizeInBytes = "size_in_bytes"
        case expired
        case createdAt = "created_at"
    }
}

private struct GHArtifactList: Codable {
    let artifacts: [GHArtifact]
}

private enum GitHubTokenStore {
    private static let service = "com.kdt.livecontainer.tinker.github"
    private static let account = "actions-token"

    static func save(_ token: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

struct LCCloudBuildView: View {
    @EnvironmentObject private var downloadHelper: DownloadHelper

    @State private var token = ""
    @State private var owner = "yiyeshi0-hash"
    @State private var repo = "LiveContainer-Tinker"
    @State private var refName = "main"

    @State private var workflows: [GHWorkflow] = []
    @State private var selectedWorkflowID: Int?
    @State private var runs: [GHRun] = []
    @State private var artifactsByRun: [Int: [GHArtifact]] = [:]
    @State private var expandedRunID: Int?

    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    @State private var artifactResult: TinkerIPAScanResult?
    @State private var artifactInstallURL: URL?
    @State private var artifactName = ""

    var body: some View {
        List {
            Section("GitHub") {
                SecureField("Token", text: $token)
                TextField("Owner", text: $owner)
                TextField("Repo", text: $repo)
                TextField("Ref / 分支", text: $refName)

                Button {
                    saveConfig()
                } label: {
                    Label("保存配置", systemImage: "lock.fill")
                }

                Button {
                    Task { await loadWorkflows() }
                } label: {
                    Label("加载工作流", systemImage: "arrow.clockwise")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }

            if !workflows.isEmpty {
                Section("工作流") {
                    Picker("Workflow", selection: Binding<Int?>(
                        get: { selectedWorkflowID ?? workflows.first?.id },
                        set: { selectedWorkflowID = $0 }
                    )) {
                        ForEach(workflows) { workflow in
                            Text(workflow.name).tag(workflow.id as Int?)
                        }
                    }

                    Button {
                        Task { await triggerBuild() }
                    } label: {
                        Label("触发构建", systemImage: "hammer.fill")
                    }
                }
            }

            Section("最近运行") {
                if isWorking && runs.isEmpty {
                    ProgressView()
                }
                if runs.isEmpty && !isWorking {
                    Text("暂无运行记录")
                        .foregroundStyle(.secondary)
                }

                ForEach(runs) { run in
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            Task { await toggleRun(run) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(run.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(run.statusText)
                                        .font(.caption.bold())
                                        .foregroundStyle(run.statusColor)
                                }
                                Text("#\(run.runNumber ?? run.id)  \(run.headBranch ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let createdAt = run.createdAt {
                                    Text(createdAt)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        if expandedRunID == run.id {
                            Divider()
                            if let artifacts = artifactsByRun[run.id] {
                                if artifacts.isEmpty {
                                    Text("暂无 Artifact")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(artifacts) { artifact in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(artifact.name)
                                                    .font(.subheadline)
                                                Text(formatBytes(artifact.sizeInBytes ?? 0))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Button("体检") {
                                                Task { await downloadArtifact(artifact) }
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                }
                            } else {
                                ProgressView("正在读取 Artifact")
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if let artifactResult {
                TinkerIPAResultCard(
                    result: artifactResult,
                    installURL: artifactInstallURL ?? URL(fileURLWithPath: "/")
                ) {
                    installArtifact()
                }
            }
        }
        .refreshable {
            await refresh()
        }
        .task {
            loadConfig()
            if !token.isEmpty {
                await refresh()
            }
        }
    }

    private func loadConfig() {
        owner = UserDefaults.standard.string(forKey: "LCCloudOwner") ?? "yiyeshi0-hash"
        repo = UserDefaults.standard.string(forKey: "LCCloudRepo") ?? "LiveContainer-Tinker"
        refName = UserDefaults.standard.string(forKey: "LCCloudRef") ?? "main"
        token = GitHubTokenStore.load() ?? ""
    }

    private func saveConfig() {
        UserDefaults.standard.set(owner.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "LCCloudOwner")
        UserDefaults.standard.set(repo.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "LCCloudRepo")
        UserDefaults.standard.set(refName.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "LCCloudRef")
        GitHubTokenStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
        statusMessage = "配置已保存"
        errorMessage = nil
    }

    private func refresh() async {
        isWorking = true
        errorMessage = nil
        do {
            await loadWorkflows()
            try await refreshRuns()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func loadWorkflows() async {
        do {
            let data = try await apiRequest("repos/\(owner)/\(repo)/actions/workflows?per_page=100")
            let list = try JSONDecoder().decode(GHWorkflowList.self, from: data)
            workflows = list.workflows
            selectedWorkflowID = workflows.first?.id
            statusMessage = "找到 \(workflows.count) 个工作流"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshRuns() async throws {
        let data = try await apiRequest("repos/\(owner)/\(repo)/actions/runs?per_page=20")
        let list = try JSONDecoder().decode(GHRunList.self, from: data)
        runs = list.workflowRuns
        artifactsByRun.removeAll()
        expandedRunID = nil
    }

    private func triggerBuild() async {
        guard let workflowID = selectedWorkflowID ?? workflows.first?.id else {
            errorMessage = "请先加载工作流"
            return
        }

        do {
            let payload: [String: Any] = [
                "ref": refName.trimmingCharacters(in: .whitespacesAndNewlines),
            ]
            let body = try JSONSerialization.data(withJSONObject: payload)
            _ = try await apiRequest(
                "repos/\(owner)/\(repo)/actions/workflows/\(workflowID)/dispatches",
                method: "POST",
                body: body
            )
            statusMessage = "已触发，正在刷新运行列表"
            try await refreshRuns()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleRun(_ run: GHRun) async {
        if expandedRunID == run.id {
            expandedRunID = nil
            return
        }
        expandedRunID = run.id
        await loadArtifacts(for: run.id)
    }

    private func loadArtifacts(for runID: Int) async {
        do {
            let data = try await apiRequest("repos/\(owner)/\(repo)/actions/runs/\(runID)/artifacts")
            let list = try JSONDecoder().decode(GHArtifactList.self, from: data)
            artifactsByRun[runID] = list.artifacts
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func downloadArtifact(_ artifact: GHArtifact) async {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/actions/artifacts/\(artifact.id)/zip") else {
            errorMessage = "Artifact URL 无效"
            return
        }

        do {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("cloud-artifact-\(artifact.id)-\(UUID().uuidString).zip")
            try? FileManager.default.removeItem(at: destination)
            try await downloadHelper.download(
                url: url,
                to: destination,
                headers: [
                    "Authorization": "Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))",
                    "Accept": "application/vnd.github+json",
                ]
            )
            try await inspectArtifact(at: destination, name: artifact.name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func inspectArtifact(at zipURL: URL, name: String) async throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("artifact-extract-\(UUID().uuidString)")
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)

        let work = try await Task.detached(priority: .userInitiated) { () -> (TinkerIPAScanResult, URL) in
            guard extract(zipURL.path, temp.path, Progress.discreteProgress(totalUnitCount: 100)) == 0 else {
                throw NSError(domain: "LCCloudBuild", code: 1, userInfo: [NSLocalizedDescriptionKey: "Artifact 解压失败"])
            }

            let files = try fm.subpathsOfDirectory(atPath: temp.path)
            guard let ipaRelative = files.first(where: { $0.hasSuffix(".ipa") }) else {
                throw NSError(domain: "LCCloudBuild", code: 2, userInfo: [NSLocalizedDescriptionKey: "Artifact 里没有找到 .ipa"])
            }

            let ipaURL = temp.appendingPathComponent(ipaRelative)
            let localURL = fm.temporaryDirectory
                .appendingPathComponent("cloud-ipa-\(UUID().uuidString).ipa")
            try? fm.removeItem(at: localURL)
            try fm.copyItem(at: ipaURL, to: localURL)
            let scanResult = try TinkerIPAScanner.scan(url: localURL)
            try? fm.removeItem(at: temp)
            return (scanResult, localURL)
        }.value

        artifactResult = work.0
        artifactInstallURL = work.1
        artifactName = name
    }

    private func installArtifact() {
        guard let artifactInstallURL else { return }
        NotificationCenter.default.post(name: NSNotification.InstallAppNotification, object: ["url": artifactInstallURL])
    }

    private func apiRequest(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw "请先填写 GitHub Token"
        }

        guard let url = URL(string: "https://api.github.com/\(path)") else {
            throw "GitHub API URL 无效"
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw "GitHub 响应无效"
        }
        guard (200...299).contains(http.statusCode) else {
            let message = githubErrorMessage(data) ?? "HTTP \(http.statusCode)"
            throw "GitHub \(http.statusCode): \(message)"
        }
        return data
    }

    private func githubErrorMessage(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? String else {
            return nil
        }
        return message
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
