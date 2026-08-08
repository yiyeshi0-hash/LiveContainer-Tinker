import UIKit

final class BuiltInUTMAppInfo: LCAppInfo {
    static let shared = BuiltInUTMAppInfo()

    private override init() {
        super.init(bundlePath: Bundle.main.bundleURL.appendingPathComponent("Frameworks/UTMApp.framework").path)
    }

    override func iconIsDarkIcon(_ isDarkIcon: Bool) -> UIImage! {
        if isDarkIcon {
            if let cachedIconDark {
                return cachedIconDark
            }
        } else if let cachedIcon {
            return cachedIcon
        }

        guard let iconCacheUrl = ensureAndGetIconCacheFolder() else {
            return nil
        }
        let cachedIconURL = iconCacheUrl.appendingPathComponent(isDarkIcon ? "LCAppIconDark.png" : "LCAppIconLight.png")
        var ans: UIImage?
        if FileManager.default.fileExists(atPath: cachedIconURL.path) {
            ans = UIImage(contentsOfFile: cachedIconURL.path)
        }
        if let ans {
            return ans
        }

        ans = UIImage.generateIcon(
            forBundleURL: URL(fileURLWithPath: bundlePath()),
            style: isDarkIcon ? .Dark : .Light,
            hasBorder: true
        )
        if let ans {
            saveCGImage(ans.cgImage, cachedIconURL)
        }
        if isDarkIcon {
            cachedIconDark = ans
        } else {
            cachedIcon = ans
        }
        return ans
    }

    override var lastLaunched: Date! {
        get { nil }
        set {}
    }

    private func ensureAndGetIconCacheFolder() -> URL? {
        let directory = LCPath.docPath
            .appendingPathComponent("UTM/Library/Caches", isDirectory: true)
            .appendingPathComponent("BuiltInUTMIconCache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                return nil
            }
        }
        return directory
    }
}
