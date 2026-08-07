import Darwin
import Foundation

enum QEMURunner {
    private static var runningTask: Task<Void, Never>?
    private static var qemuHandle: UnsafeMutableRawPointer?
    private static var lastError: String?

    static var isRunning: Bool {
        runningTask != nil
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
        guard let handle = dlopen(runtimePath, RTLD_NOW | RTLD_LOCAL) else {
            lastError = String(cString: dlerror())
            return false
        }
        guard let qemuInitSymbol = dlsym(handle, "qemu_init"),
              let qemuMainLoopSymbol = dlsym(handle, "qemu_main_loop"),
              let qemuCleanupSymbol = dlsym(handle, "qemu_cleanup") else {
            lastError = String(cString: dlerror())
            dlclose(handle)
            return false
        }

        typealias QEMUInitFunction = @convention(c) (
            Int32,
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        ) -> Int32
        typealias QEMUVoidFunction = @convention(c) () -> Void

        let qemuInit = unsafeBitCast(qemuInitSymbol, to: QEMUInitFunction.self)
        let qemuMainLoop = unsafeBitCast(qemuMainLoopSymbol, to: QEMUVoidFunction.self)
        let qemuCleanup = unsafeBitCast(qemuCleanupSymbol, to: QEMUVoidFunction.self)
        qemuHandle = handle
        lastError = nil

        runningTask = Task {
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

            var argv = args.map { strdup($0) }
            argv.append(nil)
            let initResult = argv.withUnsafeMutableBufferPointer { buffer in
                qemuInit(Int32(args.count), buffer.baseAddress, _NSGetEnviron()?.pointee)
            }
            if initResult == 0 {
                qemuMainLoop()
            } else {
                lastError = "qemu_init 返回 \(initResult)"
            }
            qemuCleanup()
            argv.forEach { free($0) }
            if let qemuHandle {
                dlclose(qemuHandle)
                self.qemuHandle = nil
            }
            runningTask = nil
        }
        return true
    }

    static func stop() {
        runningTask?.cancel()
        runningTask = nil
    }
}
