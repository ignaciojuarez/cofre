import XCTest
@testable import CofreKit

final class ModJarMetadataTests: XCTestCase {
    func testFabricMetadataReadsDependenciesAndIcon() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jar")
        defer { try? FileManager.default.removeItem(at: url) }
        let json = """
            {"id":"sample","name":"Sample","version":"1.2","depends":{"fabric-api":">=0.1"},"icon":"assets/sample/icon.png"}
            """
        let icon = Data([0x89, 0x50, 0x4e, 0x47])
        try Zip.write(
            [
                (path: "fabric.mod.json", data: { Data(json.utf8) }),
                (path: "assets/sample/icon.png", data: { icon }),
            ], to: url)
        let metadata = try XCTUnwrap(ModJarMetadata.read(jar: url, loader: .fabric))
        XCTAssertEqual(metadata.modIDs, ["sample"])
        XCTAssertEqual(metadata.name, "Sample")
        XCTAssertEqual(metadata.version, "1.2")
        XCTAssertEqual(metadata.dependencies.map(\.id), ["fabric-api"])
        XCTAssertEqual(metadata.icon, icon)
        XCTAssertEqual(ModJarMetadata.read(jar: url, loader: .fabric), metadata)
    }

    func testNeoForgeMetadataReadsLanguageProviderAndLogo() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jar")
        defer { try? FileManager.default.removeItem(at: url) }
        let toml = """
            modLoader = "kotlinforforge"
            logoFile = "logo.png"
            [[mods]]
            modId = "sample"
            [[dependencies.sample]]
            modId = "architectury"
            type = "required"
            """
        let logo = Data([0x89, 0x50, 0x4e, 0x47])
        try Zip.write(
            [
                (path: "META-INF/neoforge.mods.toml", data: { Data(toml.utf8) }),
                (path: "logo.png", data: { logo }),
            ], to: url)
        let metadata = try XCTUnwrap(ModJarMetadata.read(jar: url, loader: .neoforge))
        XCTAssertEqual(metadata.dependencies.map(\.id), ["architectury", "kotlinforforge"])
        XCTAssertEqual(metadata.dependencies.first { $0.id == "kotlinforforge" }?.name, "Kotlin for Forge")
        XCTAssertEqual(metadata.icon, logo)
    }
}
