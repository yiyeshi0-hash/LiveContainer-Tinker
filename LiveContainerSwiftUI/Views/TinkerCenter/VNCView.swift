import SwiftUI

struct VNCView: View {
    @StateObject private var client = VNCClient()
    @State private var pointerDown = false
    @State private var keyText = ""
    @State private var inputMode = 0
    @State private var lastPoint = (x: 0, y: 0)
    @State private var rightClickMode = false
    @State private var displayScale: CGFloat = 1
    @State private var lastMagnification: CGFloat = 0
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
                    Group {
                        if inputMode == 0 {
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                                .contentShape(Rectangle())
                                .gesture(dragGesture(in: geo.size, width: client.width, height: client.height))
                                .simultaneousGesture(magnificationGesture)
                                .scaleEffect(displayScale)
                        } else {
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                        }
                    }
                } else {
                    Text("等待画面")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
            toolbar
        }
        .navigationTitle("VNC")
        .onDisappear {
            client.disconnect()
        }
    }

    private var toolbar: some View {
        VStack(spacing: 6) {
            Picker("输入", selection: $inputMode) {
                Text("鼠标").tag(0)
                Text("键盘").tag(1)
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button(rightClickMode ? "右键模式开" : "右键模式") {
                        rightClickMode.toggle()
                    }
                    Button("左键") {
                        client.click(buttonMask: 1, x: lastPoint.x, y: lastPoint.y)
                    }
                    Button("右键") {
                        client.click(buttonMask: 2, x: lastPoint.x, y: lastPoint.y)
                    }
                    Button("键盘") {
                        keyboardOn = true
                    }
                    Button("Ctrl") { client.tapKey(0xFFE3) }
                    Button("Alt") { client.tapKey(0xFFE9) }
                    Button("Shift") { client.tapKey(0xFFE1) }
                    Button("Tab") { client.tapKey(0xFF09) }
                    Button("Esc") { client.tapKey(0xFF1B) }
                    Button("Enter") { client.tapKey(0xFF0D) }
                    Button("Space") { client.tapKey(0x20) }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func dragGesture(in size: CGSize, width: Int, height: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = mappedPoint(value.location, in: size, width: width, height: height)
                lastPoint = point
                if rightClickMode {
                    client.click(buttonMask: 2, x: point.x, y: point.y)
                    rightClickMode = false
                    return
                }
                if !pointerDown {
                    client.sendPointer(x: point.x, y: point.y, buttonMask: 1)
                    pointerDown = true
                } else {
                    client.sendPointer(x: point.x, y: point.y, buttonMask: 1)
                }
            }
            .onEnded { value in
                let point = mappedPoint(value.location, in: size, width: width, height: height)
                lastPoint = point
                client.sendPointer(x: point.x, y: point.y, buttonMask: 0)
                pointerDown = false
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if lastMagnification == 0 {
                    lastMagnification = value
                    return
                }
                let delta = value - lastMagnification
                if abs(delta) > 0.02 {
                    client.scroll(up: delta < 0, times: Int(abs(delta) * 20), x: lastPoint.x, y: lastPoint.y)
                    lastMagnification = value
                }
                displayScale = value
            }
            .onEnded { _ in
                lastMagnification = 0
                displayScale = 1
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
