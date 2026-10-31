import XCTest

@testable import CofreKit

final class ModRequirementsTests: XCTestCase {
    /// Bountiful 8.0.0-beta.2's shape: a Kotlin mod whose Modrinth page lists no dependencies.
    static let bountiful = """
        modLoader = "kotlinforforge" # Kotlin mods load through KFF
        loaderVersion = "[4,)"
        license = "MIT"

        [[mods]]
        modId = "bountiful"
        version = "8.0.0-beta.2"
        description = '''
        Bounty boards.
        [[mods]]
        modId = "notreal"
        '''

        [[dependencies.bountiful]]
        modId = "neoforge"
        type = "required"
        versionRange = "[21.1,)"

        [[dependencies.bountiful]]
        modId = "architectury"
        type = "required"

        [[dependencies.bountiful]]
        modId = "jei"
        type = "optional"

        [[dependencies.bountiful]]
        modId = "serverstuff"
        type = "required"
        side = "SERVER"

        [[dependencies.bountiful]]
        modId = "${placeholder}"
        type = "required"
        """

    private func jar(_ files: [(String, Data)]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jar")
        try Zip.write(files.map { file in (path: file.0, data: { file.1 }) }, to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testParsesLoaderModsAndRequiredDependencies() {
        let toml = ModsToml(text: Self.bountiful)
        XCTAssertEqual(toml.modLoader, "kotlinforforge")
        XCTAssertEqual(toml.modIDs, ["bountiful"])
        XCTAssertEqual(toml.dependencies.filter(\.required).map(\.modID), ["neoforge", "architectury"])
        XCTAssertEqual(toml.dependencies.first?.owner, "bountiful")
    }

    func testForgeMandatoryCounts() {
        let toml = ModsToml(
            text: """
                modLoader="javafml"
                [[mods]]
                modId="a"
                [[dependencies.a]]
                    modId="cloth_config"
                    mandatory=true
                [[dependencies.a]]
                    modId="b"
                    mandatory=false
                """)
        XCTAssertEqual(toml.dependencies.filter(\.required).map(\.modID), ["cloth_config"])
        XCTAssertEqual(ModRequirements.missing(in: [("a.jar", toml)]).first?.slugs, ["cloth-config", "cloth_config"])
    }

    func testReadsJarAndFlagsKotlinForForge() throws {
        let url = try jar([
            ("META-INF/neoforge.mods.toml", Data(Self.bountiful.utf8)), ("x/Y.class", Data([0xca, 0xfe])),
        ])
        let toml = try XCTUnwrap(ModsToml.read(jar: url, neoForge: true))
        let missing = ModRequirements.missing(in: [("bountiful-neoforge-8.0.0-beta.2.jar", toml)])
        XCTAssertEqual(missing.map(\.modID), ["kotlinforforge", "architectury"])
        XCTAssertEqual(missing[0].projectID, "ordsPcFz")
        XCTAssertEqual(missing[0].name, "Kotlin for Forge")
        XCTAssertEqual(missing[0].reason, "modLoader:kotlinforforge")
        XCTAssertEqual(missing[0].neededBy, "bountiful-neoforge-8.0.0-beta.2.jar")
        XCTAssertEqual(missing[1].slugs, ["architectury-api", "architectury"])
    }

    func testInstalledProvidersAndBundledJarsSatisfy() throws {
        let toml = ModsToml(text: Self.bountiful)
        // Kotlin for Forge by file name, Architectury by another jar's mods.toml.
        let arch = ModsToml(text: "modLoader=\"javafml\"\n[[mods]]\nmodId=\"architectury\"")
        XCTAssertEqual(
            ModRequirements.missing(
                in: [("b.jar", toml), ("arch.jar", arch)], otherFiles: ["kotlinforforge-5.5.0-all.jar"]),
            [])
        // Bundled inside the jar (jar-in-jar) counts too.
        let inner = try Data(contentsOf: jar([("META-INF/mods.toml", Data("[[mods]]\nmodId=\"architectury\"".utf8))]))
        let url = try jar([
            ("META-INF/neoforge.mods.toml", Data(Self.bountiful.utf8)), ("META-INF/jarjar/arch-1.jar", inner),
        ])
        let read = try XCTUnwrap(ModsToml.read(jar: url, neoForge: true))
        XCTAssertEqual(ModRequirements.missing(in: [("b.jar", read)]).map(\.modID), ["kotlinforforge"])
    }

    func testPlainJarHasNoToml() throws {
        XCTAssertNil(ModsToml.read(jar: try jar([("fabric.mod.json", Data("{}".utf8))]), neoForge: true))
    }

    func testCrashCluesNameTheMissingMod() {
        let neo =
            "Failure message: Mod File mods/bountiful-neoforge-8.0.0-beta.2.jar needs language provider kotlinforforge:4 or above to load"
        let kff = ModRequirements.fromCrash(neo)
        XCTAssertEqual(kff.map(\.projectID), ["ordsPcFz"])
        XCTAssertEqual(kff.first?.neededBy, "bountiful-neoforge-8.0.0-beta.2.jar")

        let requires = """
            	Failure message: Mod sophisticatedbackpacks requires sophisticatedcore 1.0.0 or above
            		Currently, sophisticatedcore is not installed
            	Failure message: Mod foo requires bar 2.0 or above
            		Currently, bar is 1.0
            """
        let found = ModRequirements.fromCrash(requires)
        XCTAssertEqual(found.map(\.modID), ["sophisticatedcore"])
        XCTAssertEqual(found.first?.slugs, ["sophisticated-core", "sophisticatedcore"])

        XCTAssertEqual(
            ModRequirements.fromCrash(
                "Mod ID: 'kotlinforforge', Requested by: 'bountiful', Expected range: '[4,)', Actual version: '[MISSING]'"
            ).map(\.projectID), ["ordsPcFz"])
        XCTAssertEqual(
            ModRequirements.fromCrash(
                "Mod 'Bountiful' (bountiful) 6.0.0 requires any version of fabric-language-kotlin, which is missing!"
            )
            .map(\.modID), ["fabric-language-kotlin"])
        XCTAssertEqual(
            ModRequirements.fromCrash("Mod x requires minecraft 1.21\nCurrently, minecraft is not installed"), [])
    }
}
