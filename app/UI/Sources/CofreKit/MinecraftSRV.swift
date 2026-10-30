import Foundation
import dnssd

public enum MinecraftSRV {
    public struct Record: Equatable, Sendable {
        public let priority: UInt16, weight: UInt16, port: UInt16
        public let host: String
    }
    /// DNSServiceQueryRecord returns uncompressed SRV RDATA: three big-endian words and DNS labels.
    public static func parse(_ data: Data) -> Record? {
        let bytes = Array(data)
        guard bytes.count >= 7 else { return nil }
        func word(_ i: Int) -> UInt16 { UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1]) }
        var index = 6, labels: [String] = []
        while index < bytes.count {
            let count = Int(bytes[index]); index += 1
            if count == 0 {
                guard index == bytes.count, !labels.isEmpty, word(4) > 0 else { return nil }
                return Record(priority: word(0), weight: word(2), port: word(4), host: labels.joined(separator: "."))
            }
            guard count <= 63, count <= bytes.count - index,
                  let label = String(bytes: bytes[index..<index+count], encoding: .utf8),
                  label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
            labels.append(label); index += count
        }
        return nil
    }
    public static func resolve(_ address: MinecraftServerAddress) async -> MinecraftServerAddress {
        guard address.port == nil, !address.host.contains(":"),
              !address.host.allSatisfy({ $0.isNumber || $0 == "." }) else { return address }
        let records = await Query().run(host: address.host)
        guard let priority = records.map(\.priority).min() else { return address }
        let candidates = records.filter { $0.priority == priority }
        let total = candidates.reduce(0) { $0 + Int($1.weight) }
        var ticket = Int.random(in: 0...max(0, total - 1))
        var selected = candidates.randomElement()!
        if total > 0 {
            for candidate in candidates {
                ticket -= Int(candidate.weight)
                if ticket < 0 { selected = candidate; break }
            }
        }
        return .init(host: selected.host, port: selected.port)
    }
}

private final class Query: @unchecked Sendable {
    private let queue = DispatchQueue(label: "cofre.srv")
    private var service: DNSServiceRef?
    private var continuation: CheckedContinuation<[MinecraftSRV.Record], Never>?
    private var records: [MinecraftSRV.Record] = []
    func run(host: String) async -> [MinecraftSRV.Record] {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async {
                    self.continuation = continuation
                    let error = DNSServiceQueryRecord(&self.service, 0, 0, "_minecraft._tcp.\(host)",
                        UInt16(kDNSServiceType_SRV), UInt16(kDNSServiceClass_IN), { _, flags, _, error, _, _, _, length, data, _, context in
                            guard let context else { return }
                            let query = Unmanaged<Query>.fromOpaque(context).takeUnretainedValue()
                            if error == kDNSServiceErr_NoError, let data,
                               let record = MinecraftSRV.parse(Data(bytes: data, count: Int(length))) { query.records.append(record) }
                            if error != kDNSServiceErr_NoError || flags & UInt32(kDNSServiceFlagsMoreComing) == 0 { query.finish() }
                        }, Unmanaged.passUnretained(self).toOpaque())
                    guard error == kDNSServiceErr_NoError, let service = self.service,
                          DNSServiceSetDispatchQueue(service, self.queue) == kDNSServiceErr_NoError else { self.finish(); return }
                    self.queue.asyncAfter(deadline: .now() + 1) { self.finish() }
                }
            }
        } onCancel: { self.queue.async { self.finish() } }
    }
    private func finish() {
        if let service { DNSServiceRefDeallocate(service); self.service = nil }
        continuation?.resume(returning: records); continuation = nil
    }
}
