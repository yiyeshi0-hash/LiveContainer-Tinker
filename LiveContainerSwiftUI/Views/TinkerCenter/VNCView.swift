import SwiftUI

struct VNCView: View {
    @StateObject private var client = VNCClient()
    @State private var pointerDown = false
    @State private var keyText = ""
    @FocusState private var keyboardOn: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("连接") {
                    client.connect(host: "127.0.0.1", port: 5900)
                }
                .buttonStyle(.bordered)

                Button("断开") {
                    client.disconnect()
                }
                .buttonStyle(.bordered)

                Button("键盘") {
                    keyboardOn = true
                }
                .buttonStyle(.bordered)

                TextField("", text: $keyText)
                    .focused($keyboardOn)
                    .opacity(0)
                    .frame(width: 1, height: 1)
                    .onChange(of: keyText) { newText in
                        if let char = newText.last, let code = char.asciiValue {
                            client.sendKey(UInt32(code), down: true)
                            client.sendKey(UInt32(code), down: false)
                        }
                        if newText.count > 16 {
                            keyText = ""
                        }
                    }

                Spacer()
                Text(client.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            GeometryReader { geo in
                if let image = client.image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(in: geo.size, width: client.width, height: client.height))
                } else {
                    Text("等待画面")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("VNC")
        .onDisappear {
            client.disconnect()
        }
    }

    private func dragGesture(in size: CGSize, width: Int, height: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = mappedPoint(value.location, in: size, width: width, height: height)
                if !pointerDown {
                    client.sendPointer(x: point.x, y: point.y, buttonMask: 1)
                    pointerDown = true
                } else {
                    client.sendPointer(x: point.x, y: point.y, buttonMask: 1)
                }
            }
            .onEnded { value in
                let point = mappedPoint(value.location, in: size, width: width, height: height)
                client.sendPointer(x: point.x, y: point.y, buttonMask: 0)
                pointerDown = false
            }
    }

    private func mappedPoint(_ location: CGPoint, in size: CGSize, width: Int, height: Int) -> (x: Int, y: Int) {
        guard width > 0, height > 0, size.width > 0, size.height > 0 else { return (0, 0) }
        let scale = min(size.width / CGFloat(width), size.height / CGFloat(height))
        let drawW = CGFloat(width) * scale
        let drawH = CGFloat(height) * scale
        let offsetX = (size.width - drawW) / 2
        let offsetY = (size.height - drawH) / 2
        let x = Int((location.x - offsetX) / scale)
        let y = Int((location.y - offsetY) / scale)
        return (max(0, min(width - 1, x)), max(0, min(height - 1, y)))
    }
}
