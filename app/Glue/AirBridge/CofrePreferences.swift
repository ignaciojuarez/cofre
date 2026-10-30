import Foundation
import CofreUI

/// Typed owner for the preferences exposed by CofreUI.
///
/// The backing closures are the only Air seam. Keys, defaults, NSNumber
/// conversion, profile fallback, and Air's memory calculation stay here.
public struct CofrePreferenceStore {
    public enum Key: String, CaseIterable {
        case autoRAM = "java.auto_ram"
        case ramAllocation = "java.allocated_memory"
        case ramCeiling = "java.ram_ceiling"
        case renderer = "video.renderer"
        case resolution = "video.resolution"
        case fsrMode = "mobileglues.fsr1_setting"
        case graphicsAPI = "video.graphics_api"
        case java = "java.java_version"
        case javaArgs = "java.java_args"
        case fpsOverlay = "video.performance_hud"
        case muteWithSwitch = "video.silence_with_switch"
        case microphone = "video.allow_microphone"
        case gyroAim = "control.gyroscope_enable"
        case virtualMouse = "control.virtmouse_enable"
        case hotbarSwipe = "control.gesture_hotbar"
        case touchControllerMod = "control.mod_touch_enable"
        case buttonScale = "control.button_scale"
        case controllerLayout = "control.default_gamepad_ctrl"
        case touchLayout = "control.default_ctrl"
        case downloadSource = "general.download_source"
        case verifyFiles = "general.check_sha"
        case envVariables = "java.env_variables"
        case shaderCacheMB = "mobileglues.max_glsl_cache_size"
        case multidraw = "mobileglues.multidraw_mode"
        case computeShaders = "mobileglues.enable_ext_compute_shader"

        /// PLProfiles only isolates these fields. All other fields are global
        /// Air preferences, even when the settings screen is opened per instance.
        public var profileField: String? {
            switch self {
            case .renderer: return "renderer"
            case .graphicsAPI: return "graphicsApi"
            case .java: return "javaVersion"
            case .javaArgs: return "javaArgs"
            case .ramAllocation: return "allocatedMemory"
            default: return nil
            }
        }
    }

    public typealias Read = (_ key: String, _ profile: String?) -> Any?
    public typealias Write = (_ key: String, _ value: Any, _ profile: String?) -> Void

    private let read: Read
    private let write: Write

    public init(read: @escaping Read, write: @escaping Write) {
        self.read = read
        self.write = write
    }

    public func load(instanceID: String?) -> GamePreferences {
        var p = GamePreferences()
        p.autoRAM = bool(.autoRAM, instanceID, default: p.autoRAM)
        p.ramMB = p.autoRAM
            ? integer(.ramCeiling, instanceID, default: p.ramMB)
            : integer(.ramAllocation, instanceID, default: p.ramMB)
        p.deviceRAMMB = Int(ProcessInfo.processInfo.physicalMemory / 1_048_576)
        p.renderer = string(.renderer, instanceID, default: p.renderer)
        p.resolution = double(.resolution, instanceID, default: p.resolution * 100) / 100
        let fsr = integer(.fsrMode, instanceID, default: 0)
        p.fsrMode = [.off, .ultra, .quality, .performance][safe: fsr] ?? .off
        p.fsr = p.fsrMode != .off
        p.graphicsApi = string(.graphicsAPI, instanceID, default: p.graphicsApi)
        p.java = string(.java, instanceID, default: p.java)
        p.jvmArgs = string(.javaArgs, instanceID, default: p.jvmArgs)
        p.fpsOverlay = bool(.fpsOverlay, instanceID, default: p.fpsOverlay)
        p.muteWithSwitch = bool(.muteWithSwitch, instanceID, default: p.muteWithSwitch)
        p.microphone = bool(.microphone, instanceID, default: p.microphone)
        p.gyroAim = bool(.gyroAim, instanceID, default: p.gyroAim)
        p.virtualMouse = bool(.virtualMouse, instanceID, default: p.virtualMouse)
        p.hotbarSwipe = bool(.hotbarSwipe, instanceID, default: p.hotbarSwipe)
        p.touchControllerMod = bool(.touchControllerMod, instanceID, default: p.touchControllerMod)
        p.buttonScale = double(.buttonScale, instanceID, default: p.buttonScale * 100) / 100
        p.controllerLayout = string(.controllerLayout, instanceID, default: p.controllerLayout)
        p.touchLayout = string(.touchLayout, instanceID, default: p.touchLayout)
        p.downloadSource = string(.downloadSource, instanceID, default: "bmclapi") == "official" ? .official : .mirror
        p.verifyFiles = bool(.verifyFiles, instanceID, default: p.verifyFiles)
        p.envVariables = Self.parseEnv(string(.envVariables, instanceID, default: ""))
        p.shaderCacheMB = integer(.shaderCacheMB, instanceID, default: 128)
        let multidraw = integer(.multidraw, instanceID, default: 0)
        p.multidraw = multidraw == 0 ? "Auto" : String(multidraw)
        p.computeShaders = bool(.computeShaders, instanceID, default: false)
        return p
    }

