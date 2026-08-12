import SwiftUI

struct ScreenStreamSettingsView: View {
    @AppStorage("LCStreamURI", store: LCUtils.appGroupUserDefault) private var streamURI = "rtmp://192.168.3.234/live"
    @AppStorage("LCStreamName", store: LCUtils.appGroupUserDefault) private var streamName = "test"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField("rtmp://192.168.3.234/live", text: $streamURI)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("test", text: $streamName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("RTMP")
            } footer: {
                Text("\(streamURI)/\(streamName)")
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Screen Stream")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}
