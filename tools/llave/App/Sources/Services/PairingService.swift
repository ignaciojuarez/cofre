import Foundation

public protocol PairingServiceProtocol: AnyObject, Sendable {
    func pair(device: Device, outURL: URL, simulate: Bool) -> AsyncThrowingStream<LlaveEvent, Error>
}

public final class PairingService: PairingServiceProtocol, @unchecked Sendable {
    private let binaryURL: URL?

    public init(binaryURL: URL? = nil) {
        self.binaryURL = binaryURL ?? DeviceWatcher.resolveBinary()
    }

    public func pair(device: Device, outURL: URL, simulate: Bool) -> AsyncThrowingStream<LlaveEvent, Error> {
        AsyncThrowingStream { continuation in
            Task.detached { [binaryURL] in
                guard let bin = binaryURL, FileManager.default.isExecutableFile(atPath: bin.path) else {
                    continuation.finish(throwing: LlaveError(code: "CLI_NOT_FOUND", message: "llave-pair binary not found"))
                    return
                }

                let process = Process()
                process.executableURL = bin
                var args = ["pair", "--udid", device.udid, "--out", outURL.path]
                if !simulate { args.append("--place") }
                if simulate { args.append("--simulate") }
                process.arguments = args

                let pipe = Pipe()
                process.standardOutput = pipe
                let errPipe = Pipe()
                process.standardError = errPipe

                let outputHandle = pipe.fileHandleForReading
                var buffer = Data()

                outputHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty { return }
                    buffer.append(data)

                    while let newlineRange = buffer.range(of: Data([0x0A])) {
                        let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                        buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)
                        if let line = String(data: lineData, encoding: .utf8),
                           let event = LlaveEvent.parse(line: line) {
                            continuation.yield(event)
                        }
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()
                    outputHandle.readabilityHandler = nil

                    if process.terminationStatus == 0 {
                        continuation.finish()
                    } else {
                        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        let errStr = String(data: errData, encoding: .utf8) ?? "Unknown failure"
                        continuation.finish(throwing: LlaveError(code: "PAIRING_FAILED", message: errStr))
                    }
                } catch {
                    outputHandle.readabilityHandler = nil
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
