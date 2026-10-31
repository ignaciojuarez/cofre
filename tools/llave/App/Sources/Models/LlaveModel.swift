import Combine
import Foundation

@MainActor
public final class LlaveModel: ObservableObject {
    @Published public private(set) var state: LlaveState = .noDevice
    @Published public private(set) var detectedDevices: [Device] = []
    @Published public var isSimulating: Bool = false {
        didSet {
            restartWatcher()
        }
    }

    private let deviceWatcherFactory: (Bool) -> DeviceWatcherProtocol
    private let pairingService: PairingServiceProtocol
    private let airDropService: AirDropServiceProtocol

    private var deviceWatcher: DeviceWatcherProtocol?
    private var watcherTask: Task<Void, Never>?
    private var pairingTask: Task<Void, Never>?
    private var temporaryFileURL: URL?
    private var pairingDeviceUDID: String?

    public init(
        deviceWatcherFactory: @escaping (Bool) -> DeviceWatcherProtocol = { isSim in DeviceWatcher(isSimulating: isSim)
        },
        pairingService: PairingServiceProtocol = PairingService(),
        airDropService: AirDropServiceProtocol = AirDropService(),
        isSimulating: Bool = false
    ) {
        self.deviceWatcherFactory = deviceWatcherFactory
        self.pairingService = pairingService
        self.airDropService = airDropService
        self.isSimulating = isSimulating
        restartWatcher()
    }

    public func restartWatcher() {
        deviceWatcher?.stop()
        watcherTask?.cancel()

        let watcher = deviceWatcherFactory(isSimulating)
        self.deviceWatcher = watcher
        watcher.start()

        watcherTask = Task { [weak self] in
            for await devices in watcher.devicesStream {
                guard let self = self else { break }
                self.handleDevicesUpdated(devices)
            }
        }
    }

    public func handleDevicesUpdated(_ devices: [Device]) {
        detectedDevices = devices
        guard let selectedUDID = pairingDeviceUDID else {
            // Only the initial waiting state may auto-start pairing.
            if case .noDevice = state {
                transitionToDefaultDeviceState(devices)
            } else if case .multipleDevices = state {
                transitionToDefaultDeviceState(devices)
            }
            return
        }
        guard devices.contains(where: { $0.udid == selectedUDID }) else {
            pairingTask?.cancel()
            pairingDeviceUDID = nil
            cleanupTemporaryFile()
            state = devices.isEmpty ? .noDevice : .multipleDevices(devices)
            return
        }
        // DeviceWatcher ticks are intentionally ignored while pairing, placing,
        // done, error, or export states are on screen.
    }

    private func transitionToDefaultDeviceState(_ devices: [Device]) {
        if devices.isEmpty {
            state = .noDevice
        } else if devices.count > 1 {
            state = .multipleDevices(devices)
        } else if let single = devices.first {
            // Automatically start pairing single device
            startPairing(device: single)
        }
    }

    public func startPairing(device: Device) {
        pairingTask?.cancel()
        cleanupTemporaryFile()

        pairingDeviceUDID = device.udid
        state = .pairing(device)

        let outURL = makeTemporaryPairingURL(deviceName: device.name)
        self.temporaryFileURL = outURL

        pairingTask = Task { [weak self, pairingService, isSimulating] in
            do {
                let stream = pairingService.pair(device: device, outURL: outURL, simulate: isSimulating)
                for try await event in stream {
                    guard let self = self else { break }
                    self.handlePairingEvent(event, device: device, outURL: outURL)
                }
            } catch let error as LlaveError {
                if !Task.isCancelled { self?.state = .error(error) }
            } catch {
                if !Task.isCancelled {
                    self?.state = .error(LlaveError(code: "PAIRING_FAILED", message: error.localizedDescription))
                }
            }
        }
    }

    public func handlePairingEvent(_ event: LlaveEvent, device: Device, outURL: URL) {
        temporaryFileURL = outURL
        switch event {
        case .waitingForUnlock:
            state = .locked(device)
        case .waitingForTrust:
            state = .waitingForTrust(device)
        case .paired, .wifiEnabled, .remotePairingWarning:
            state = .pairing(device)
        case .wifiFailed(let code, let message):
            state = .error(LlaveError(code: code, message: message))
        case .placed:
            state = .done(device)
        case .validated:
            state = .placing(device)
        case .error(let code, let message):
            if code == "COFRE_MISSING" {
                state = .cofreMissing(device)
            } else if code == "PLACE_FAILED" {
                state = .placementFailed(device, message)
            } else {
                state = .error(LlaveError(code: code, message: message))
            }
        }
    }

    private var exportFileURL: URL? {
        if case .ready(let url) = state { return url }
        if case .placementFailed = state { return temporaryFileURL }
        return nil
    }

    public func sendViaAirDrop() -> Bool {
        guard let fileURL = exportFileURL else { return false }
        let success = airDropService.sendViaAirDrop(fileURL: fileURL)
        if success { cleanupTemporaryFile() }
        return success
    }

    public func saveToDesktop() -> URL? {
        guard let fileURL = exportFileURL else { return nil }
        do {
            let saved = try airDropService.saveToDesktop(fileURL: fileURL)
            cleanupTemporaryFile()
            return saved
        } catch {
            state = .error(LlaveError(code: "SAVE_FAILED", message: error.localizedDescription))
            return nil
        }
    }

    public func reset() {
        pairingTask?.cancel()
        pairingDeviceUDID = nil
        cleanupTemporaryFile()
        transitionToDefaultDeviceState(detectedDevices)
    }

    public func cleanupTemporaryFile() {
        if let url = temporaryFileURL {
            try? FileManager.default.removeItem(at: url)
            temporaryFileURL = nil
        }
    }

    private func makeTemporaryPairingURL(deviceName: String) -> URL {
        let sanitized =
            deviceName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let cleanName = sanitized.isEmpty ? "iPhone" : sanitized
        let fileName = "\(cleanName).mobiledevicepairing"

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LlavePairing-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir.appendingPathComponent(fileName)
    }
}
