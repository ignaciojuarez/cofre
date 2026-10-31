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

    // NeoForge refuses later events "to a broken mod state"; the shader event in that line isn't the cause.
    func testNeoForgeLoaderFailureBeatsTheShaderEvent() {
        let client = """
            Description: Rendering overlay
            java.lang.IllegalStateException: Cowardly refusing to send event net.neoforged.neoforge.client.event.RegisterShadersEvent to a broken mod state
            """
        let log = """
            [22:43:32] [Render thread/FATAL] [ne.ne.fm.ModLoader/CORE]: Error during pre-loading phase: Mod File mods/bountiful.jar needs language provider kotlinforforge:4 or above to load
            [22:43:32] [Render thread/ERROR] [ne.ne.fm.ModLoader/]: Cowardly refusing to send event net.neoforged.neoforge.client.event.RegisterShadersEvent to a broken mod state
            """
        let r = diagnose(1, report: client, log: log)
        XCTAssertEqual(r.reason, .mods)
        XCTAssertEqual(r.clue, "Mod File mods/bountiful.jar needs language provider kotlinforforge:4 or above to load")
    }

    // The shader pack in System Details and an INFO log line must not turn a Java error into a renderer one.
    func testMetalDriverCrashIsTheRenderer() {
        let fatal = "#  SIGSEGV (0xb)\n  #19 0x262d24730  /System/Library/Extensions/AGXMetalG18P.bundle/AGXMetalG18P"
        let midGame = diagnose(134, log: "[17:03:20] [Render thread/INFO]: Reloading ResourceManager: vanilla\n" + fatal)
        XCTAssertEqual(midGame.reason, .renderer)
        XCTAssertEqual(midGame.clue, GameExitReport.metalReload)
        XCTAssertEqual(midGame.explanation, "Metal crashed while reloading graphics.")
        XCTAssertTrue(midGame.nextStep.contains("before joining a world"))
        XCTAssertEqual(diagnose(134, log: fatal).clue, "Metal crashed in the GPU driver.")

        // Metallum's logging pushed the reload line out of the tail; the changed setting still tells, and is named.
        let named = GameExitReport(code: 134, crashReport: nil, log: fatal, changedSettings: ["Mipmap levels"])
        XCTAssertEqual(named.clue, GameExitReport.metalReload)
        XCTAssertTrue(named.nextStep.hasPrefix("Your change to Mipmap levels is saved for next time."))
    }

    func testGLOnlyModOnMetalNamesTheMod() {
        let report = """
            Description: Initializing game

            java.lang.ExceptionInInitializerError
            	at knot//net.irisshaders.iris.Iris.setDebug(Iris.java:432)
            Caused by: java.lang.IllegalStateException: No GLCapabilities instance set for the current thread.
            	at knot//org.lwjgl.opengl.GL.checkCapabilities(GL.java:288)
            """
        let r = diagnose(1, report: report)
        XCTAssertEqual(r.reason, .mods)
        XCTAssertEqual(r.clue, "Iris " + GameExitReport.needsGL)
        XCTAssertTrue(r.nextStep.hasPrefix("Turn that mod off"))
    }

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

extension GameExitTests {
    func testRejoinDetectsLastServerAndExpires() {
        let log = "Connecting to old.example, 25565\nConnecting to play.example, 25566\n"
        XCTAssertEqual(RejoinDetector.server(in: log), "play.example:25566")
        let defaults = UserDefaults(suiteName: "rejoin-test")!
        defaults.removePersistentDomain(forName: "rejoin-test")
        RejoinIntentStore.save(RejoinIntent(instanceID: "i", kind: .server, target: "play.example:25566", displayName: "Play"), defaults: defaults)
        XCTAssertNotNil(RejoinIntentStore.load(defaults: defaults))
        let expired = RejoinIntent(instanceID: "i", kind: .world, target: "world", displayName: "World", createdAt: .now.addingTimeInterval(-601))
        RejoinIntentStore.save(expired, defaults: defaults)
        XCTAssertNil(RejoinIntentStore.load(defaults: defaults))
    }
}