    public func save(_ p: GamePreferences, instanceID: String?) {
        put(.autoRAM, p.autoRAM, instanceID)
        if !p.autoRAM { put(.ramAllocation, p.ramMB, instanceID) }
        put(.renderer, p.renderer, instanceID)
        put(.resolution, p.resolution * 100, instanceID)
        put(.fsrMode, ["off": 0, "ultra": 1, "quality": 2, "performance": 3][p.fsrMode.rawValue] ?? 0, instanceID)
        put(.graphicsAPI, p.graphicsApi == "auto" ? "" : p.graphicsApi, instanceID)
        put(.java, p.java, instanceID)
        put(.javaArgs, p.jvmArgs, instanceID)
        put(.fpsOverlay, p.fpsOverlay, instanceID)
        put(.muteWithSwitch, p.muteWithSwitch, instanceID)
        put(.microphone, p.microphone, instanceID)
        put(.gyroAim, p.gyroAim, instanceID)
        put(.virtualMouse, p.virtualMouse, instanceID)
        put(.hotbarSwipe, p.hotbarSwipe, instanceID)
        put(.touchControllerMod, p.touchControllerMod, instanceID)
        put(.buttonScale, p.buttonScale * 100, instanceID)
        put(.controllerLayout, p.controllerLayout, instanceID)
        put(.touchLayout, p.touchLayout, instanceID)
        put(.downloadSource, p.downloadSource == .official ? "official" : "bmclapi", instanceID)
        put(.verifyFiles, p.verifyFiles, instanceID)
        put(.envVariables, p.envVariables.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "), nil)
        put(.shaderCacheMB, p.shaderCacheMB, nil)
        put(.multidraw, p.multidraw == "Auto" ? 0 : (Int(p.multidraw) ?? 0), nil)
        put(.computeShaders, p.computeShaders, nil)
    }

    public func stringValue(_ key: Key, profile: String?) -> String? { object(key, profile) as? String }

    private func put(_ key: Key, _ value: Any, _ profile: String?) { write(key.rawValue, value, key.profileField == nil ? nil : profile) }
    private func object(_ key: Key, _ profile: String?) -> Any? { read(key.rawValue, key.profileField == nil ? nil : profile) }
    private func string(_ key: Key, _ profile: String?, default value: String) -> String { object(key, profile) as? String ?? value }
    private func integer(_ key: Key, _ profile: String?, default value: Int) -> Int {
        if let value = object(key, profile) as? Int { return value }
        if let value = object(key, profile) as? NSNumber { return value.intValue }
        return value
    }
    private func double(_ key: Key, _ profile: String?, default value: Double) -> Double {
        if let value = object(key, profile) as? Double { return value }
        if let value = object(key, profile) as? NSNumber { return value.doubleValue }
        return value
    }
    private func bool(_ key: Key, _ profile: String?, default value: Bool) -> Bool {
        if let value = object(key, profile) as? Bool { return value }
        if let value = object(key, profile) as? NSNumber { return value.boolValue }
        return value
    }
    private static func parseEnv(_ value: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: value.split(separator: " ").compactMap { part in
            let pair = part.split(separator: "=", maxSplits: 1)
            return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
        })
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
