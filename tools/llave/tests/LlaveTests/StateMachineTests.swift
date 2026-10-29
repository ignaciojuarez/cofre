import XCTest
@testable import Llave

final class MockDeviceWatcher: DeviceWatcherProtocol, @unchecked Sendable {
    private var continuation: AsyncStream<[Device]>.Continuation?
    public let devicesStream: AsyncStream<[Device]>
    private(set) var currentDevices: [Device] = []

    init() {
        var cont: AsyncStream<[Device]>.Continuation?
        self.devicesStream = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    func start() {}
    func stop() {}
    func refresh() async -> [Device] { currentDevices }
    func emit(_ devices: [Device]) {
        currentDevices = devices
        continuation?.yield(devices)
    }
}

final class MockPairingService: PairingServiceProtocol, @unchecked Sendable {
    var eventsToYield: [LlaveEvent] = []
    var errorToThrow: Error?

    func pair(device: Device, outURL: URL, simulate: Bool) -> AsyncThrowingStream<LlaveEvent, Error> {
        AsyncThrowingStream { cont in
            for event in self.eventsToYield {
                cont.yield(event)
            }
            if let error = self.errorToThrow {
                cont.finish(throwing: error)
            } else {
                cont.finish()
            }
        }
    }
}

final class MockAirDropService: AirDropServiceProtocol, @unchecked Sendable {
    var airDropCalledWithURL: URL?
    var desktopSavedURL: URL?

    @MainActor
    func sendViaAirDrop(fileURL: URL) -> Bool {
        airDropCalledWithURL = fileURL
        return true
    }

    @MainActor
    func saveToDesktop(fileURL: URL) throws -> URL {
        desktopSavedURL = fileURL
        return fileURL
    }
}

@MainActor
final class StateMachineTests: XCTestCase {
    func testDeviceTransitions() async {
        let mockWatcher = MockDeviceWatcher()
        let model = LlaveModel(
            deviceWatcherFactory: { _ in mockWatcher },
            pairingService: MockPairingService(),
            airDropService: MockAirDropService()
        )

        XCTAssertEqual(model.state, .noDevice)

        // Multiple devices
        let dev1 = Device(udid: "UDID1", name: "iPhone 15", version: "18.0")
        let dev2 = Device(udid: "UDID2", name: "iPhone 16", version: "18.1")
        model.handleDevicesUpdated([dev1, dev2])
        XCTAssertEqual(model.state, .multipleDevices([dev1, dev2]))

        // Single device triggers pairing
        model.handleDevicesUpdated([dev1])
        XCTAssertEqual(model.state, .pairing(dev1))

        // Disconnect
        model.handleDevicesUpdated([])
        XCTAssertEqual(model.state, .noDevice)
    }

    func testPairingEventsTransition() async {
        let model = LlaveModel(
            deviceWatcherFactory: { _ in MockDeviceWatcher() },
            pairingService: MockPairingService(),
            airDropService: MockAirDropService()
        )

        let dev = Device(udid: "UDID-TEST", name: "Test iPhone", version: "18.0")
        let tempURL = URL(fileURLWithPath: "/tmp/test.mobiledevicepairing")

        model.handlePairingEvent(.waitingForUnlock, device: dev, outURL: tempURL)
        XCTAssertEqual(model.state, .locked(dev))

        model.handlePairingEvent(.waitingForTrust, device: dev, outURL: tempURL)
        XCTAssertEqual(model.state, .waitingForTrust(dev))

        model.handlePairingEvent(.paired, device: dev, outURL: tempURL)
        XCTAssertEqual(model.state, .pairing(dev))

        model.handlePairingEvent(.wifiEnabled, device: dev, outURL: tempURL)
        XCTAssertEqual(model.state, .pairing(dev))

        model.handlePairingEvent(.validated, device: dev, outURL: tempURL)
        XCTAssertEqual(model.state, .placing(dev))

        model.handlePairingEvent(.placed, device: dev, outURL: tempURL)
        XCTAssertEqual(model.state, .done(dev))

        model.handlePairingEvent(.error(code: "TEST_ERR", message: "Failed"), device: dev, outURL: tempURL)
        XCTAssertEqual(model.state, .error(LlaveError(code: "TEST_ERR", message: "Failed")))
    }
}
