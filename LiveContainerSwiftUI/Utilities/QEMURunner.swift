import Darwin
import Foundation

enum QEMURunner {
    private static var runningTask: Task<Void, Never>?

    static var isRunning: Bool {
        runningTask != nil
    }

    static var runtimePath: String {
        Bundle.main.bundlePath + "/Frameworks/qemu-x86_64-softmmu.framework/qemu-x86_64-softmmu"
    }

    static func isAvailable() -> Bool {
        FileManager.default.fileExists(atPath: runtimePath)
    }

    @discardableResult
    static func launch(diskPath: String, isoPath: String? = nil) -> Bool {
        guard !isRunning, isAvailable() else { return false }
        guard let handle = dlopen(runtimePath, RTLD_NOW | RTLD_LOCAL),
              let symbol = dlsym(handle, "qemu_main") else {
            return false
        }

        let qemuMain = unsafeBitCast(
            symbol,
            to: (@convention(c) (Int32, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32).self
        )

        runningTask = Task {
            var args = [
                "qemu-system-x86_64",
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

            var argv = args.map { strdup($0) }
            argv.append(nil)
            _ = argv.withUnsafeMutableBufferPointer { buffer in
                qemuMain(Int32(args.count), buffer.baseAddress)
            }
            argv.forEach { free($0) }
            runningTask = nil
        }
        return true
    }

    static func stop() {
        runningTask?.cancel()
        runningTask = nil
    }
}
