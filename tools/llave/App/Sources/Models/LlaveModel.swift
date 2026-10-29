import Foundation
import Combine

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

    public init(
        deviceWatcherFactory: @escaping (Bool) -> DeviceWatcherProtocol = { isSim in DeviceWatcher(isSimulating: isSim) },
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
        self.detectedDevices = devices

        // If currently in an active pairing or ready state with a valid device, preserve unless disconnected
        switch state {
        case .locked(let current), .waitingForTrust(let current), .pairing(let current):
            if !devices.contains(where: { $0.udid == current.udid }) {
                pairingTask?.cancel()
                cleanupTemporaryFile()
                transitionToDefaultDeviceState(devices)
            }
            return
        case .ready:
            // Device remains ready until user dismisses or device disconnects
            return
        default:
            transitionToDefaultDeviceState(devices)
        }
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
                self?.state = .error(error)
            } catch {
                self?.state = .error(LlaveError(code: "PAIRING_FAILED", message: error.localizedDescription))
            }
        }
    }

    public func handlePairingEvent(_ event: LlaveEvent, device: Device, outURL: URL) {
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
            if message.localizedCaseInsensitiveContains("not installed") { state = .cofreMissing(device) } else if code == "PAIRING_FAILED" && message.localizedCaseInsensitiveContains("placement") { state = .placementFailed(device, message) } else { state = .error(LlaveError(code: code, message: message)) }
        }
    }

    public func sendViaAirDrop() -> Bool {
        guard case .ready(let fileURL) = state else {
            return false
        }
        let success = airDropService.sendViaAirDrop(fileURL: fileURL)
        return success
    }

    public func saveToDesktop() -> URL? {
        guard case .ready(let fileURL) = state else {
            return nil
        }
        do {
            let saved = try airDropService.saveToDesktop(fileURL: fileURL)
            return saved
        } catch {
            state = .error(LlaveError(code: "SAVE_FAILED", message: error.localizedDescription))
            return nil
        }
    }

    public func reset() {
        pairingTask?.cancel()
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
        let sanitized = deviceName
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
