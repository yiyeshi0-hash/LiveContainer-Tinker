import SwiftUI

struct LCServerConsoleView: View {
    @State private var host = UserDefaults.standard.string(forKey: "LCConsoleHost") ?? "192.168.1.18"
    @State private var port = UserDefaults.standard.string(forKey: "LCConsolePort") ?? "8081"
    @State private var token = UserDefaults.standard.string(forKey: "LCConsoleToken") ?? "123456"
    @State private var command = ""
    @State private var output = ""
    @State private var isRunning = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("连接") {
                    TextField("Host", text: $host)
                    TextField("Port", text: $port)
                    SecureField("Token", text: $token)
                    Button("保存配置") { save() }
                }

                Section("快捷命令") {
                    Button("磁盘") { run("df -h") }
                    Button("内存") { run("free -h") }
                    Button("负载") { run("uptime") }
                    Button("最近日志") { run("tail -n 80 ~/.codex/app-server-control/app-server.log 2>/dev/null") }
                }

                Section("命令") {
                    TextField("输入命令", text: $command)
                    Button("执行") { run(command) }
                    if isRunning { ProgressView("执行中") }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }

            Divider()
            ScrollView {
                Text(output.isEmpty ? "暂无输出" : output)
                    .font(.system(size: 11).monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .frame(maxHeight: .infinity)
        }
        .navigationTitle("服务器")
    }

    private func save() {
        UserDefaults.standard.set(host, forKey: "LCConsoleHost")
        UserDefaults.standard.set(port, forKey: "LCConsolePort")
        UserDefaults.standard.set(token, forKey: "LCConsoleToken")
    }

    private func run(_ cmd: String) {
        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: "http://\(host):\(port)/cmd") else { return }

        isRunning = true
        errorMessage = nil
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token, "cmd": trimmed])

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw "HTTP \(http.statusCode)"
                }
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                output = obj?["output"] as? String ?? (obj?["error"] as? String ?? String(data: data, encoding: .utf8) ?? "")
            } catch {
                errorMessage = error.localizedDescription
            }
            isRunning = false
        }
    }
}
