import Combine
import AVFoundation
import CryptoKit
import Foundation
import Security
import SwiftUI
import UIKit

struct TOTPAccount: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var issuer: String
    var account: String
    var secret: String
    var digits: Int = 6
    var period: Int = 30
}

final class TOTPStore: ObservableObject {
    static let shared = TOTPStore()

    @Published var accounts: [TOTPAccount] = []

    private let service = "com.kdt.livecontainer.totp"
    private let keychainAccount = "accounts"

    private init() {
        load()
    }

    func add(issuer: String, account: String, secretOrURI: String) throws {
        let trimmed = secretOrURI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TOTPError.invalidInput
        }

        if trimmed.lowercased().hasPrefix("otpauth://") {
            let parsed = try parseURI(trimmed)
            accounts.append(parsed)
        } else {
            let normalizedSecret = Base32.normalize(trimmed)
            guard Base32.decode(normalizedSecret) != nil else {
                throw TOTPError.invalidSecret
            }
            accounts.append(
                TOTPAccount(
                    issuer: issuer.isEmpty ? "TOTP" : issuer,
                    account: account.isEmpty ? "Account" : account,
                    secret: normalizedSecret
                )
            )
        }
        try save()
    }

    func remove(at offsets: IndexSet) {
        accounts.remove(atOffsets: offsets)
        try? save()
    }

    func code(for account: TOTPAccount, at date: Date = Date()) -> String {
        TOTPGenerator.code(secret: account.secret, digits: account.digits, period: account.period, date: date)
    }

    func remainingSeconds(for account: TOTPAccount, at date: Date = Date()) -> Int {
        account.period - Int(date.timeIntervalSince1970) % account.period
    }

    private func parseURI(_ uri: String) throws -> TOTPAccount {
        guard let components = URLComponents(string: uri),
              components.scheme?.lowercased() == "otpauth" else {
            throw TOTPError.invalidInput
        }
        let query = components.queryItems ?? []
        guard let secret = query.first(where: { $0.name == "secret" })?.value else {
            throw TOTPError.invalidSecret
        }
        let normalizedSecret = Base32.normalize(secret)
        guard Base32.decode(normalizedSecret) != nil else {
            throw TOTPError.invalidSecret
        }

        var issuer = query.first(where: { $0.name == "issuer" })?.value
        var account = components.path.replacingOccurrences(of: "/", with: "")
        if let colon = account.lastIndex(of: ":") {
            issuer = issuer ?? String(account[..<colon])
            account = String(account[account.index(after: colon)...])
        }
        let digits = query.first(where: { $0.name == "digits" }).flatMap { Int($0.value ?? "") } ?? 6
        let period = query.first(where: { $0.name == "period" }).flatMap { Int($0.value ?? "") } ?? 30
        return TOTPAccount(
            issuer: issuer?.isEmpty == false ? issuer! : "TOTP",
            account: account.isEmpty ? "Account" : account,
            secret: normalizedSecret,
            digits: max(6, min(8, digits)),
            period: max(1, period)
        )
    }

    private func load() {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return
        }
        accounts = (try? JSONDecoder().decode([TOTPAccount].self, from: data)) ?? []
    }

    private func save() throws {
        let data = try JSONEncoder().encode(accounts)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TOTPError.keychain(status)
        }
    }
}

enum TOTPError: LocalizedError {
    case invalidInput
    case invalidSecret
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "请输入 otpauth:// 链接或 Base32 密钥"
        case .invalidSecret:
            return "Base32 密钥格式不正确"
        case .keychain(let status):
            return "Keychain 写入失败：\(status)"
        }
    }
}

enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func normalize(_ input: String) -> String {
        input
            .uppercased()
            .filter { $0 != " " && $0 != "-" && $0 != "=" }
    }

    static func decode(_ input: String) -> [UInt8]? {
        var bits = 0
        var value = 0
        var output: [UInt8] = []
        for character in input {
            guard let index = alphabet.firstIndex(of: character) else {
                return nil
            }
            value = (value << 5) | index
            bits += 5
            if bits >= 8 {
                output.append(UInt8((value >> (bits - 8)) & 0xff))
                bits -= 8
            }
        }
        return output
    }
}

