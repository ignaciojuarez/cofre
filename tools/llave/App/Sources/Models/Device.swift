import Foundation

public struct Device: Identifiable, Codable, Equatable, Sendable {
    public var id: String { udid }
    public let udid: String
    public let name: String
    public let version: String
    public let connectionType: String

    enum CodingKeys: String, CodingKey {
        case udid
        case name
        case version
        case connectionType = "connection_type"
    }

    public init(udid: String, name: String, version: String, connectionType: String = "USB") {
        self.udid = udid
        self.name = name
        self.version = version
        self.connectionType = connectionType
    }
}
