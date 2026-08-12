import Foundation
import Security

struct ScreenStreamPreference: Sendable {
    static let shared = ScreenStreamPreference()

    var uri = "rtmp://192.168.3.234/live"
    var streamName = "test"

    static var appGroup: String? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        let raw = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil)
        guard let groups = raw as? [String] else { return nil }
        return groups.first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil } ?? groups.first
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
