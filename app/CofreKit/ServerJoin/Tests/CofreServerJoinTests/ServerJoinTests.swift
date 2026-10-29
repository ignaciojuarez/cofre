import XCTest
@testable import CofreServerJoin
final class ServerJoinTests: XCTestCase {
 let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
 func testExamples() throws { let dir=root.appendingPathComponent("../launcher-plan/server-join/examples"); for name in ["fabric-modrinth","forge-curseforge-restricted","ios-override","update-diff"] { let d=try Data(contentsOf:dir.appendingPathComponent(name+".json")); XCTAssertNoThrow(try CardDecoder.decode(d)) }; for name in ["http-malicious","path-malicious","wildcard-malicious","missing-required-invalid"] { let d=try Data(contentsOf:dir.appendingPathComponent(name+".json")); XCTAssertThrowsError(try CardDecoder.decode(d)) } }
 func testDeepLink() throws { let u=try Discovery.deepLink(URL(string:"cofre://join?card=https%3A%2F%2Fexample.test%2Fcard.json")!); XCTAssertEqual(u.absoluteString,"https://example.test/card.json") }
 func testTOFUAndChange() async throws { let d=try Data(contentsOf:root.appendingPathComponent("../launcher-plan/server-join/examples/fabric-modrinth.json")); let c=try CardDecoder.decode(d); let s=MemoryTrustStore(); let first=try await TrustVerifier.evaluate(c,store:s); XCTAssertTrue(first.firstVisit); await TrustVerifier.confirm(c,store:s); let second=try await TrustVerifier.evaluate(c,store:s); XCTAssertFalse(second.firstVisit) }
}
