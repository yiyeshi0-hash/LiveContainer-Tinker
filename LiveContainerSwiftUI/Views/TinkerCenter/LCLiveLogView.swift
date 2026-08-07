import SwiftUI

struct LCLiveLogView: View {
    private let logURL = LCPath.docPath.appendingPathComponent("Logs/live.log")

    @State private var text = ""
    @State private var offset: UInt64 = 0
    @State private var paused = false
    @State private var errorMessage: String?
    @State private var useUTMDebug = false
    @State private var utmDebugURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(text.isEmpty ? "暂无日志" : text)
                        .font(.system(size: 11).monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                        .id("bottom")
                }
                .onChange(of: text) { _ in
                    if !paused {
                        withAnimation(.linear(duration: 0.15)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()
            HStack {
                Toggle("UTM debug.log", isOn: $useUTMDebug)
                    .onChange(of: useUTMDebug) { _ in
                        utmDebugURL = findUTMDebugLog()
                        text = ""
                        offset = 0
                        readNewData()
                    }

                Button(paused ? "继续" : "暂停") {
                    paused.toggle()
                }
                .buttonStyle(.bordered)

                Button("清空") {
                    text = ""
                    offset = 0
                    if !useUTMDebug {
                        try? FileManager.default.removeItem(at: logURL)
                    }
                }
                .buttonStyle(.bordered)

                Spacer()
                Text(currentLogPath())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle("实时日志")
        .task {
            while !Task.isCancelled {
                if !paused {
                    readNewData()
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func readNewData() {
        let path = currentLogPath()
        guard let handle = FileHandle(forReadingAtPath: path) else {
            if text.isEmpty {
                errorMessage = "日志文件尚未创建: \(path)"
            }
            return
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: offset)
            let data = handle.readDataToEndOfFile()
            offset += UInt64(data.count)
            if let newText = String(data: data, encoding: .utf8), !newText.isEmpty {
                text += newText
                if text.count > 200_000 {
                    text = String(text.suffix(200_000))
                }
            }
            errorMessage = nil
        } catch {
            if errorMessage == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func currentLogPath() -> String {
        if useUTMDebug {
            if let utmDebugURL {
                return utmDebugURL.path
            }
            if let found = findUTMDebugLog() {
                utmDebugURL = found
                return found.path
            }
        }
        return logURL.path
    }

    private func findUTMDebugLog() -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: LCPath.docPath,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for case let url as URL in enumerator {
            if url.lastPathComponent == "debug.log", url.path.contains(".utm") {
                return url
            }
        }
        return nil
    }
}
