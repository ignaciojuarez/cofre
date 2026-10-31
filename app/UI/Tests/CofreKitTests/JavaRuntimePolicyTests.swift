import XCTest

@testable import CofreKit

final class JavaRuntimePolicyTests: XCTestCase {
    func testMetalUsesLowestBundledRuntimeForAuto() {
        XCTAssertEqual(
            JavaRuntimePolicy.decision(
                requiredJava: 21, selectedJava: nil, renderer: .metallum,
                bundledMajors: [8, 17, 21, 25]),
            .use(major: 25))
        XCTAssertEqual(
            JavaRuntimePolicy.decision(
                requiredJava: 21, selectedJava: nil, renderer: "libmetallum.dylib",
                bundledMajors: [17, 22, 25]),
            .use(major: 22))
    }

    func testMetalRejectsExplicitOldChoicesWithoutReplacingThem() {
        for major in [8, 17, 21] {
            XCTAssertEqual(
                JavaRuntimePolicy.decision(
                    requiredJava: 21, selectedJava: major, renderer: .metallum,
                    bundledMajors: [8, 17, 21, 25]),
                .unsupportedSelection)
        }
    }

    func testMetalUsesExplicitModernChoiceAndKeepsOtherLaunches() {
        XCTAssertEqual(
            JavaRuntimePolicy.decision(
                requiredJava: 21, selectedJava: 25, renderer: .metallum,
                bundledMajors: []),
            .use(major: 25))
        XCTAssertEqual(
            JavaRuntimePolicy.decision(
                requiredJava: 21, selectedJava: nil, renderer: .mobileglues,
                bundledMajors: [25]),
            .keep)
        XCTAssertEqual(
            JavaRuntimePolicy.decision(
                requiredJava: 22, selectedJava: nil, renderer: .metallum,
                bundledMajors: [25]),
            .keep)
    }

    func testMetalReportsMissingModernRuntime() {
        XCTAssertEqual(
            JavaRuntimePolicy.decision(
                requiredJava: 21, selectedJava: nil, renderer: .metallum,
                bundledMajors: [8, 17, 21]),
            .unavailable)
    }

    func testFabricMetalGetsJava25() {
        // Air merges a Fabric profile with its base version (26.2 asks for Java 25), so the game's own runtime stays.
        XCTAssertEqual(
            JavaRuntimePolicy.decision(
                requiredJava: 25, selectedJava: nil, renderer: "libmetallum.dylib", bundledMajors: [8, 17, 21, 25]),
            .keep)
        // Unmerged metadata has no javaVersion (8): Auto still lands on the shipped Java 25.
        XCTAssertEqual(
            JavaRuntimePolicy.decision(
                requiredJava: 8, selectedJava: nil, renderer: "libmetallum.dylib", bundledMajors: [8, 17, 21, 25]),
            .use(major: 25))
    }

    func testNeoForgeMetalGetsJava25() {
        XCTAssertEqual(
            JavaRuntimePolicy.decision(
                requiredJava: 8, selectedJava: nil, renderer: .metallum, bundledMajors: [21, 25]),
            .use(major: 25))
    }
}
