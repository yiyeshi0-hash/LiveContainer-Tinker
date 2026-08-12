import Foundation

struct ScreenStreamPreference: Sendable {
    static let shared = ScreenStreamPreference()

    var uri = "rtmp://192.168.3.234/live"
    var streamName = "test"

    static var appGroup: String? {
        let fileManager = FileManager.default
        if let configured = Bundle.main.object(forInfoDictionaryKey: "LCAppGroup") as? String,
           fileManager.containerURL(forSecurityApplicationGroupIdentifier: configured) != nil {
            return configured
        }

        let components = (Bundle.main.bundleIdentifier ?? "").components(separatedBy: ".")
        var candidates: [String] = []
        if components.count > 4,
           components[0] == "com",
           components[1] == "kdt",
           components[2] == "livecontainer",
           components[3] != "ScreenStreamExtension" {
            let team = components[3]
            candidates.append("group.com.SideStore.SideStore.\(team)")
            candidates.append("group.com.rileytestut.AltStore.\(team)")
        }
        candidates.append("group.com.SideStore.SideStore")
        candidates.append("group.com.rileytestut.AltStore")

        return candidates.first { fileManager.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
    }

    func makeURL() -> URL? {
        guard let group = Self.appGroup else { return nil }
        let defaults = UserDefaults(suiteName: group)
        let uri = defaults?.string(forKey: "LCStreamURI") ?? uri
        let streamName = defaults?.string(forKey: "LCStreamName") ?? streamName
        if uri.contains("rtmp://") || uri.contains("rtmps://") {
            return URL(string: uri + "/" + streamName)
        }
        return URL(string: uri)
    }
}