enum TOTPGenerator {
    static func code(secret: String, digits: Int, period: Int, date: Date = Date()) -> String {
        guard let key = Base32.decode(Base32.normalize(secret)) else {
            return "------"
        }
        let counter = UInt64(date.timeIntervalSince1970 / Double(period))
        var bigEndianCounter = counter.bigEndian
        let message = withUnsafeBytes(of: &bigEndianCounter) { Data($0) }
        let mac = HMAC<Insecure.SHA1>.authenticationCode(
            for: message,
            using: SymmetricKey(data: key)
        )
        let hash = mac.withUnsafeBytes { Array($0) }
        let offset = Int(hash[hash.count - 1] & 0x0f)
        let binary = (UInt32(hash[offset] & 0x7f) << 24) |
            (UInt32(hash[offset + 1]) << 16) |
            (UInt32(hash[offset + 2]) << 8) |
            UInt32(hash[offset + 3])
        let modulus = UInt32(pow(10, Double(digits)))
        let code = Int(binary % modulus)
        return String(format: "%0*d", digits, code)
    }
}

struct TOTPView: View {
    @ObservedObject private var store = TOTPStore.shared
    @AppStorage("totpAutoCopy") private var autoCopy = false
    @State private var showAdd = false
    @State private var now = Date()
    @State private var copiedID: String?

    var body: some View {
        Toggle("自动复制验证码", isOn: $autoCopy)
            .padding(.horizontal)
            .padding(.vertical, 6)
        List {
            if store.accounts.isEmpty {
                Section {
                    Text("还没有 TOTP 账号，点击右上角添加")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(store.accounts) { account in
                TOTPRow(
                    account: account,
                    code: store.code(for: account, at: now),
                    remaining: store.remainingSeconds(for: account, at: now),
                    copied: copiedID == account.id,
                    autoCopy: autoCopy
                ) {
                    UIPasteboard.general.string = store.code(for: account, at: now)
                    copiedID = account.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedID = nil
                    }
                }
            }
            .onDelete { offsets in
                store.remove(at: offsets)
            }
        }
        .navigationTitle("TOTP 验证器")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Label("添加", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            TOTPAddView(store: store)
        }
        .onReceive(
            Timer.publish(every: 1, on: .main, in: .common).autoconnect()
        ) { date in
            now = date
        }
    }
}

private struct TOTPRow: View {
    let account: TOTPAccount
    let code: String
    let remaining: Int
    let copied: Bool
    let autoCopy: Bool
    let onCopy: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.issuer)
                    .font(.headline)
                Text(account.account)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(code)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                TOTPRing(remaining: remaining, period: account.period)
            }
            Button(action: onCopy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onCopy)
        .onChange(of: code) { newCode in
            if autoCopy {
                onCopy()
            }
        }
    }
}

private struct TOTPRing: View {
    let remaining: Int
    let period: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0, min(1, CGFloat(remaining) / CGFloat(period))))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: remaining)
            Text("\(remaining)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(width: 34, height: 34)
    }
}

private struct TOTPAddView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TOTPStore
    @State private var issuer = ""
    @State private var account = ""
    @State private var secretOrURI = ""
    @State private var errorMessage: String?
    @State private var showScanner = false

    var body: some View {
        NavigationView {
            Form {
                Section("名称") {
                    TextField("发行方", text: $issuer)
                    TextField("账号", text: $account)
                }
                Section("密钥") {
                    TextField("otpauth:// 或 Base32 密钥", text: $secretOrURI)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        showScanner = true
                    } label: {
                        Label("扫码添加", systemImage: "qrcode.viewfinder")
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("添加 TOTP")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        do {
                            try store.add(issuer: issuer, account: account, secretOrURI: secretOrURI)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showScanner) {
            NavigationView {
                ZStack {
                    Color.black.ignoresSafeArea()
                    QRCodeScannerView(
                        onCode: { code in
                            do {
                                try store.add(issuer: issuer, account: account, secretOrURI: code)
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                                showScanner = false
                            }
                        },
                        onCancel: {
                            showScanner = false
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(32)
                }
                .navigationTitle("扫描二维码")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showScanner = false }
                    }
                }
            }
        }
    }
}

private struct QRCodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> QRCodeScannerViewController {
        let controller = QRCodeScannerViewController()
        controller.onCode = onCode
        controller.onCancel = onCancel
        return controller
    }

    func updateUIViewController(_ uiViewController: QRCodeScannerViewController, context: Context) {}
}

private final class QRCodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        session.startRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else {
            return
        }
        session.stopRunning()
        onCode?(value)
    }
}
