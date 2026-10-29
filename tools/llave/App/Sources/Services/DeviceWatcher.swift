import Foundation

public protocol DeviceWatcherProtocol: AnyObject, Sendable {
    var devicesStream: AsyncStream<[Device]> { get }
    func start()
    func stop()
    func refresh() async -> [Device]
}

public final class DeviceWatcher: DeviceWatcherProtocol, @unchecked Sendable {
    private let binaryURL: URL?
    private let isSimulating: Bool
    private var isRunning = false
    private var task: Task<Void, Never>?
    private var continuation: AsyncStream<[Device]>.Continuation?

    public let devicesStream: AsyncStream<[Device]>

    public init(binaryURL: URL? = nil, isSimulating: Bool = false) {
        self.binaryURL = binaryURL ?? DeviceWatcher.resolveBinary()
        self.isSimulating = isSimulating

        var storedContinuation: AsyncStream<[Device]>.Continuation?
        self.devicesStream = AsyncStream { cont in
            storedContinuation = cont
        }
        self.continuation = storedContinuation
    }

    deinit {
        stop()
    }

    public static func resolveBinary() -> URL? {
        if let res = Bundle.main.url(forResource: "llave-pair", withExtension: nil),
            FileManager.default.isExecutableFile(atPath: res.path)
        {
            return res
        }
        let devPaths = [
            "/tmp/bin/llave-pair",
            "/usr/local/bin/llave-pair",
            FileManager.default.currentDirectoryPath + "/core/target/release/llave-pair",
            FileManager.default.currentDirectoryPath + "/llave/core/target/release/llave-pair",
            FileManager.default.currentDirectoryPath + "/../core/target/release/llave-pair",
        ]
        for p in devPaths {
            if FileManager.default.isExecutableFile(atPath: p) {
                return URL(fileURLWithPath: p)
            }
        }
        return nil
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        task = Task { [weak self] in
            while let self = self, self.isRunning {
                let devs = await self.refresh()
                self.continuation?.yield(devs)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    public func stop() {
        isRunning = false
        task?.cancel()
        task = nil
    }

    public func refresh() async -> [Device] {
        if isSimulating {
            return [
                Device(
                    udid: "00008150-SIMULATED-DEV",
                    name: "Simulated iPhone",
                    version: "18.1",
                    connectionType: "USB"
                )
            ]
        }

        guard let bin = binaryURL, FileManager.default.isExecutableFile(atPath: bin.path) else {
            return []
        }

        return await Task.detached {
            let process = Process()
            process.executableURL = bin
            process.arguments = ["devices"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let devices = try JSONDecoder().decode([Device].self, from: data)
                return devices
            } catch {
                return []
            }
        }.value
    }
}
