import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(Network)
import Network
#endif

/// Cofre-owned downloads. Air continues to own the game's library downloads.
/// The queue outlives Cofre: items and resume data live in a small journal, and the background session's
/// tasks find their item again by `taskDescription` (the item's id).
public final class DownloadQueue: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public enum State: String, Codable, Sendable { case queued, running, waitingWiFi, paused, failed, finished, cancelled }
    public struct Item: Identifiable, Codable, Sendable, Equatable {
        public let id: UUID
        public let title: String
        public let url: URL
        public let destination: URL
        public let totalBytes: Int64?
        public var completedBytes: Int64
        public var state: State
        public var error: String?
        public var sha1: String?, sha512: String?
        /// The user said yes to this one on cellular.
        public var allowCellular = false
        public var fraction: Double { guard let totalBytes, totalBytes > 0 else { return 0 }; return min(1, Double(completedBytes) / Double(totalBytes)) }
    }
    public enum QueueError: LocalizedError, Sendable { case noDiskSpace(required: Int64, free: Int64), cellularRestricted, invalidResponse, hashMismatch
        public var errorDescription: String? { switch self { case let .noDiskSpace(required, free): "Not enough space: need \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)); \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) is free."; case .cellularRestricted: "Over 200 MB on cellular: waits for Wi‑Fi unless you start it now."; case .invalidResponse: "The download server returned an invalid response."; case .hashMismatch: "The downloaded file failed its integrity check." } }
    }
    static let interrupted = "Stopped when Cofre closed."

    /// Downloads above this ask first on cellular. They wait for Wi‑Fi, never fail.
    public static let cellularAskBytes: Int64 = 200 * 1024 * 1024
    public static func asksOnCellular(bytes: Int64?, onCellular: Bool, allowCellular: Bool) -> Bool {
        onCellular && !allowCellular && (bytes ?? 0) > cellularAskBytes
    }

    public static let shared: DownloadQueue = {
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.cofre.downloads")
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        // Large downloads are gated by enqueue's cellular ask; the session must still permit
        // cellular so the user's "Download now" can take effect.
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = false
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return DownloadQueue(configuration: configuration, journal: support?.appendingPathComponent("Cofre/Downloads"))
    }()
    public private(set) var session: URLSession!
    private let lock = NSLock()
    private let journal: URL?
    private var items: [UUID: Item] = [:]
    private var continuations: [UUID: AsyncStream<[Item]>.Continuation] = [:]
    private var resume: [UUID: Data] = [:]
    private var cellular = false
    private var backgroundCompletion: (() -> Void)?
    public var allowCellularForLargeDownloads = false
    public var isOnCellular: Bool { lock.withLock { cellular } }
    #if canImport(Network)
    private let monitor = NWPathMonitor()
    #endif

    /// `journal` is a folder for the queue and its resume data; `nil` keeps everything in memory.
    /// `watchNetwork: false` leaves the cellular state to `networkChanged` (tests).
    public init(configuration: URLSessionConfiguration = .default, journal: URL? = nil, watchNetwork: Bool = true) {
        self.journal = journal
        super.init()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        restore()
        #if canImport(Network)
        guard watchNetwork else { return }
        monitor.pathUpdateHandler = { [weak self] path in self?.networkChanged(online: path.status == .satisfied, cellular: path.isExpensive) }
        monitor.start(queue: DispatchQueue(label: "com.cofre.downloads.network"))
        #endif
    }

    public func updates() -> AsyncStream<[Item]> { AsyncStream { continuation in lock.withLock { continuations[UUID()] = continuation; continuation.yield(Array(items.values)) } } }
    public func snapshot() -> [Item] { lock.withLock { Array(items.values) } }

    public func preflight(requiredBytes: Int64, at url: URL) -> DiskPreflight { .check(downloadBytes: requiredBytes, at: url) }

    @discardableResult public func enqueue(url: URL, destination: URL, title: String, totalBytes: Int64? = nil,
                                           sha1: String? = nil, sha512: String? = nil, allowCellular: Bool? = nil) throws -> UUID {
        let id = UUID()
        let check = preflight(requiredBytes: totalBytes ?? 0, at: destination.deletingLastPathComponent())
        guard check.hasRoom else {
            NSLog("[Cofre] downloads preflight blocked title=%@ need=%lld free=%lld", title, check.needBytes, check.freeBytes)
            throw QueueError.noDiskSpace(required: check.needBytes, free: check.freeBytes)
        }
        let allow = allowCellular ?? allowCellularForLargeDownloads
        var item = Item(id: id, title: title, url: url, destination: destination, totalBytes: totalBytes, completedBytes: 0,
                        state: .queued, error: nil, sha1: sha1, sha512: sha512, allowCellular: allow)
        guard !Self.asksOnCellular(bytes: totalBytes, onCellular: isOnCellular, allowCellular: allow) else {
            item.state = .waitingWiFi; item.error = QueueError.cellularRestricted.localizedDescription
            NSLog("[Cofre] downloads cellular ask title=%@ bytes=%lld", title, totalBytes ?? 0)
            lock.withLock { items[id] = item }; changed(); return id
        }
        lock.withLock { items[id] = item }; start(id, data: nil); return id
    }
    public func download(url: URL, destination: URL, title: String, totalBytes: Int64? = nil,
                        sha1: String? = nil, sha512: String? = nil, allowCellular: Bool? = nil) async throws -> URL {
        let id = try enqueue(url: url, destination: destination, title: title, totalBytes: totalBytes, sha1: sha1, sha512: sha512, allowCellular: allowCellular)
        while true {
            if let item = snapshot().first(where: { $0.id == id }) {
                switch item.state { case .finished: return destination; case .failed, .cancelled: throw NSError(domain: "CofreDownload", code: 1, userInfo: [NSLocalizedDescriptionKey: item.error ?? "Download failed"]); default: break }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
    /// Picks up from where it stopped when the server allows it, otherwise starts over.
    public func resume(_ id: UUID) {
        // Resume data is a property list; anything else would crash the session, so start over instead.
        let data = lock.withLock { resume[id] }.flatMap { (try? PropertyListSerialization.propertyList(from: $0, format: nil)) is [String: Any] ? $0 : nil }
        start(id, data: data)
    }
    public func retry(_ id: UUID) { lock.withLock { items[id]?.completedBytes = 0 }; start(id, data: nil) }
    /// The answer to the cellular ask: download this one now instead of waiting for Wi‑Fi.
    public func startNow(_ id: UUID) { lock.withLock { items[id]?.allowCellular = true }; start(id, data: nil) }
    public func cancel(_ id: UUID) {
        lock.withLock { items[id]?.state = .cancelled }; dropResume(id)
        session.getAllTasks { tasks in tasks.filter { $0.taskDescription == id.uuidString }.forEach { $0.cancel() } }
        changed()
    }

    private func start(_ id: UUID, data: Data?) {
        guard let item = lock.withLock({ items[id] }) else { return }; let task: URLSessionDownloadTask
        if let data { task = session.downloadTask(withResumeData: data) } else { var request = URLRequest(url: item.url); request.timeoutInterval = 120; task = session.downloadTask(with: request) }
        task.taskDescription = id.uuidString; dropResume(id)
        lock.withLock { items[id]?.state = .queued; items[id]?.error = nil }
        NSLog("[Cofre] downloads start title=%@ resumed=%d", item.title, data != nil)
        task.resume(); changed()
    }

    /// Wi‑Fi is back: everything that waited for it starts.
    func networkChanged(online: Bool, cellular: Bool) {
        lock.withLock { self.cellular = online && cellular }
        let waiting = online && !cellular ? snapshot().filter { $0.state == .waitingWiFi }.map(\.id) : []
        if !waiting.isEmpty { NSLog("[Cofre] downloads wifi start waiting=%ld", waiting.count) }
        waiting.forEach { start($0, data: nil) }; publish()
    }

    private func id(of task: URLSessionTask) -> UUID? { task.taskDescription.flatMap(UUID.init(uuidString:)) }
    private func publish() { let value = snapshot(); lock.withLock { continuations.values.forEach { $0.yield(value) } } }
    /// Publishes and writes the journal. Progress ticks only publish.
    private func changed() {
        publish()
        guard let journal else { return }
        let value = snapshot()
        try? FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        try? JSONEncoder().encode(value).write(to: journal.appendingPathComponent("queue.json"), options: .atomic)
    }
    private func update(_ id: UUID, save: Bool = true, _ body: (inout Item) -> Void) { lock.withLock { if var item = items[id] { body(&item); items[id] = item } }; save ? changed() : publish() }
    private func resumeFile(_ id: UUID) -> URL? { journal?.appendingPathComponent("\(id.uuidString).resume") }
    private func keepResume(_ id: UUID, _ data: Data) { lock.withLock { resume[id] = data }; if let file = resumeFile(id) { try? data.write(to: file, options: .atomic) } }
    private func dropResume(_ id: UUID) { _ = lock.withLock { resume.removeValue(forKey: id) }; if let file = resumeFile(id) { try? FileManager.default.removeItem(at: file) } }

    /// Reloads the journal. Anything that was moving is stopped until the session says its task is still alive.
    private func restore() {
        guard let file = journal?.appendingPathComponent("queue.json"), let data = try? Data(contentsOf: file),
              let saved = try? JSONDecoder().decode([Item].self, from: data) else { return }
        for var item in saved where ![.finished, .cancelled].contains(item.state) {
            if let file = resumeFile(item.id), let data = try? Data(contentsOf: file) { resume[item.id] = data }
            if [.queued, .running, .paused].contains(item.state) { item.state = resume[item.id] == nil ? .failed : .paused; item.error = Self.interrupted }
            items[item.id] = item
        }
        NSLog("[Cofre] downloads restored items=%ld resumable=%ld", items.count, resume.count)
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            for task in tasks { if let id = self.id(of: task) { self.update(id) { if $0.error == Self.interrupted { $0.state = .running; $0.error = nil } } } }
        }
    }

    public func handleBackgroundEvents(completion: @escaping () -> Void) { lock.withLock { backgroundCompletion = completion } }
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = lock.withLock { () -> (() -> Void)? in defer { backgroundCompletion = nil }; return backgroundCompletion }
        DispatchQueue.main.async { completion?() }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) { guard let id = id(of: downloadTask) else { return }; update(id, save: false) { $0.state = .running; $0.completedBytes = totalBytesWritten } }
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = id(of: downloadTask), let item = lock.withLock({ items[id] }), item.state != .cancelled else { return }
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw QueueError.invalidResponse }
            if let expected = item.sha1, computeHash(of: location, algorithm: .sha1) != expected.lowercased() { throw QueueError.hashMismatch }
            if let expected = item.sha512, computeHash(of: location, algorithm: .sha512) != expected.lowercased() { throw QueueError.hashMismatch }
            try FileManager.default.createDirectory(at: item.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let tmp = item.destination.appendingPathExtension("partial"); try? FileManager.default.removeItem(at: tmp); try FileManager.default.moveItem(at: location, to: tmp)
            try? FileManager.default.removeItem(at: item.destination); try FileManager.default.moveItem(at: tmp, to: item.destination)
            NSLog("[Cofre] downloads finished title=%@", item.title)
            update(id) { $0.state = .finished; $0.completedBytes = $0.totalBytes ?? $0.completedBytes }
        } catch {
            NSLog("[Cofre] downloads failed title=%@ reason=%@", item.title, error.localizedDescription)
            update(id) { $0.state = .failed; $0.error = error.localizedDescription }
        }
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error as NSError?, let id = id(of: task), let item = lock.withLock({ items[id] }), ![.cancelled, .finished].contains(item.state) else { return }
        if let data = error.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            keepResume(id, data); NSLog("[Cofre] downloads paused title=%@ resumable=1", item.title)
            update(id) { $0.state = .paused; $0.error = error.localizedDescription }
        } else {
            NSLog("[Cofre] downloads failed title=%@ reason=%@", item.title, error.localizedDescription)
            update(id) { $0.state = .failed; $0.error = error.localizedDescription }
        }
    }
}

