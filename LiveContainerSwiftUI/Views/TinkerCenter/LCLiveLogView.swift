import SwiftUI

struct LCLiveLogView: View {
    private let logURL = LCPath.docPath.appendingPathComponent("Logs/live.log")

    @State private var text = ""
    @State private var offset: UInt64 = 0
    @State private var paused = false
    @State private var errorMessage: String?

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
                Button(paused ? "继续" : "暂停") {
                    paused.toggle()
                }
                .buttonStyle(.bordered)

                Button("清空") {
                    text = ""
                    offset = 0
                    try? FileManager.default.removeItem(at: logURL)
                }
                .buttonStyle(.bordered)

                Spacer()
                Text(logURL.path)
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
        guard let handle = FileHandle(forReadingAtPath: logURL.path) else {
            if text.isEmpty {
                errorMessage = "日志文件尚未创建"
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
}
