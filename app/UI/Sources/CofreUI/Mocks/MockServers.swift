#if canImport(UIKit)
    import Foundation

    /// Server sample data (plan/servers.md): each instance's servers.dat, ping replies and Modrinth's list.
    /// Names and addresses are made up. For previews, tests and the preview host only.
    enum MockServers {
        static let modern = ["1.21.4", "1.21.3", "1.21.1", "1.21", "1.20.6", "1.20.4", "1.20.1", "1.19.4", "1.8.9"]

        /// servers.dat per instance: what Minecraft stores (name, ip, acceptTextures). Ping fills the rest.
        static func saved() -> [String: [ServerSummary]] {
            func s(_ id: String, _ name: String, _ address: String, _ inst: String, card: Bool = false)
                -> ServerSummary
            { ServerSummary(id: id, name: name, address: address, hasServerCard: card, instanceID: inst) }
            return [
                "survival": [
                    s("sv-ironwood", "Ironwood SMP", MockServerJoin.ironwood.address, "survival", card: true),
                    s("sv-lan", "Friends' world", "10.0.0.4:25565", "survival"),
                    s("sv-emberfall", "Emberfall Network", "play.emberfall.net", "survival"),
                    s("sv-oakridge", "Oakridge Towny", "play.oakridge.gg", "survival"),
                    s("sv-factions", "Old Factions", "factions.example.net", "survival"),
                ],
                "create": [s("cr-brass", "Brass & Gears", "play.brassgears.net", "create")],
                "cobblemon": [s("cb-valley", "Cobble Valley", "mc.cobblevalley.net", "cobblemon")],
                "skyblock": [s("sk-skyforge", "Skyforge Skyblock", "sky.skyforge.io", "skyblock")],
            ]
        }

        /// Ping replies by address. Missing means it can't be reached.
        static let pings: [String: ServerPing] = [
            MockServerJoin.ironwood.address: ServerPing(
                motd: "Create, trains and farms · whitelist on", online: 12, max: 40, versionName: "Fabric 1.21.1",
                protocolVersion: 767, gameVersions: ["1.21.1"], latencyMS: 38),
            "10.0.0.4:25565": ServerPing(
                motd: "Steve_42's world", online: 3, max: 8, versionName: "1.21.1", protocolVersion: 767,
                gameVersions: ["1.21.1"], latencyMS: 6),
            "play.emberfall.net": ServerPing(
                motd: "BedWars · SkyWars · Parkour  [1.8–1.21]", online: 18_204, max: 50_000,
                versionName: "Velocity 1.8.x-1.21.x", protocolVersion: 767, gameVersions: modern, latencyMS: 92),
            "play.oakridge.gg": ServerPing(
                motd: "§aTowny§r · Economy · Season 4", online: 64, max: 200, versionName: "Paper 1.20.4",
                protocolVersion: 765, gameVersions: ["1.20.4"], latencyMS: 71),
            "play.brassgears.net": ServerPing(
                motd: "Create 0.5 · trains everywhere", online: 9, max: 30, versionName: "Forge 1.20.1",
                protocolVersion: 763, gameVersions: ["1.20.1"], latencyMS: 120),
            "mc.cobblevalley.net": ServerPing(
                motd: "Catch them on NeoForge 1.21.1", online: 140, max: 300, versionName: "NeoForge 1.21.1",
                protocolVersion: 767, gameVersions: ["1.21.1"], latencyMS: 210),
            "sky.skyforge.io": ServerPing(
                motd: "Islands, minions and auctions", online: 830, max: 2000, versionName: "Paper 1.21.4",
                protocolVersion: 769, gameVersions: ["1.21.4", "1.21.1", "1.20.4"], latencyMS: 64),
            "mc.pixelisles.org": ServerPing(
                motd: "Island hopping survival · season 6", online: 211, max: 500, versionName: "Paper 1.21.4",
                protocolVersion: 769, gameVersions: ["1.21.4"], latencyMS: 88),
        ]

        /// Modrinth's server list, most popular first. Emberfall and Ironwood are saved in Survival+ too.
        static let recommended: [ServerSummary] = [
            d(
                "emberfall", "Emberfall Network", "play.emberfall.net",
                "BedWars, SkyWars and parkour for every version",
                18_204, 50_000, modern),
            d(
                "blockheads", "Blockheads PvP", "pvp.blockheads.gg", "Practice, duels and kit PvP", 1_920, 5000,
                ["1.21.1", "1.20.4", "1.8.9"]),
            d(
                "skyforge", "Skyforge Skyblock", "sky.skyforge.io", "Islands, minions and auctions", 830, 2000,
                ["1.21.4", "1.21.1", "1.20.4"]),
            d("lumen", "Lumen SMP", "lumen.example.org", "Vanilla+ survival with land claims", 342, 1000, ["1.21.1"]),
            d(
                "pixelisles", "Pixel Isles", "mc.pixelisles.org", "Island hopping survival, season 6", 211, 500,
                ["1.21.4"]),
            d(
                "cobblevalley", "Cobble Valley", "mc.cobblevalley.net", "Cobblemon on NeoForge, modpack on Modrinth",
                140, 300, ["1.21.1"]),
            d(
                "oakridge", "Oakridge Towny", "play.oakridge.gg", "Towns, nations and a real economy", 64, 200,
                ["1.20.4"]),
            d(
                "ironwood", "Ironwood SMP", MockServerJoin.ironwood.address,
                "A cozy Create SMP. Cofre installs the mods",
                12, 40, ["1.21.1"], card: true),
            d("hearth", "Hearthstone Valley", "hearth.example.net", "Farming and cozy towns", 96, 250, modern),
            d(
                "redstone", "Redstone Academy", "learn.redstone.example", "Redstone lessons and contraption contests",
                58, 150, ["1.21.1", "1.21"]),
            d(
                "frontier", "Frontier Wilds", "wilds.example.org", "Hardcore survival with a shrinking border",
                41, 100, ["1.21.1"]),
            d(
                "aurora", "Aurora Builds", "build.aurora.example", "Creative plots and monthly build contests",
                33, 120, ["1.21.1", "1.20.4"]),
        ]

        private static func d(
            _ id: String, _ name: String, _ address: String, _ motd: String, _ online: Int, _ max: Int,
            _ versions: [String], card: Bool = false
        ) -> ServerSummary {
            ServerSummary(
                id: "mr-\(id)", name: name, address: address, hasServerCard: card, motd: motd, playersOnline: online,
                playersMax: max, gameVersions: versions)
        }
    }
#endif
