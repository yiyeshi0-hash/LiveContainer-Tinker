import SwiftUI

struct VNCView: View {
    @StateObject private var client = VNCClient()

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
}
