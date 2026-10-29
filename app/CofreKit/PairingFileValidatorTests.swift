import Foundation
#if canImport(XCTest)
import XCTest
final class PairingFileValidatorTests: XCTestCase { func testRejectsMissingKey() { let d = try! PropertyListSerialization.data(fromPropertyList:["HostID":"x"], format:.xml, options:0); XCTAssertThrowsError(try PairingFileValidator.validate(d)) } }
#endif
