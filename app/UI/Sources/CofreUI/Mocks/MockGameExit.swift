import Foundation

/// Sample game exits for the preview host and tests: real-looking crash reports and log tails, diagnosed by the same
/// code as the app. Fixtures only.
public enum MockGameExit {
    public static let instance = "Survival+ · Fabric 1.21.1"

    private static let header = """
        ---- Minecraft Crash Report ----
        // Who set us up the TNT?

        Time: 2026-10-29 17:42:10
        """
    private static let system = """
        -- System Details --
        Details:
        	Minecraft Version: 1.21.1
        	Fabric Mods:
        		iris: Iris 1.8.1
        		sodium: Sodium 0.6.0
        	Loaded Shaderpack: ComplementaryReimagined_r5.3.zip
        """
    private static let playing = """
        [17:40:02] [Render thread/INFO]: Loaded shader pack ComplementaryReimagined_r5.3.zip
        [17:40:03] [Render thread/INFO]: Reloading ResourceManager: vanilla, fabric
        [17:40:08] [Server thread/INFO]: Preparing spawn area: 84%
        [17:41:30] [Render thread/INFO]: [System] [CHAT] Steve_42 joined the game
        """

    /// (code, crash report, log) per reason.
    public static func sample(_ reason: GameExitReport.Reason) -> (code: Int, crashReport: String?, log: String) {
        switch reason {
        case .memory:
            (
                -1,
                """
                \(header)
                Description: Unexpected error

                java.lang.OutOfMemoryError: Java heap space
                	at net.minecraft.class_1923.method_8324(class_1923.java:52)

                \(system)
                """,
                playing + "\n[17:42:09] [Render thread/ERROR]: Out of memory, stopping\n"
            )
        case .renderer:
            (
                -1, nil,
                playing
                    + """

                    [17:42:09] [Render thread/ERROR]: Shader composite2 failed to compile: 0:118: 'texelFetch' : no matching overloaded function found
                    [17:42:09] [Render thread/ERROR]: GLFW error 65543: No OpenGL context
                    """
            )
        case .missingLibrary:
            (
                1, nil,
                """
                [17:40:01] [main/INFO]: Loading Minecraft 26.3 with Java 21
                [17:40:02] [main/ERROR]: Exception in thread "main" java.lang.UnsatisfiedLinkError: Can't load library: /var/mobile/Containers/Data/Application/…/natives/libjnidispatch.dylib
                """
            )
        case .mods:
            (
                -1,
                """
                \(header)
                Description: Mod resolution failed

                net.fabricmc.loader.impl.FormattedException: Incompatible mods found!
                 - Mod 'Sodium Extra' (sodium-extra) 0.6.0 requires version 0.6.0-beta.2 or later of mod 'Sodium' (sodium), but only the wrong version is present: 0.5.11!

                \(system)
                """,
                playing
            )
        case .java:
            (
                -1,
                """
                \(header)
                Description: Ticking entity

                java.lang.NullPointerException: Cannot invoke "net.minecraft.class_1297.method_5864()" because "entity" is null
                	at com.example.pets.PetFollowGoal.tick(PetFollowGoal.java:88)

                \(system)
                """,
                playing
            )
        case .unknown:
            (11, nil, playing + "\n[17:42:09] [Air/ERROR]: Fatal signal 11 received\n")
        case .quit:
            (0, nil, playing + "\n[17:45:00] [Render thread/INFO]: Stopping!\n")
        }
    }

    public static func report(_ reason: GameExitReport.Reason) -> GameExitReport {
        let s = sample(reason)
        let dir = FileManager.default.temporaryDirectory
        let log = dir.appendingPathComponent("latestlog.txt")
        try? s.log.write(to: log, atomically: true, encoding: .utf8)
        var files = [log]
        if let crash = s.crashReport {
            let url = dir.appendingPathComponent("crash-2026-10-29_17.42.10-client.txt")
            try? crash.write(to: url, atomically: true, encoding: .utf8)
            files.append(url)
        }
        return GameExitReport(code: s.code, crashReport: s.crashReport, log: s.log, instance: instance, files: files)
    }
}