/// What Play's strip says about the queue. Finished and cancelled downloads don't show.
public struct DownloadSummary: Sendable, Equatable {
    public let visible: [DownloadQueue.Item]
    public init(_ items: [DownloadQueue.Item]) {
        visible = items.filter { ![.finished, .cancelled].contains($0.state) }.sorted { $0.title < $1.title }
    }
    public var active: [DownloadQueue.Item] { visible.filter { [.queued, .running].contains($0.state) } }
    public var waitingWiFi: [DownloadQueue.Item] { visible.filter { $0.state == .waitingWiFi } }
    public var stopped: [DownloadQueue.Item] { visible.filter { [.paused, .failed].contains($0.state) } }
    /// Bytes done over bytes known, across what's moving.
    public var fraction: Double {
        let sized = active.filter { ($0.totalBytes ?? 0) > 0 }
        let total = sized.reduce(Int64(0)) { $0 + $1.totalBytes! }
        return total == 0 ? 0 : min(1, Double(sized.reduce(Int64(0)) { $0 + $1.completedBytes }) / Double(total))
    }
    public var title: String {
        if !active.isEmpty { return "Downloading \(active.count) · \(Int(fraction * 100))%" }
        if !stopped.isEmpty { return stopped.count == 1 ? "A download stopped" : "\(stopped.count) downloads stopped" }
        return waitingWiFi.count == 1 ? "A download waits for Wi‑Fi" : "\(waitingWiFi.count) downloads wait for Wi‑Fi"
    }
}

private enum HashAlgorithm { case sha1, sha512 }
/// Reads in 1 MB chunks: a pack can be hundreds of megabytes.
private func computeHash(of url: URL, algorithm: HashAlgorithm) -> String {
#if canImport(CryptoKit)
    guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
    defer { try? handle.close() }
    var sha1 = Insecure.SHA1(), sha512 = SHA512()
    while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
        switch algorithm { case .sha1: sha1.update(data: chunk); case .sha512: sha512.update(data: chunk) }
    }
    let digest: [UInt8] = algorithm == .sha1 ? Array(sha1.finalize()) : Array(sha512.finalize())
    return digest.map { String(format: "%02x", $0) }.joined()
#else
    return ""
#endif
}

private extension NSLock { func withLock<T>(_ body: () -> T) -> T { lock(); defer { unlock() }; return body() } }
