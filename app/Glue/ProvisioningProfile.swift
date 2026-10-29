import Foundation

/// The app's embedded provisioning profile. iOS only opens a development build (get-task-allow) with Developer Mode
/// on and its signer trusted, so a running one proves both.
struct ProvisioningProfile {
    let team: String
    let expires: Date
    let isDevelopment: Bool

    static let current: ProvisioningProfile? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
            let data = try? Data(contentsOf: url),
            let start = data.range(of: Data("<?xml".utf8)),
            let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
            let plist = try? PropertyListSerialization.propertyList(
                from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any]
        else { return nil }
        let entitlements = plist["Entitlements"] as? [String: Any]
        return ProvisioningProfile(
            team: plist["TeamName"] as? String ?? "",
            expires: plist["ExpirationDate"] as? Date ?? .distantFuture,
            isDevelopment: entitlements?["get-task-allow"] as? Bool == true)
    }()
}
