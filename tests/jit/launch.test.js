// Run the production Swift launch method with device-free JIT and Air stand-ins.
const assert = require('node:assert/strict');
const {readFileSync, writeFileSync, mkdtempSync, rmSync} = require('node:fs');
const {execFileSync} = require('node:child_process');
const {tmpdir} = require('node:os');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const backend = readFileSync(path.join(root, 'app/Glue/AirBridge/CofreBackendAdapter.swift'), 'utf8');
const launch = backend.slice(backend.indexOf('        public func launch('), backend.indexOf('        public func logLines('));
assert(launch.includes('public func cancelLaunch()'));
const models = readFileSync(path.join(root, 'app/UI/Sources/CofreUI/Facade/Models.swift'), 'utf8');
const progress = models.slice(models.indexOf('    public struct LaunchProgress:'), models.indexOf('    public enum LogKind:'));
const jit = readFileSync(path.join(root, 'app/Glue/CofreJIT.swift'), 'utf8');
const status = jit.slice(jit.indexOf('public enum CofreJITStatus:'), jit.indexOf('public final class CofreJIT:'));
const dir = mkdtempSync(path.join(tmpdir(), 'cofre-launch-test-'));
try {
    writeFileSync(path.join(dir, 'main.swift'), `
import Foundation
${progress}
${status}
enum CofreLaunchEvent { case preparing, downloading, surfaceShown, firstFrame, failed, cancelled, exited }
enum CofreBackendError: LocalizedError {
    case jit(String), unavailable(String)
    var errorDescription: String? { switch self { case .jit(let message), .unavailable(let message): return message } }
}
enum RejoinIntent { enum Kind: String { case server }; }
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
    func setServerIp(_ address: String, forProfile profile: String) {}
    func launchProfile(_ profile: String, accountID: String?, progress: (CofreLaunchEvent, Double, String?) -> Void) {
        precondition(CofreJIT.enabled, "Air started before JIT")
        precondition(profile == "instance" && accountID == "account")
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
    var launchTask: Task<Void, Never>?
    var isJITEnabled: Bool { CofreJIT.enabled }
    let pairingURL = URL(fileURLWithPath: "/test/pairing.plist")
${launch}
}
@main struct Tests {
    @MainActor static func run(
        _ result: CofreJITStatus, alreadyEnabled: Bool = false, setsFlag: Bool = true,
        cancel: Bool = false, airFails: Bool = false, expectedError: String? = nil
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
    }
    static func main() async {
        await run(.enabled("debugger"))
        await run(.failed("must not run"), alreadyEnabled: true)
        await run(.needsPairing, expectedError: "This device isn't paired yet. Pair it in Settings.")
        await run(.needsVPN, expectedError: "The VPN isn't on")
        await run(.failed("attach failed", step: "debugger"), expectedError: "JIT failed at debugger: attach failed")
        await run(.failed("VPN denied"), expectedError: "VPN denied")
        await run(.unavailable, expectedError: "JIT didn't turn on")
        await run(.enabling, expectedError: "JIT didn't turn on")
        await run(.enabled("debugger"), setsFlag: false, expectedError: "JIT didn't turn on")
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
