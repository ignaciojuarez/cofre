import XCTest
@testable import CofreKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class UpdatesTests: XCTestCase {
    func testReleaseParsingComparisonAndMalformed() throws {
        let json = #"{"tag_name":"v0.1.123","body":"notes","assets":[{"name":"manifest.plist","browser_download_url":"https://github.com/x/manifest.plist"},{"name":"Cofre.ipa","browser_download_url":"https://github.com/x/Cofre.ipa"}]}"#.data(using: .utf8)!
        XCTAssertEqual(UpdateChecker.parse(data: json, installedBuildNumber: 122)?.version, "v0.1.123")
        XCTAssertNil(UpdateChecker.parse(data: json, installedBuildNumber: 123))
        XCTAssertNil(UpdateChecker.parse(data: json, installedBuildNumber: 124))
        XCTAssertNil(UpdateChecker.parse(data: Data(#"{"tag_name":"bad"}"#.utf8), installedBuildNumber: 1))
    }
}
