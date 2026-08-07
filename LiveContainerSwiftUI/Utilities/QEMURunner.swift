import Foundation

enum QEMURunner {
    private static var lastError: String?

    static var isRunning: Bool {
        LCQEMUIsRunning()
    }

    static var lastErrorMessage: String {
        lastError ?? "未知错误"
    }

    static var runtimePath: String {
        Bundle.main.bundlePath + "/Frameworks/qemu-x86_64-softmmu.framework/qemu-x86_64-softmmu"
    }

    static var resourcePath: String {
        Bundle.main.bundlePath + "/qemu"
    }

    static func isAvailable() -> Bool {
        FileManager.default.fileExists(atPath: runtimePath) &&
            FileManager.default.fileExists(atPath: resourcePath)
    }

    @discardableResult
    static func launch(diskPath: String, isoPath: String? = nil) -> Bool {
        guard !isRunning else {
            lastError = "QEMU 已在运行"
            return false
        }
        guard isAvailable() else {
            lastError = "QEMU 运行时或资源目录未找到"
            return false
        }

        var args = [
            "qemu-system-x86_64",
            "-L", resourcePath,
            "-machine", "q35",
            "-accel", "tcg,tb-size=1024,split-wx=on",
            "-smp", "4",
            "-m", "2048",
            "-nodefaults",
            "-display", "none",
            "-vnc", "127.0.0.1:5900",
        ]
        if FileManager.default.fileExists(atPath: diskPath) {
            let format = diskPath.lowercased().hasSuffix(".qcow2") ? "qcow2" : "raw"
            args.append(contentsOf: ["-drive", "file=\(diskPath),format=\(format),if=ide"])
        }
        if let isoPath {
            args.append(contentsOf: ["-cdrom", isoPath])
            args.append(contentsOf: ["-boot", "d"])
        }

        if let error = LCLaunchQEMU(runtimePath, args) {
            lastError = error
            return false
        }
        lastError = nil
        return true
    }

    static func stop() {
    }
}
