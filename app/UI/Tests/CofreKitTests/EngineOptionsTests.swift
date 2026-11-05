import XCTest

@testable import CofreKit

final class EngineOptionsTests: XCTestCase {
    func testDefaultsAddNothing() {
        XCTAssertEqual(EngineOptions().jvmFlags(javaMajor: 25, gameDirectory: nil), [])
    }

    func testFlagsFollowTheRuntime() {
        let options = EngineOptions(codeCacheMB: 256, compactHeaders: true, collector: .zgc, logGC: true)
        XCTAssertEqual(
            options.jvmFlags(javaMajor: 25, gameDirectory: nil),
            [
                "-XX:ReservedCodeCacheSize=256m", "-XX:+UseCompactObjectHeaders", "-XX:-UseG1GC", "-XX:+UseZGC",
                "-Xlog:gc",
            ])
        // Java 21 doesn't know compact headers, and an unknown -XX option stops the JVM.
        XCTAssertEqual(
            options.jvmFlags(javaMajor: 21, gameDirectory: nil),
            ["-XX:ReservedCodeCacheSize=256m", "-XX:-UseG1GC", "-XX:+UseZGC", "-Xlog:gc"])
        // Java 8: Air leaves its default collector and has no unified logging.
        XCTAssertEqual(options.jvmFlags(javaMajor: 8, gameDirectory: nil), ["-XX:ReservedCodeCacheSize=256m"])
    }

    func testCodeCacheIsClamped() {
        XCTAssertEqual(
            EngineOptions(codeCacheMB: 4).jvmFlags(javaMajor: 25, gameDirectory: nil), ["-XX:ReservedCodeCacheSize=48m"]
        )
        XCTAssertEqual(
            EngineOptions(codeCacheMB: 4096).jvmFlags(javaMajor: 25, gameDirectory: nil),
            ["-XX:ReservedCodeCacheSize=512m"])
    }

    func testFlightRecorderWritesIntoTheGameFolder() {
        let flags = EngineOptions(flightRecorder: true).jvmFlags(
            javaMajor: 25, gameDirectory: URL(fileURLWithPath: "/game"))
        XCTAssertEqual(flags.first, "-XX:FlightRecorderOptions:repository=/game/cofre-jfr")
        XCTAssertTrue(flags.last?.hasPrefix("-XX:StartFlightRecording=settings=profile,") == true)
        XCTAssertTrue(flags.last?.hasSuffix("filename=/game/cofre-jfr/cofre.jfr") == true)
        XCTAssertEqual(EngineOptions(flightRecorder: true).jvmFlags(javaMajor: 25, gameDirectory: nil), [])
    }

    func testDecodesPartialJSONAndRoundTripsThroughDefaults() throws {
        let decoded = try JSONDecoder().decode(
            EngineOptions.self, from: Data(#"{"detachJIT": true, "collector": "parallel"}"#.utf8))
        XCTAssertEqual(decoded, EngineOptions(collector: .parallel, detachJIT: true))
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        XCTAssertEqual(EngineOptions.load(from: defaults), EngineOptions())
        decoded.save(to: defaults)
        XCTAssertEqual(EngineOptions.load(from: defaults), decoded)
    }

    func testGraphicsBackendArguments() {
        XCTAssertEqual(
            GraphicsBackendArguments.arguments(renderer: "libmetallum.dylib", gameVersion: "26.2"),
            ["--graphicsBackend", "default"])
        XCTAssertEqual(GraphicsBackendArguments.arguments(renderer: .metallum, gameVersion: "1.21.11"), [])
        XCTAssertEqual(
            GraphicsBackendArguments.arguments(renderer: "libMoltenVK.dylib", gameVersion: "26.3"),
            ["--graphicsBackend", "vulkan"])
        XCTAssertEqual(GraphicsBackendArguments.arguments(renderer: .vulkan, gameVersion: "26.1"), [])
        XCTAssertEqual(GraphicsBackendArguments.arguments(renderer: .mobileglues, gameVersion: "26.3"), [])
    }
}
