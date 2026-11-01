import Foundation

/// The app's embedded provisioning profile. iOS only opens a development build (get-task-allow) with Developer Mode
/// on and its signer trusted, so a running one proves both.
struct ProvisioningProfile {
    let team: String
    let expires: Date
    let isDevelopment: Bool
    let hasPacketTunnel: Bool
    let hasMemoryEntitlements: Bool

    var supportsBuiltInJIT: Bool { isDevelopment && hasPacketTunnel }

    static let builtInJITUnavailableMessage =
        "This signed build can't enable Cofre's built-in JIT. Re-sign with a development profile that includes JIT and Packet Tunnel entitlements."
    static let packetTunnelUnavailableMessage =
        "This signed build can't provide Cofre's local VPN. Re-sign with a profile that includes the Packet Tunnel entitlement."

    static let current: ProvisioningProfile? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
            let data = try? Data(contentsOf: url),
            let start = data.range(of: Data("<?xml".utf8)),
            let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
            let plist = try? PropertyListSerialization.propertyList(
                from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any]
        else { return nil }
        let entitlements = plist["Entitlements"] as? [String: Any]
        let networkExtension = entitlements?["com.apple.developer.networking.networkextension"] as? [String]
        let hasPacketTunnel = networkExtension?.contains("packet-tunnel-provider") == true
        let hasMemoryEntitlements = entitlements?["com.apple.developer.kernel.increased-memory-limit"] as? Bool == true
            && entitlements?["com.apple.developer.kernel.extended-virtual-addressing"] as? Bool == true
        return ProvisioningProfile(
            team: plist["TeamName"] as? String ?? "",
            expires: plist["ExpirationDate"] as? Date ?? .distantFuture,
            isDevelopment: entitlements?["get-task-allow"] as? Bool == true,
            hasPacketTunnel: hasPacketTunnel,
            hasMemoryEntitlements: hasMemoryEntitlements)
    }()
}
