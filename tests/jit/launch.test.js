// Run the production Swift launch method with device-free JIT and Air stand-ins.
const assert = require('node:assert/strict');
const {readFileSync, writeFileSync, mkdtempSync, rmSync} = require('node:fs');
const {execFileSync} = require('node:child_process');
const {tmpdir} = require('node:os');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const read = file => readFileSync(path.join(root, file), 'utf8');
// One member, from its signature line to its matching closing brace, so nearby methods can change freely.
function member(source, signature) {
    const start = source.indexOf(signature);
    assert(start >= 0 && source.indexOf(signature, start + 1) < 0, `expected one ${signature.trim()}`);
    let depth = 0;
    for (let i = source.indexOf('{', start); i < source.length; i++) {
        if (source[i] === '{') depth++;
        else if (source[i] === '}' && --depth === 0) return source.slice(source.lastIndexOf('\n', start) + 1, i + 1);
    }
    assert.fail(`unbalanced ${signature.trim()}`);
}
const backend = read('app/Glue/AirBridge/CofreBackendAdapter.swift');
const launch = [
    '        public func launch(instanceID: String, accountID: String?) ->',
    '        func launch(instanceID: String, accountID: String?, gameArguments: [String]) ->',
    '        public func cancelLaunch()',
    '        func ensureJIT()',
].map(signature => member(backend, signature)).join('\n');
const models = read('app/UI/Sources/CofreUI/Facade/Models.swift');
const progress = member(models, '    public struct LaunchProgress:');
const failure = read('app/UI/Sources/CofreKit/LaunchFailure.swift');
const jit = read('app/Glue/CofreJIT.swift');
const status = jit.slice(jit.indexOf('public enum CofreJITStatus:'), jit.indexOf('public final class CofreJIT:'));
const dir = mkdtempSync(path.join(tmpdir(), 'cofre-launch-test-'));
try {
    writeFileSync(path.join(dir, 'main.swift'), `
import Foundation
${progress}
${failure.replace('import Foundation', '')}
${status}
enum CofreLaunchEvent {
    case preparing, downloading, surfaceShown, firstFrame, failed, cancelled, exited
    case restartRequired, rendererUnsupported, downloadFailed
}
enum CofreBackendError: LocalizedError {
    case jit(String), unavailable(String)
    var errorDescription: String? { switch self { case .jit(let message), .unavailable(let message): return message } }
}
// Keeps launch bookkeeping out of the Mac's real defaults.
final class UserDefaults {
    static let standard = UserDefaults()
    func set(_ value: Any?, forKey key: String) {}
}
enum CofreBreadcrumb { static func log(_ event: String, details: String) {} }
enum CofreServersStore { enum Failure: Error { case gameRunning } }
enum Loader {
    case vanilla, forge, neoforge, unknown
    func isInstalled(in versionID: String, root: URL, minecraftVersion: String) -> Bool { true }
}
public enum JITStep { public enum Kind: String { case pairing, vpn, diskImage, debugger, region, detach } }
enum PreferenceKey {
    case setupJIT, launchStarted(String), optionsBefore(String)
    var rawValue: String {
        switch self {
        case .setupJIT: return "cofre.setup.jit"
        case .launchStarted(let id): return "cofre.launch.started.\\(id)"
        case .optionsBefore(let id): return "cofre.options.before.\\(id)"
        }
    }
}
struct Instance {
    let loader = Loader.vanilla, restartRequired = false
    let versionID = "1.21", gameVersion = "1.21", gameDirectory = URL(fileURLWithPath: "/test/instance")
}
struct InstanceStore { let root = URL(fileURLWithPath: "/test") }
struct ContentStore {
    enum Kind { case mods }
    init(gameDirectory: URL) {}
    func list(_ kind: Kind) throws -> [String] { [] }
}
enum FMLConfig { static func disableEarlyWindow(in directory: URL) throws {} }
@MainActor final class CofreJIT {
    static var result: CofreJITStatus = .enabled("debugger")
    static var enabled = false
    static var setsFlag = true
    static var calls = 0
    static var onEnable: (() async -> Void)?
    static func enable(pid: Int32, pairingURL: () -> URL) async -> CofreJITStatus {
        precondition(pid == getpid())
        precondition(pairingURL().lastPathComponent == "pairing.plist")
        calls += 1
        await onEnable?()
        await Task.yield()
        if result.isEnabled && setsFlag { enabled = true }
        return result
    }
}
@MainActor final class Air {
    var calls = 0
    var fails = false
    func hideCofreLaunchOverlay() {}
    func jvmUsedInProcess() -> Bool { false }
    func gameDirectory(forProfile profile: String) -> URL? { URL(fileURLWithPath: "/test/instance") }
    func launchProfile(_ profile: String, accountID: String?, gameArguments: [String],
                       progress: @escaping (CofreLaunchEvent, Double, String?) -> Void) {
        precondition(CofreJIT.enabled, "Air started before JIT")
        precondition(profile == "instance" && accountID == "account" && gameArguments.isEmpty)
        calls += 1
        progress(.preparing, 0, "Starting Minecraft")
        if fails { progress(.failed, 0, "Minecraft couldn't start. Check the launcher log.") }
        else {
            progress(.downloading, 0.4, "Game files")
            progress(.surfaceShown, 0, nil)
            progress(.firstFrame, 1, nil)
        }
    }
}
@MainActor final class Harness {
    let air = Air()
    var instances: InstanceStore? = InstanceStore()
    var launchingGameDirectory: URL?
    var loaderInstallInProgress = false
    var launchTask: Task<Void, Never>?
    var isJITEnabled: Bool { CofreJIT.enabled }
    let pairingURL = URL(fileURLWithPath: "/test/pairing.plist")
    func storedInstance(_ id: String) throws -> Instance { Instance() }
    func recordJVMUse() {}
    func repairLibraries() {}
    func applyJavaHeap(instanceID: String) {}
    func checkDiskBeforeLaunch(_ instance: Instance, root: URL) async throws {}
    enum SetupStatus { case ready }
    struct SetupState { var jit = SetupStatus.ready }
    var setup = SetupState()
    func publishSetup() {}
${launch}
}
@main struct Tests {
    @MainActor static func run(
        _ result: CofreJITStatus, alreadyEnabled: Bool = false, setsFlag: Bool = true,
        cancel: Bool = false, airFails: Bool = false, jitError: String? = nil, expectedError: String? = nil
    ) async {
        let backend = Harness()
        CofreJIT.result = result
        CofreJIT.enabled = alreadyEnabled
        CofreJIT.setsFlag = setsFlag
        CofreJIT.calls = 0
        CofreJIT.onEnable = cancel ? { await backend.cancelLaunch() } : nil
        backend.air.fails = airFails
        var rows: [LaunchProgress] = []
        var failure: Error?
        do {
            for try await p in backend.launch(instanceID: "instance", accountID: "account") { rows.append(p) }
        } catch { failure = error }
        precondition(CofreJIT.calls == (alreadyEnabled ? 0 : 1))
        precondition(alreadyEnabled || rows.first?.title == "JIT")
        if cancel {
            precondition(failure is CancellationError)
            precondition(backend.air.calls == 0)
        } else if let expectedError {
            precondition(failure?.localizedDescription == expectedError, "Unexpected error: \\(String(describing: failure))")
            precondition(backend.air.calls == (airFails ? 1 : 0))
            precondition(!rows.contains(where: { $0.finished }))
        } else {
            precondition(failure == nil && backend.air.calls == 1)
            precondition(rows.last?.finished == true && rows.last?.stage == 7 && rows.last?.of == 7)
        }
        CofreJIT.onEnable = nil
        // Launch reports every JIT failure as jitUnavailable; ensureJIT keeps the cause for the log.
        guard let jitError else { return }
        precondition(failure as? LaunchFailure == .jitUnavailable)
        CofreJIT.enabled = false
        do { try await Harness().ensureJIT(); preconditionFailure("ensureJIT succeeded") }
        catch { precondition(error.localizedDescription == jitError, "Unexpected JIT error: \\(error)") }
    }
    static func main() async {
        await run(.enabled("debugger"))
        await run(.failed("must not run"), alreadyEnabled: true)
        let jit = LaunchFailure.jitUnavailable.localizedDescription
        await run(.needsPairing, jitError: "This device isn't paired yet. Pair it in Settings.", expectedError: jit)
        await run(.needsVPN, jitError: "The VPN isn't on", expectedError: jit)
        await run(.failed("attach failed", step: .debugger), jitError: "JIT failed at debugger: attach failed", expectedError: jit)
        await run(.failed("VPN denied"), jitError: "VPN denied", expectedError: jit)
        await run(.unavailable, jitError: "JIT didn't turn on", expectedError: jit)
        await run(.enabling, jitError: "JIT didn't turn on", expectedError: jit)
        await run(.enabled("debugger"), setsFlag: false, jitError: "JIT didn't turn on", expectedError: jit)
        await run(.enabled("debugger"), cancel: true)
        await run(.enabled("debugger"), airFails: true,
                  expectedError: "Minecraft couldn't start. Check the launcher log.")
        print("Cofre launch: 11 checks passed")
    }
}
`);
    execFileSync('xcrun', ['swiftc', '-parse-as-library', path.join(dir, 'main.swift'), '-o', path.join(dir, 'launch-test')], {stdio: 'inherit'});
    execFileSync(path.join(dir, 'launch-test'), [], {stdio: 'inherit'});
} finally {
    rmSync(dir, {recursive: true, force: true});
}
