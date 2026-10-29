import Foundation

#if canImport(XCTest)
    import XCTest
    final class PairingFileValidatorTests: XCTestCase {
        func testRejectsFakeCredentials() {
            let d: [String: Any] = [
                "HostID": "", "SystemBUID": "b", "UDID": "u", "HostCertificate": Data(), "HostPrivateKey": Data([1]),
                "RootCertificate": Data([1]), "RootPrivateKey": Data([1]),
            ]
            let data = try! PropertyListSerialization.data(fromPropertyList: d, format: .xml, options: 0)
            XCTAssertThrowsError(try PairingFileValidator.validate(data))
        }
    }
#endif
