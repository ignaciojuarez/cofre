import Foundation
#if canImport(XCTest)
import XCTest

final class PairingFileValidatorTests: XCTestCase {
    func testRejectsNonDictionary() {
        let arrayData = try! PropertyListSerialization.data(fromPropertyList: ["Item1", "Item2"], format: .xml, options: 0)
        XCTAssertThrowsError(try PairingFileValidator.validate(arrayData)) { error in
            XCTAssertEqual(error as? PairingFileValidationError, .notDictionary)
        }
    }

    func testRejectsMissingRequiredKeys() {
        let incompleteDict: [String: Any] = [
            "HostID": "my-host-id",
            "SystemBUID": "my-buid"
        ]
        let data = try! PropertyListSerialization.data(fromPropertyList: incompleteDict, format: .xml, options: 0)
        XCTAssertThrowsError(try PairingFileValidator.validate(data)) { error in
            guard case .missing(let key) = error as? PairingFileValidationError else {
                XCTFail("Expected missing key error, got \(error)")
                return
            }
            XCTAssertTrue(PairingFileValidator.requiredKeys.contains(key))
        }
    }

    func testRejectsWrongTypeForCertificates() {
        let wrongTypeDict: [String: Any] = [
            "HostID": "my-host-id",
            "SystemBUID": "my-buid",
            "HostCertificate": "not-data-a-string",
            "HostPrivateKey": Data([0x01, 0x02]),
            "RootCertificate": Data([0x03, 0x04])
        ]
        let data = try! PropertyListSerialization.data(fromPropertyList: wrongTypeDict, format: .xml, options: 0)
        XCTAssertThrowsError(try PairingFileValidator.validate(data)) { error in
            XCTAssertEqual(error as? PairingFileValidationError, .wrongType("HostCertificate"))
        }
    }

    func testAcceptsValidPairingFileAndExtractsUDID() {
        let validDict: [String: Any] = [
            "HostID": "my-host-id",
            "SystemBUID": "my-buid",
            "HostCertificate": Data([0xAA, 0xBB]),
            "HostPrivateKey": Data([0xCC, 0xDD]),
            "RootCertificate": Data([0xEE, 0xFF]),
            "UDID": "OLD_DEVICE_UDID"
        ]
        let data = try! PropertyListSerialization.data(fromPropertyList: validDict, format: .xml, options: 0)
        XCTAssertNoThrow({
            let udid = try PairingFileValidator.validate(data)
            XCTAssertEqual(udid, "OLD_DEVICE_UDID")
        }())
    }
}
#endif
