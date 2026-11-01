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
    func testShutdownCrashAfterStoppingIsAQuit() {
        let log = [
            "[16:16:02] [Render thread/INFO]: Stopping!",
            "#  SIGSEGV (0xb) at pc=0x0000000100fffc4c, pid=4110, tid=67891",
            "# C  [AngelAuraAmethyst+0x6fc4c]  gl_terminate+0x88",
            "  #09 0x1012b6d3c  Cofre.app/AngelAuraAmethyst  pojavTerminate + 3304764",
        ]
        XCTAssertEqual(GameExitReport.diagnose(code: 1, crashReport: nil, logLines: log).0, .quit)
        // The same trace while the game is running is still a crash.
        XCTAssertNotEqual(GameExitReport.diagnose(code: 1, crashReport: nil, logLines: Array(log.dropFirst())).0, .quit)
    }

    func testMetalDriverCrashIsTheRenderer() {
        let fatal = """
            [Render thread/INFO]: [metallum] createTexture 512x256 fmt=RGBA8_UNORM usage=0xf
            # A fatal error has been detected by the Java Runtime Environment:
            #  SIGSEGV (0xb)
            # Problematic frame:
            # C  [libobjc.A.dylib+0x127c]  objc_retain+0x10
            ===== [Amethyst fatal trace] ... reason: abort() called
              #08 0x2565688ec  /System/Library/Extensions/AGXMetalG14.bundle/AGXMetalG14
            """
        let midGame = diagnose(134, log: "[17:03:20] [Render thread/INFO]: Reloading ResourceManager: vanilla\n" + fatal)
        XCTAssertEqual(midGame.reason, .renderer)
        XCTAssertEqual(midGame.clue, GameExitReport.metalReload)
        XCTAssertEqual(midGame.explanation, "Metal crashed while reloading graphics.")
        XCTAssertTrue(midGame.nextStep.contains("before joining a world"))
        let native = diagnose(134, log: fatal)
        XCTAssertEqual(native.clue, "The Metal renderer crashed.")
        XCTAssertEqual(native.explanation, "The Metal renderer crashed.")
        XCTAssertTrue(native.nextStep.contains("switch the renderer in the instance settings"))

        // Metallum's logging pushed the reload line out of the tail; the changed setting still tells, and is named.
        let named = GameExitReport(code: 134, crashReport: nil, log: fatal, changedSettings: ["Mipmap levels"])
        XCTAssertEqual(named.clue, GameExitReport.metalReload)
        XCTAssertTrue(named.nextStep.hasPrefix("Your change to Mipmap levels is saved for next time."))
    }

    func testNativeMobileGluesCrashIsNamed() {
        let fatal = """
            # A fatal error has been detected by the Java Runtime Environment:
            #  SIGBUS (0x7)
            # Problematic frame:
            # C  [libmobileglues.dylib+0x1234]  glDrawElements+0x10
            """
        let r = diagnose(134, log: fatal)
        XCTAssertEqual(r.reason, .renderer)
        XCTAssertEqual(r.explanation, "The MobileGlues renderer crashed.")
    }

    func testNativeRendererMarkersCoverShippedBackends() {
        let cases = [
            ("libmetallum.dylib", "The Metal renderer crashed."),
            ("MetalUniversal-1.0.4.jar", "The Metal renderer crashed."),
            ("libspvc.dylib", "The Metal renderer crashed."),
            ("ANGLE", "The ANGLE renderer crashed."),
            ("libtinygl4angle.dylib", "The ANGLE renderer crashed."),
        ]
        for (marker, explanation) in cases {
            let r = diagnose(log: "# SIGSEGV (0xb)\n#08 \(marker)")
            XCTAssertEqual(r.reason, .renderer, marker)
            XCTAssertEqual(r.explanation, explanation, marker)
        }
        XCTAssertNotEqual(diagnose(log: "#08 AGXMetalG14.bundle").reason, .renderer)
    }

    func testNativeRendererDoesNotHideLoaderOrMemoryFailure() {
        let native = "# SIGSEGV (0xb)\n#08 /System/Library/Extensions/AGXMetalG14.bundle/AGXMetalG14"
        let loader = diagnose(log: "Error during pre-loading phase: Mod File mods/bountiful.jar needs language provider kotlinforforge:4 or above to load\n" + native)
        XCTAssertEqual(loader.reason, .mods)
        let memory = diagnose(report: "java.lang.OutOfMemoryError: Java heap space", log: native)
        XCTAssertEqual(memory.reason, .memory)
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

    /// NeoForge 26.2 + MetalUniversal + Distant Horizons (iPhone 17 Pro, crash-2026-10-31_17.08.36-client.txt).
    func testOpenGLModHandedAMetalTextureNamesTheMod() {
        let report = """
            Description: Render Frame

            java.lang.ClassCastException: class com.metallum.client.metal.render.MetalGpuTexture cannot be cast to class com.mojang.blaze3d.opengl.GlTexture (com.metallum.client.metal.render.MetalGpuTexture is in module metallum@1.0.4 of loader 'TRANSFORMER' @3d4d3fe7; com.mojang.blaze3d.opengl.GlTexture is in module minecraft@26.2 of loader 'TRANSFORMER' @3d4d3fe7)
            	at TRANSFORMER/minecraft@26.2/net.minecraft.client.renderer.Lightmap.handler$zkf000$distanthorizons$render(Lightmap.java:620) ~[minecraft-client-patched-<redacted-address>.jar:?] {neoforge:mixin[APP:DistantHorizons.neoforge.mixins.json:client.MixinLightTexture from mod distanthorizons]}
            	at TRANSFORMER/minecraft@26.2/net.minecraft.client.renderer.Lightmap.render(Lightmap.java:93) ~[minecraft-client-patched-<redacted-address>.jar:?] {neoforge:mixin[APP:DistantHorizons.neoforge.mixins.json:client.MixinLightTexture from mod distanthorizons]}
            	at TRANSFORMER/minecraft@26.2/net.minecraft.client.renderer.GameRenderer.render(GameRenderer.java:427) ~[minecraft-client-patched-<redacted-address>.jar:?] {neoforge:access_transformer,neoforge:access_transformer,neoforge:mixin[APP:fabric-rendering-v1.mixins.json:GameRendererMixin from mod fabric_rendering_v1,APP:DistantHorizons.neoforge.mixins.json:client.MixinGameRenderer from mod distanthorizons]}
            """
        let r = diagnose(-1, report: report)
        XCTAssertEqual(r.reason, .mods)
        XCTAssertEqual(r.clue, "Distant Horizons " + GameExitReport.needsGL)
        XCTAssertEqual(r.explanation, "Distant Horizons " + GameExitReport.needsGL)
        XCTAssertTrue(r.nextStep.hasPrefix("Turn that mod off"))
        XCTAssertEqual(GameExitReport.metalGLModID(in: report.components(separatedBy: "\n")), "distanthorizons")
        XCTAssertNil(GameExitReport.metalGLModID(in: ["java.lang.ClassCastException: class a.B cannot be cast to class c.D"]))
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
