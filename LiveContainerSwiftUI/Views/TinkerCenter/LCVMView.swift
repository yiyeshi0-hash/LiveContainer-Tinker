import SwiftUI
import UniformTypeIdentifiers

struct LCVMModel: Identifiable, Codable, Hashable {
    var id: String { folderName }
    var folderName: String
    var name: String
    var system: String
    var diskFileName: String
    var createdAt: Date
    var status: String
    var notes: String
}

private enum LCVMStore {
    static var rootURL: URL {
        LCPath.docPath.appendingPathComponent("VM", isDirectory: true)
    }

    static func ensureRoot() {
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    static func folderURL(for model: LCVMModel) -> URL {
        rootURL.appendingPathComponent(model.folderName, isDirectory: true)
    }

    static func diskURL(for model: LCVMModel) -> URL {
        folderURL(for: model).appendingPathComponent(model.diskFileName)
    }

    static func load() -> [LCVMModel] {
        ensureRoot()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return entries.compactMap { folder in
            guard folder.hasDirectoryPath else { return nil }
            let configURL = folder.appendingPathComponent("config.json")
            if let data = try? Data(contentsOf: configURL),
               let model = try? JSONDecoder.vmDecoder.decode(LCVMModel.self, from: data) {
                return model
            }

            let fallbackName = folder.lastPathComponent
            return LCVMModel(
                folderName: fallbackName,
                name: fallbackName,
                system: "Unknown",
                diskFileName: "disk.qcow2",
                createdAt: Date(),
                status: "Untested",
                notes: ""
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    static func save(_ model: LCVMModel) throws {
        ensureRoot()
        let folder = folderURL(for: model)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder.vmEncoder.encode(model)
        try data.write(to: folder.appendingPathComponent("config.json"), options: .atomic)
    }

    static func addImportedFile(at sourceURL: URL) throws -> LCVMModel {
        ensureRoot()
        let folderName = UUID().uuidString
        let folder = rootURL.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let fileName = sourceURL.lastPathComponent.isEmpty ? "disk.qcow2" : sourceURL.lastPathComponent
        let destination = folder.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        let model = LCVMModel(
            folderName: folderName,
            name: sourceURL.deletingPathExtension().lastPathComponent,
            system: Self.systemName(for: fileName),
            diskFileName: fileName,
            createdAt: Date(),
            status: "Untested",
            notes: ""
        )
        try save(model)
        return model
    }

    static func systemName(for fileName: String) -> String {
        let ext = fileName.lowercased()
        if ext.hasSuffix(".qcow2") { return "QEMU QCOW2" }
        if ext.hasSuffix(".img") || ext.hasSuffix(".raw") { return "Raw Disk" }
        if ext.hasSuffix(".iso") { return "ISO 镜像" }
        if ext.hasSuffix(".vdi") { return "VirtualBox VDI" }
        if ext.hasSuffix(".vmdk") { return "VMware VMDK" }
        return "磁盘镜像"
    }
}

private extension JSONEncoder {
    static var vmEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var vmDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct LCVMView: View {
    @EnvironmentObject private var downloadHelper: DownloadHelper

    @State private var vms: [LCVMModel] = []
    @State private var showImporter = false
    @State private var isWorking = false
    @State private var alertMessage: String?
    @State private var errorMessage: String?
    @State private var logContent = ""
    @State private var showLogs = false
    @StateObject private var urlInput = InputHelper()

    var body: some View {
        List {
            Section("运行时") {
                Label("QEMU 运行时：待集成", systemImage: "cpu")
                Label("JIT 链路：复用折腾中心", systemImage: "bolt.fill")
            }

            Section("操作") {
                Button {
                    showImporter = true
                } label: {
                    Label("导入镜像", systemImage: "externaldrive.badge.plus")
                }

                Button {
                    Task { await promptDownloadURL() }
                } label: {
                    Label("下载镜像", systemImage: "arrow.down.circle")
                }

                if isWorking {
                    ProgressView("正在处理")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section("虚拟机") {
                if vms.isEmpty {
                    Text("还没有 VM，先导入或下载一个镜像")
                        .foregroundStyle(.secondary)
                }

                ForEach(vms) { vm in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(vm.name)
                                .font(.headline)
                                .lineLimit(1)
                            Spacer()
                            Text(vm.status)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }

                        Text(vm.system)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(formatBytes(diskSize(of: vm)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button("启动") {
                                start(vm)
                            }
                            .buttonStyle(.bordered)

                            Button("日志") {
                                loadLogs(vm)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("虚拟机中心")
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.item]
        ) { result in
            handleImport(result)
        }
        .task {
            reload()
        }
        .textFieldAlert(
            isPresented: $urlInput.show,
            title: "下载镜像 URL",
            text: $urlInput.initVal,
            placeholder: "https://",
            action: { newText in
                urlInput.close(result: newText)
            },
            actionCancel: { _ in
                urlInput.close(result: nil)
            }
        )
        .alert(
            "虚拟机",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("好") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .sheet(isPresented: $showLogs) {
            NavigationView {
                ScrollView {
                    Text(logContent)
                        .font(.system(size: 12).monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
                .navigationTitle("VM 日志")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { showLogs = false }
                    }
                }
            }
        }
    }

    private func reload() {
        vms = LCVMStore.load()
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let model = try LCVMStore.addImportedFile(at: url)
                vms.insert(model, at: 0)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func promptDownloadURL() async {
        guard let text = await urlInput.open(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: text) else {
            return
        }
        await downloadImage(from: url)
    }

    private func downloadImage(from url: URL) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let folderName = UUID().uuidString
            let folder = LCVMStore.rootURL.appendingPathComponent(folderName, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let fileName = url.lastPathComponent.isEmpty ? "disk.qcow2" : url.lastPathComponent
            let destination = folder.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: destination)
            try await downloadHelper.download(url: url, to: destination)

            let model = LCVMModel(
                folderName: folderName,
                name: url.deletingPathExtension().lastPathComponent,
                system: LCVMStore.systemName(for: fileName),
                diskFileName: fileName,
                createdAt: Date(),
                status: "Untested",
                notes: ""
            )
            try LCVMStore.save(model)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func start(_ vm: LCVMModel) {
        alertMessage = "QEMU 运行时尚未集成，当前版本先做 VM 管理。"
    }

    private func loadLogs(_ vm: LCVMModel) {
        let logURL = LCVMStore.folderURL(for: vm).appendingPathComponent("vm.log")
        logContent = (try? String(contentsOf: logURL, encoding: .utf8)) ?? "暂无日志"
        showLogs = true
    }

    private func diskSize(of vm: LCVMModel) -> Int64 {
        let values = try? LCVMStore.diskURL(for: vm).resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
