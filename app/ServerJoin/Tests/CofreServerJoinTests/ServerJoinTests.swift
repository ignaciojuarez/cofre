import XCTest

@testable import CofreServerJoin

final class ServerJoinTests: XCTestCase {
    let examples = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("plan/server-join/examples")
    func card(_ name: String) throws -> Data { try Data(contentsOf: examples.appendingPathComponent(name + ".json")) }
    func testEveryValidFixture() throws {
        for n in ["fabric-modrinth", "forge-curseforge-restricted", "ios-override", "update-diff"] {
            XCTAssertNoThrow(try CardDecoder.decodeCard(card(n)))
        }
    }
    func testEveryMaliciousFixture() throws {
        for n in ["http-malicious", "path-malicious", "wildcard-malicious", "missing-required-invalid"] {
            XCTAssertThrowsError(try CardDecoder.decodeCard(card(n)))
        }
    }
    func testDeepLink() throws {
        XCTAssertEqual(
            try Discovery.deepLink(URL(string: "cofre://join?card=https%3A%2F%2Fexample.test%2Fx")!).absoluteString,
            "https://example.test/x")
    }
    func testDeepLinkServerMismatchRejected() throws {
        let c = try CardDecoder.decodeCard(card("fabric-modrinth"))
        let link = URL(string: "cofre://join?server=other.test:25565&card=https%3A%2F%2Fexample.test%2Fx")!
        XCTAssertThrowsError(try Discovery.deepLink(link, card: c))
    }
    func testURLPolicyRejectsUserinfoPortsAndCanonicalizesIDN() throws {
        XCTAssertThrowsError(try URLPolicy.validate(URL(string: "https://u:p@example.test/x")!, allowedHosts: ["example.test"]))
        XCTAssertThrowsError(try URLPolicy.validate(URL(string: "https://example.test:444/x")!, allowedHosts: ["example.test"]))
        let url = try URLPolicy.validate(URL(string: "https://bücher.example./x")!, allowedHosts: ["xn--bcher-kva.example"])
        XCTAssertEqual(url.host, "xn--bcher-kva.example")
    }
    func testWellKnown() {
        XCTAssertEqual(
            Discovery.wellKnown(host: "a.test").absoluteString, "https://a.test/.well-known/minecraft-server-card.json")
    }
    func testUnknownFieldRejected() throws {
        var d = try JSONSerialization.jsonObject(with: card("fabric-modrinth")) as! [String: Any]
        d["x"] = 1
        XCTAssertThrowsError(try CardDecoder.decodeCard(JSONSerialization.data(withJSONObject: d)))
    }
    func testHTTPSRejected() throws {
        var d = try JSONSerialization.jsonObject(with: card("fabric-modrinth")) as! [String: Any]
        var p = d["pack"] as! [String: Any]
        p["url"] = "http://example.test/x"
        d["pack"] = p
        XCTAssertThrowsError(try CardDecoder.decodeCard(JSONSerialization.data(withJSONObject: d)))
    }
    func testWildcardRejected() throws { XCTAssertThrowsError(try CardDecoder.decodeCard(card("wildcard-malicious"))) }
    func testPathRejected() throws { XCTAssertThrowsError(try CardDecoder.decodeCard(card("path-malicious"))) }
    func testSizeCap() { XCTAssertThrowsError(try CardDecoder.decodeCard(Data(repeating: 0, count: 513 * 1024))) }
    func testTOFUFirstAndSameKey() async throws {
        let c = try CardDecoder.decodeCard(card("fabric-modrinth"))
        let e = CardEnvelope(
            format: "cofre-card-envelope/1", payload: "", keyID: "k", publicKey: String(repeating: "A", count: 43),
            signature: String(repeating: "B", count: 86), previousKeySignature: nil)
        let s = MemoryTrustStore()
        let first = await TrustVerifier.evaluate(card: c, envelope: e, store: s)
        XCTAssertTrue(first.firstVisit)
        await TrustVerifier.confirm(card: c, envelope: e, store: s)
        let second = await TrustVerifier.evaluate(card: c, envelope: e, store: s)
        XCTAssertFalse(second.keyChanged)
    }
    func testTrustPersistsAcrossReinitAndKeyChangeBlocks() async throws {
        let c = try CardDecoder.decodeCard(card("fabric-modrinth"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("trust-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = CardEnvelope(format: "cofre-card-envelope/1", payload: "", keyID: "k", publicKey: String(repeating: "A", count: 43), signature: String(repeating: "B", count: 86), previousKeySignature: nil)
        let store = FileTrustStore(url: url)
        await TrustVerifier.confirm(card: c, envelope: first, store: store)
        let reloaded = FileTrustStore(url: url)
        let same = await TrustVerifier.evaluate(card: c, envelope: first, store: reloaded)
        XCTAssertFalse(same.firstVisit)
        let changed = CardEnvelope(format: first.format, payload: "", keyID: "new", publicKey: String(repeating: "C", count: 43), signature: first.signature, previousKeySignature: nil)
        let rotation = await TrustVerifier.evaluate(card: c, envelope: changed, store: reloaded)
        XCTAssertTrue(rotation.keyChanged)
    }
    func testOriginBinding() async throws {
        let c = try CardDecoder.decodeCard(card("fabric-modrinth"))
        let e = CardEnvelope(
            format: "cofre-card-envelope/1", payload: "", keyID: "k", publicKey: String(repeating: "A", count: 43),
            signature: String(repeating: "B", count: 86), previousKeySignature: nil)
        let s = MemoryTrustStore()
        await s.save(TrustRecord(origin: "https://other.test", keyID: "k", fingerprint: e.publicKey))
        let decision = await TrustVerifier.evaluate(card: c, envelope: e, store: s)
        XCTAssertTrue(decision.firstVisit)
    }
    func testUpdateDiffFields() throws {
        let i = MrpackIndex(
            dependencies: [:],
            files: [MrpackFile(path: "a", hashes: ["sha512": "1"], downloads: [], fileSize: 2, env: nil)])
        let n = MrpackIndex(
            dependencies: [:],
            files: [MrpackFile(path: "b", hashes: ["sha512": "2"], downloads: [], fileSize: 3, env: nil)])
        let d = UpdateDiffer.diff(old: i, new: n, userOptional: ["a"])
        XCTAssertEqual(d.added, ["b"])
        XCTAssertEqual(d.preservedUserOptional, ["a"])
    }
    func testPlannerTotal() throws {
        let c = try CardDecoder.decodeCard(card("fabric-modrinth"))
        let i = MrpackIndex(
            dependencies: [:],
            files: [MrpackFile(path: "mods/a.jar", hashes: [:], downloads: [], fileSize: 4, env: nil)])
        XCTAssertEqual(InstallPlanner.plan(card: c, index: i).totalDownloadSize, 4)
    }
    func testPlannerIOSExclude() throws {
        let c = try CardDecoder.decodeCard(card("ios-override"))
        let i = MrpackIndex(
            dependencies: [:],
            files: [MrpackFile(path: "mod:voicechat", hashes: [:], downloads: [], fileSize: 2, env: nil)])
        XCTAssertTrue(InstallPlanner.plan(card: c, index: i).entries.isEmpty)
    }
    func testPlannerManualCurseForge() throws {
        let c = try CardDecoder.decodeCard(card("forge-curseforge-restricted"))
        let i = MrpackIndex(
            dependencies: [:],
            files: [
                MrpackFile(
                    path: "x", hashes: [:], downloads: [URL(string: "https://curseforge.com/x")!], fileSize: 1, env: nil
                )
            ])
        XCTAssertTrue(InstallPlanner.plan(card: c, index: i).entries[0].manual)
    }
    func testPlannerEnvironment() throws {
        let c = try CardDecoder.decodeCard(card("fabric-modrinth"))
        let i = MrpackIndex(
            dependencies: [:],
            files: [MrpackFile(path: "x", hashes: [:], downloads: [], fileSize: 1, env: ["client": "unsupported"])])
        XCTAssertTrue(InstallPlanner.plan(card: c, index: i).entries.isEmpty)
    }
    func testEnvelopeMalformedRejected() { XCTAssertThrowsError(try CardDecoder.decodeEnvelope(Data("{}".utf8))) }
    func testSignatureTamperRejected() throws {
        let e = CardEnvelope(
            format: "cofre-card-envelope/1", payload: "eA", keyID: "k", publicKey: String(repeating: "A", count: 43),
            signature: String(repeating: "B", count: 86), previousKeySignature: nil)
        XCTAssertThrowsError(try CardDecoder.verify(envelope: e, payload: Data("x".utf8)))
    }
    func testUpdateDownloadSize() {
        let a = MrpackIndex(dependencies: [:], files: [])
        let b = MrpackIndex(
            dependencies: [:], files: [MrpackFile(path: "x", hashes: [:], downloads: [], fileSize: 9, env: nil)])
        XCTAssertEqual(UpdateDiffer.diff(old: a, new: b).downloadSize, 9)
    }
    func testCompatibilityField() throws {
        let c = try CardDecoder.decodeCard(card("ios-override"))
        XCTAssertNotNil(c.platformOverrides)
    }
    func testLoaderDecoded() throws {
        XCTAssertEqual(try CardDecoder.decodeCard(card("fabric-modrinth")).loader.type, .fabric)
    }
    func testAddressDecoded() throws {
        XCTAssertEqual(try CardDecoder.decodeCard(card("fabric-modrinth")).server.addresses[0].port, 25565)
    }
    func testPackHashLength() throws {
        XCTAssertEqual(try CardDecoder.decodeCard(card("fabric-modrinth")).pack.sha512.count, 128)
    }
}
