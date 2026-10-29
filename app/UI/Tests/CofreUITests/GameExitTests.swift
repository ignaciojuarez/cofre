import XCTest

@testable import CofreUI

/// G01: why Minecraft stopped, from the exit code, crash report and log. Runs on the Mac too.
final class GameExitTests: XCTestCase {
    private func diagnose(_ code: Int = -1, report: String? = nil, log: String = "") -> GameExitReport {
        GameExitReport(code: code, crashReport: report, log: log)
    }

    func testEverySampleGetsItsReason() {
        for reason in GameExitReport.Reason.allCases {
            let s = MockGameExit.sample(reason)
            XCTAssertEqual(diagnose(s.code, report: s.crashReport, log: s.log).reason, reason, "\(reason)")
        }
    }

    func testCluesAreTheTellingLine() {
        XCTAssertEqual(MockGameExit.report(.memory).clue, "java.lang.OutOfMemoryError: Java heap space")
        XCTAssertEqual(
            MockGameExit.report(.renderer).clue, "GLFW error 65543: No OpenGL context",
            "log prefixes like [17:42:09] [Render thread/ERROR]: are dropped")
        XCTAssertTrue(MockGameExit.report(.mods).clue?.contains("requires version") == true)
        XCTAssertTrue(MockGameExit.report(.java).clue?.hasPrefix("java.lang.NullPointerException") == true)
    }

    // The shader pack in System Details and an INFO log line must not turn a Java error into a renderer one.
    func testSystemDetailsAndInfoLinesDontCount() {
        let report = """
            Description: Ticking entity
            java.lang.IllegalStateException: boom
            -- System Details --
            	Loaded Shaderpack: BSL.zip
            	java.lang.OutOfMemoryError mentioned in a mod name
            """
        let r = diagnose(report: report, log: "[INFO]: Loaded shader pack BSL.zip")
        XCTAssertEqual(r.reason, .java)
        XCTAssertEqual(r.clue, "java.lang.IllegalStateException: boom")
    }

    func testCrashReportBeatsTheLog() {
        let r = diagnose(
            report: "java.lang.OutOfMemoryError: Metaspace", log: "[ERROR]: GLFW error 1: No OpenGL context")
        XCTAssertEqual(r.reason, .memory)
    }

    func testMemoryBeatsModsInOneSource() {
        let log = """
            [ERROR]: java.lang.NoSuchMethodError: 'void foo()'
            [ERROR]: java.lang.OutOfMemoryError: Java heap space
            """
        XCTAssertEqual(diagnose(log: log).reason, .memory)
    }

    func testForgeMissingDependencyIsMods() {
        let log =
            "[main/ERROR]: Missing or unsupported mandatory dependencies:\n\tMod ID: 'geckolib', Requested by: 'mowziesmobs'"
        XCTAssertEqual(diagnose(log: log).reason, .mods)
    }

    func testNothingToGoOn() {
        XCTAssertEqual(diagnose(1).reason, .unknown)
        XCTAssertNil(diagnose(1).clue)
        XCTAssertEqual(diagnose(0).reason, .quit)
        XCTAssertEqual(diagnose(report: "---- Minecraft Crash Report ----").reason, .java, "a crash report alone")
    }

    func testLongCluesAreTrimmed() {
        let r = diagnose(log: "[ERROR]: java.lang.UnsatisfiedLinkError: " + String(repeating: "x", count: 400))
        XCTAssertEqual(r.reason, .missingLibrary)
        XCTAssertEqual(r.clue?.count, 200)
        XCTAssertEqual(r.clue?.last, "…")
    }

    func testDetailsTextAndTail() {
        let log = (1...100).map { "line \($0)" }.joined(separator: "\n")
        let r = GameExitReport(
            code: -1, crashReport: nil, log: log, instance: "Survival+",
            files: [URL(fileURLWithPath: "/l/latestlog.txt"), URL(fileURLWithPath: "/c/crash-1.txt")])
        XCTAssertEqual(r.logTail.count, 60)
        XCTAssertEqual(r.logTail.last, "line 100")
        XCTAssertTrue(r.detailsText.hasPrefix("Minecraft stopped: It closed unexpectedly."))
        XCTAssertTrue(r.detailsText.contains("Instance: Survival+\nExit code: -1"))
        XCTAssertTrue(r.detailsText.contains("Crash report: crash-1.txt"))
        XCTAssertTrue(r.detailsText.hasSuffix("line 100"))
        XCTAssertFalse(r.detailsText.contains("line 80\n"), "only the last 20 lines")
    }

    func testEveryReasonHasCopy() {
        for reason in GameExitReport.Reason.allCases {
            let r = GameExitReport(code: 1, reason: reason)
            XCTAssertFalse(r.explanation.isEmpty || r.nextStep.isEmpty, "\(reason)")
        }
    }
}
