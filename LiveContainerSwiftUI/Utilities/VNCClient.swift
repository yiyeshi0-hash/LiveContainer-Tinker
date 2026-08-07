import Combine
import CoreGraphics
import Foundation
import Network

final class VNCClient: ObservableObject {
    enum State: String {
        case idle = "未连接"
        case connecting = "连接中"
        case connected = "已连接"
        case error = "错误"
    }

    @Published var state: State = .idle
    @Published var status = "未连接"
    @Published var image: CGImage?
    @Published var width = 0
    @Published var height = 0

    private var connection: NWConnection?
    private var buffer = Data()
    private var framebuffer = Data()
    private var handshakeState: Handshake = .version
    private var bytesPerPixel = 4

    private enum Handshake {
        case version
        case securityTypes
        case securityResult
        case serverInit
        case running
    }

    func connect(host: String, port: UInt16) {
        state = .connecting
        status = "连接中..."
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.send("RFB 003.008\n".data(using: .utf8)!)
                self?.receive()
            case .failed(let error):
                self?.fail(error.localizedDescription)
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        state = .idle
        status = "未连接"
    }

    func sendPointer(x: Int, y: Int, buttonMask: UInt8 = 0) {
        guard handshakeState == .running else { return }
        var data = Data([5, buttonMask])
        appendUInt16(UInt16(x), to: &data)
        appendUInt16(UInt16(y), to: &data)
        send(data)
    }

    func sendKey(_ key: UInt32, down: Bool) {
        guard handshakeState == .running else { return }
        var data = Data([4, down ? 1 : 0])
        appendUInt16(0, to: &data)
        data.append(contentsOf: key.bigEndian.bytes)
        send(data)
    }

    func tapKey(_ key: UInt32) {
        sendKey(key, down: true)
        sendKey(key, down: false)
    }

    func click(buttonMask: UInt8, x: Int, y: Int) {
        sendPointer(x: x, y: y, buttonMask: buttonMask)
        sendPointer(x: x, y: y, buttonMask: 0)
    }

    func scroll(up: Bool, times: Int = 1, x: Int, y: Int) {
        let mask: UInt8 = up ? 8 : 16
        for _ in 0..<max(1, times) {
            sendPointer(x: x, y: y, buttonMask: mask)
            sendPointer(x: x, y: y, buttonMask: 0)
        }
    }

    private func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.processBuffer()
            }
            if error == nil {
                self.receive()
            } else if let error {
                self.fail(error.localizedDescription)
            }
        }
    }

    private func processBuffer() {
        while true {
            switch handshakeState {
            case .version:
                guard buffer.count >= 12 else { return }
                let serverVersion = String(decoding: buffer.prefix(12), as: UTF8.self)
                guard serverVersion.hasPrefix("RFB ") else {
                    fail("VNC 版本无效")
                    return
                }
                buffer.removeFirst(12)
                handshakeState = .securityTypes
            case .securityTypes:
                guard buffer.count >= 1 else { return }
                let count = Int(buffer.removeFirst())
                guard buffer.count >= count else {
                    buffer.insert(UInt8(count), at: 0)
                    return
                }
                let types = [UInt8](buffer.prefix(count))
                buffer.removeFirst(count)
                guard let noneIndex = types.firstIndex(of: 1) else {
                    fail("VNC 不支持无密码连接")
                    return
                }
                send(Data([types[noneIndex]]))
                handshakeState = .securityResult
            case .securityResult:
                guard buffer.count >= 4 else { return }
                let result = readUInt32(from: 0)
                buffer.removeFirst(4)
                guard result == 0 else {
                    fail("VNC 安全握手失败")
                    return
                }
                send(Data([1]))
                handshakeState = .serverInit
            case .serverInit:
                guard buffer.count >= 24 else { return }
                width = Int(readUInt16(from: 0))
                height = Int(readUInt16(from: 2))
                let nameLength = Int(readUInt32(from: 20))
                guard buffer.count >= 24 + nameLength else { return }
                buffer.removeFirst(24 + nameLength)
                bytesPerPixel = 4
                setupRawFormat()
                handshakeState = .running
                framebuffer = Data(repeating: 0, count: width * height * bytesPerPixel)
                state = .connected
                status = "\(width)x\(height)"
            case .running:
                guard buffer.count >= 1 else { return }
                let messageType = buffer.removeFirst()
                switch messageType {
                case 0:
                    guard buffer.count >= 3 else {
                        buffer.insert(messageType, at: 0)
                        return
                    }
                    buffer.removeFirst(3)
                    guard buffer.count >= 2 else {
                        buffer.insert(messageType, at: 0)
                        return
                    }
                    let rectCount = Int(readUInt16(from: 0))
                    buffer.removeFirst(2)
                    if !readRawRects(count: rectCount) { return }
                    requestUpdate()
                default:
                    return
                }
            }
        }
    }

    private func readRawRects(count: Int) -> Bool {
        for _ in 0..<count {
            guard buffer.count >= 12 else { return false }
            let x = Int(readUInt16(from: 0))
            let y = Int(readUInt16(from: 2))
            let w = Int(readUInt16(from: 4))
            let h = Int(readUInt16(from: 6))
            let encoding = readUInt32(from: 8)
            buffer.removeFirst(12)
            guard encoding == 0 else { return false }
            let rectSize = w * h * bytesPerPixel
            guard buffer.count >= rectSize else { return false }
            let rectData = buffer.prefix(rectSize)
            for row in 0..<h {
                let src = rectData.startIndex + row * w * bytesPerPixel
                let dst = ((y + row) * width + x) * bytesPerPixel
                framebuffer.replaceSubrange(dst..<(dst + w * bytesPerPixel), with: rectData[src..<(src + w * bytesPerPixel)])
            }
            buffer.removeFirst(rectSize)
        }
        image = makeImage(from: framebuffer, width: width, height: height)
        return true
    }

    private func setupRawFormat() {
        var data = Data([0, 0, 0, 0])
        data.append(contentsOf: [32, 24, 0, 1])
        appendUInt16(255, to: &data)
        appendUInt16(255, to: &data)
        appendUInt16(255, to: &data)
        data.append(contentsOf: [16, 8, 0, 0, 0, 0])
        send(data)

        var encodings = Data([2, 0])
        appendUInt16(1, to: &encodings)
        encodings.append(contentsOf: [0, 0, 0, 0])
        send(encodings)
        requestUpdate()
    }

    private func requestUpdate() {
        var data = Data([3, 1])
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(UInt16(width), to: &data)
        appendUInt16(UInt16(height), to: &data)
        send(data)
    }

    private func fail(_ message: String) {
        state = .error
        status = message
        connection?.cancel()
    }

    private func readUInt16(from index: Int) -> UInt16 {
        guard buffer.count >= index + 2 else { return 0 }
        return UInt16(buffer[index]) << 8 | UInt16(buffer[index + 1])
    }

    private func readUInt32(from index: Int) -> UInt32 {
        guard buffer.count >= index + 4 else { return 0 }
        return UInt32(buffer[index]) << 24 | UInt32(buffer[index + 1]) << 16 |
            UInt32(buffer[index + 2]) << 8 | UInt32(buffer[index + 3])
    }

    private func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(contentsOf: [UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    private func makeImage(from data: Data, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, data.count >= width * height * bytesPerPixel else { return nil }
        let provider = CGDataProvider(data: data as CFData)
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

private extension UInt32 {
    var bytes: [UInt8] {
        [UInt8(self >> 24), UInt8(self >> 16), UInt8(self >> 8), UInt8(self)]
    }
}
