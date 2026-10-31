import Foundation

public protocol PairingServiceProtocol: AnyObject, Sendable {
    func pair(device: Device, outURL: URL, simulate: Bool) -> AsyncThrowingStream<LlaveEvent, Error>
}

private final class ProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldTerminate = cancelled
        lock.unlock()
        if shouldTerminate, process.isRunning { process.terminate() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = self.process
        lock.unlock()
        if let process, process.isRunning { process.terminate() }
    }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
}

private final class PairingOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var eventError: LlaveError?

    func events(from data: Data) -> [LlaveEvent] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        var events: [LlaveEvent] = []
        while let newlineRange = buffer.range(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
            buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)
            guard let line = String(data: lineData, encoding: .utf8),
                  let event = LlaveEvent.parse(line: line) else { continue }
            if case .error(let code, let message) = event {
                eventError = LlaveError(code: code, message: message)
            }
            events.append(event)
        }
        return events
    }

    var lastError: LlaveError? {
        lock.lock(); defer { lock.unlock() }
        return eventError
    }
}

public final class PairingService: PairingServiceProtocol, @unchecked Sendable {
    private let binaryURL: URL?

    public init(binaryURL: URL? = nil) {
        self.binaryURL = binaryURL ?? DeviceWatcher.resolveBinary()
    }

    public func pair(device: Device, outURL: URL, simulate: Bool) -> AsyncThrowingStream<LlaveEvent, Error> {
        AsyncThrowingStream { continuation in
            let cancellation = ProcessCancellation()
            let worker = Task.detached { [binaryURL] in
                await withTaskCancellationHandler(operation: {
                guard let bin = binaryURL, FileManager.default.isExecutableFile(atPath: bin.path) else {
                    continuation.finish(
                        throwing: LlaveError(code: "CLI_NOT_FOUND", message: "llave-pair binary not found"))
                    return
                }

                let process = Process()
                process.executableURL = bin
                let pairingDir = outURL.deletingLastPathComponent()
                var args = ["pair", "--udid", device.udid, "--out", outURL.lastPathComponent]
                if !simulate { args.append("--place") }
                if simulate { args.append("--simulate") }
                process.arguments = args
                var environment = ProcessInfo.processInfo.environment
                environment["COFRE_PAIRING_DIR"] = pairingDir.path
                process.environment = environment

                let pipe = Pipe()
                process.standardOutput = pipe
                let errPipe = Pipe()
                process.standardError = errPipe

                let outputHandle = pipe.fileHandleForReading
                let output = PairingOutput()

                outputHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty { return }
                    for event in output.events(from: data) { continuation.yield(event) }
                }

                do {
                    try Task.checkCancellation()
                    try process.run()
                    cancellation.attach(process)
                    process.waitUntilExit()
                    outputHandle.readabilityHandler = nil
                    let remainingOutput = outputHandle.readDataToEndOfFile()
                    for event in output.events(from: remainingOutput) { continuation.yield(event) }

                    if cancellation.isCancelled || Task.isCancelled {
                        continuation.finish()
                        return
                    }
                    if process.terminationStatus == 0 {
                        continuation.finish()
                    } else {
                        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        let errStr = String(data: errData, encoding: .utf8) ?? "Unknown failure"
                        continuation.finish(throwing: output.lastError ?? LlaveError(code: "PAIRING_FAILED", message: errStr))
                    }
                } catch {
                    outputHandle.readabilityHandler = nil
                    if cancellation.isCancelled || Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
                }, onCancel: { cancellation.cancel() })
            }
            continuation.onTermination = { _ in
                cancellation.cancel()
                worker.cancel()
            }
        }
    }
}
