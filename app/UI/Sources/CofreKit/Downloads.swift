import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Cofre-owned downloads. Air continues to own the game's library downloads.
public final class DownloadQueue: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public enum State: String, Codable, Sendable { case queued, running, waitingWiFi, paused, failed, finished, cancelled }
    public struct Item: Identifiable, Sendable {
        public let id: UUID
        public let title: String
        public let url: URL
        public let destination: URL
        public let totalBytes: Int64?
        public var completedBytes: Int64
        public var state: State
        public var error: String?
        public var fraction: Double { guard let totalBytes, totalBytes > 0 else { return 0 }; return min(1, Double(completedBytes) / Double(totalBytes)) }
    }
    public struct Preflight: Sendable, Equatable { public let requiredBytes: Int64; public let freeBytes: Int64; public var hasRoom: Bool { freeBytes >= requiredBytes } }
    public enum QueueError: LocalizedError, Sendable { case noDiskSpace(required: Int64, free: Int64), cellularRestricted, invalidResponse, hashMismatch
        public var errorDescription: String? { switch self { case let .noDiskSpace(required, free): "Not enough space: need \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)); \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) is free."; case .cellularRestricted: "Waiting for Wi‑Fi (this download is over 200 MB)."; case .invalidResponse: "The download server returned an invalid response."; case .hashMismatch: "The downloaded file failed its integrity check." } }
    }

    public static let shared = DownloadQueue()
    public private(set) var session: URLSession!
    private let lock = NSLock()
    private var items: [UUID: Item] = [:]
    private var tasks: [Int: UUID] = [:]
    private var continuations: [UUID: AsyncStream<[Item]>.Continuation] = [:]
    private var resume: [UUID: Data] = [:]
    private var hashes: [UUID: (sha1: String?, sha512: String?)] = [:]
    public var allowCellularForLargeDownloads = false

    public override init() {
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.cofre.downloads")
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.allowsExpensiveNetworkAccess = false
        configuration.allowsConstrainedNetworkAccess = false
        super.init()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    public func updates() -> AsyncStream<[Item]> { AsyncStream { continuation in lock.withLock { continuations[UUID()] = continuation; continuation.yield(Array(items.values)) } } }
    public func snapshot() -> [Item] { lock.withLock { Array(items.values) } }

    public func preflight(requiredBytes: Int64, at url: URL) -> Preflight {
        let free = (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
        return Preflight(requiredBytes: requiredBytes, freeBytes: Int64(free))
    }

    @discardableResult public func enqueue(url: URL, destination: URL, title: String, totalBytes: Int64? = nil,
                                           sha1: String? = nil, sha512: String? = nil, allowCellular: Bool? = nil) throws -> UUID {
        let id = UUID(); let required = totalBytes ?? 0
        let check = preflight(requiredBytes: required, at: destination.deletingLastPathComponent())
        guard check.hasRoom else { throw QueueError.noDiskSpace(required: required, free: check.freeBytes) }
        if required > 200 * 1024 * 1024 && !(allowCellular ?? allowCellularForLargeDownloads) {
            let item = Item(id: id, title: title, url: url, destination: destination, totalBytes: totalBytes, completedBytes: 0, state: .waitingWiFi, error: QueueError.cellularRestricted.localizedDescription)
            lock.withLock { items[id] = item }; publish(); return id
        }
        let item = Item(id: id, title: title, url: url, destination: destination, totalBytes: totalBytes, completedBytes: 0, state: .queued, error: nil)
        lock.withLock { items[id] = item; hashes[id] = (sha1, sha512) }
        var request = URLRequest(url: url); request.timeoutInterval = 120
        let task = session.downloadTask(with: request); task.taskDescription = id.uuidString
        lock.withLock { tasks[task.taskIdentifier] = id }; task.resume(); publish(); return id
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
    public func resume(_ id: UUID) { start(id, data: lock.withLock { resume.removeValue(forKey: id) }) }
    public func retry(_ id: UUID) { start(id, data: nil) }
    public func cancel(_ id: UUID) { lock.withLock { items[id]?.state = .cancelled }; session.getAllTasks { [weak self] tasks in tasks.filter { $0.taskDescription == id.uuidString }.forEach { $0.cancel() }; self?.publish() } }

    private func start(_ id: UUID, data: Data?) {
        guard let item = lock.withLock({ items[id] }) else { return }; var task: URLSessionDownloadTask
        if let data { task = session.downloadTask(withResumeData: data) } else { task = session.downloadTask(with: item.url) }
        task.taskDescription = id.uuidString; lock.withLock { tasks[task.taskIdentifier] = id; items[id]?.state = .queued; items[id]?.error = nil }; task.resume(); publish()
    }
    private func publish() { let value = snapshot(); lock.withLock { continuations.values.forEach { $0.yield(value) } } }
    private func update(_ id: UUID, _ body: (inout Item) -> Void) { lock.withLock { if var item = items[id] { body(&item); items[id] = item } }; publish() }
    public func handleBackgroundEvents(completion: @escaping () -> Void) { completion() }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) { guard let id = lock.withLock({ tasks[downloadTask.taskIdentifier] }) else { return }; update(id) { $0.state = .running; $0.completedBytes = totalBytesWritten } }
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) { guard let id = lock.withLock({ tasks[downloadTask.taskIdentifier] }), let item = lock.withLock({ items[id] }) else { return }; do { let expected = lock.withLock { hashes[id] ?? (nil, nil) }; if let expected = expected.sha1, computeHash(of: location, algorithm: .sha1) != expected.lowercased() { throw QueueError.hashMismatch }; if let expected = expected.sha512, computeHash(of: location, algorithm: .sha512) != expected.lowercased() { throw QueueError.hashMismatch }; try FileManager.default.createDirectory(at: item.destination.deletingLastPathComponent(), withIntermediateDirectories: true); let tmp = item.destination.appendingPathExtension("partial"); try? FileManager.default.removeItem(at: tmp); try FileManager.default.moveItem(at: location, to: tmp); try? FileManager.default.removeItem(at: item.destination); try FileManager.default.moveItem(at: tmp, to: item.destination); update(id) { $0.state = .finished; $0.completedBytes = $0.totalBytes ?? $0.completedBytes } } catch { update(id) { $0.state = .failed; $0.error = error.localizedDescription } } }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { guard let id = lock.withLock({ tasks[task.taskIdentifier] }) else { return }; if let error = error as NSError?, let data = error.userInfo[NSURLSessionDownloadTaskResumeData] as? Data { lock.withLock { resume[id] = data }; update(id) { $0.state = .paused; $0.error = error.localizedDescription } } else if let error { update(id) { $0.state = .failed; $0.error = error.localizedDescription } } }
}

private enum HashAlgorithm { case sha1, sha512 }
private func computeHash(of url: URL, algorithm: HashAlgorithm) -> String {
    guard let data = try? Data(contentsOf: url) else { return "" }
#if canImport(CryptoKit)
    switch algorithm { case .sha1: return Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined(); case .sha512: return SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined() }
#else
    return ""
#endif
}

private extension NSLock { func withLock<T>(_ body: () -> T) -> T { lock(); defer { unlock() }; return body() } }
