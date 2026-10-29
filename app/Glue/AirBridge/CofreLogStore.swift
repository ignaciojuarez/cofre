import CofreUI
import Foundation

/// Cofre's reader for Air's logs, in place of PLLogOutputView: `latestlog.txt` (Air writes the launcher and JVM
/// output there) and the running instance's `crash-reports/`. Implements `LogSource` and builds the crash screen's
/// report. Air still writes the files.
struct CofreLogStore: Sendable {
    var documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    var latestLog: URL { documents.appendingPathComponent("latestlog.txt") }

    /// Air chdirs the JVM into the instance's game folder (JavaLauncher `[CwdAlign]`), so the working directory wins
    /// while a game runs; POJAV_GAME_DIR (the shared root) otherwise.
    var gameDir: URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if FileManager.default.fileExists(atPath: cwd.appendingPathComponent("crash-reports").path) { return cwd }
        return ProcessInfo.processInfo.environment["POJAV_GAME_DIR"].map { URL(fileURLWithPath: $0) } ?? cwd
    }

    /// The newest `crash-reports/*.txt` written since `since`.
    func newestCrashReport(since: Date = .distantPast) -> URL? {
        let dir = gameDir.appendingPathComponent("crash-reports")
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "txt" }
            .map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) }
            .compactMap { url, date in date.flatMap { $0 >= since ? (url, $0) : nil } }
            .max { $0.1 < $1.1 }?.0
    }

    func url(_ kind: LogKind) -> URL? { kind == .crash ? newestCrashReport() : latestLog }

    // MARK: LogSource

    /// The file's lines, then lines Air appends (polled every half second) until the reader stops. Crash reports
    /// don't grow, so they finish after one read.
    func lines(_ kind: LogKind) -> AsyncStream<LogLine> {
        let url = url(kind)
        let tag = kind == .crash ? "Crash" : "Air"
        return AsyncStream { continuation in
            guard let url else {
                continuation.yield(LogLine(id: 0, time: "", tag: tag, text: "No crash reports", level: .success))
                continuation.finish()
                return
            }
            NSLog("[Cofre] log stream opened kind=%@", kind.rawValue)
            let task = Task.detached {
                var tail = LogTail()
                while !Task.isCancelled {
                    for line in tail.read(url) { continuation.yield(line.tagged(tag)) }
                    if kind == .crash { break }
                    try? await Task.sleep(for: .milliseconds(500))
                }
                NSLog("[Cofre] log line count=%d", tail.count)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func export(_ kind: LogKind) throws -> URL {
        guard let url = url(kind), FileManager.default.fileExists(atPath: url.path) else {
            throw CofreBackendError.unavailable(kind == .crash ? "crash report" : "log export")
        }
        return url
    }

    // MARK: Crash screen

    /// Why the game stopped, from the last 256 KB of the log and this run's newest crash report.
    func gameExitReport(code: Int, instance: String?) -> GameExitReport {
        let crash = newestCrashReport(since: Self.processStart)
        let crashText = crash.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        var tail = LogTail()
        tail.skip(latestLog, keepingLast: 256_000)
        let log = tail.read(latestLog).map(\.text).joined(separator: "\n")
        return GameExitReport(
            code: code, crashReport: crashText, log: log, instance: instance,
            files: [latestLog] + (crash.map { [$0] } ?? []))
    }

    /// When this process started: older crash reports belong to earlier runs.
    static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return .distantPast }
        let t = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000)
    }()
}

/// Reads whole lines appended to a file since the last read. Holds back a partial last line (and so a split UTF-8
/// character) until its newline arrives, and starts over when the file shrinks (Air truncates it per launch).
struct LogTail {
    private var offset: UInt64 = 0
    private var pending = Data()
    private(set) var count = 0

    mutating func skip(_ url: URL, keepingLast bytes: UInt64) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        offset = size > bytes ? size - bytes : 0
    }

    mutating func read(_ url: URL) -> [LogLine] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset {
            offset = 0
            pending = Data()
        }
        guard size > offset, (try? handle.seek(toOffset: offset)) != nil,
            let data = try? handle.readToEnd()
        else { return [] }
        offset += UInt64(data.count)
        pending.append(data)
        guard let end = pending.lastIndex(of: 0x0A) else { return [] }
        let text = String(decoding: pending[..<end], as: UTF8.self)
        pending = Data(pending[pending.index(after: end)...])
        var lines: [LogLine] = []
        for line in text.split(separator: "\n") {
            lines.append(LogLine(id: count, time: "", tag: "", text: String(line), level: Self.level(line)))
            count += 1
        }
        return lines
    }

    private static func level(_ line: Substring) -> LogLine.Level {
        line.contains("ERROR") || line.contains("Exception") ? .error : line.contains("WARN") ? .warning : .info
    }
}

extension LogLine {
    fileprivate func tagged(_ tag: String) -> LogLine {
        var l = self
        l.tag = tag
        return l
    }
}
