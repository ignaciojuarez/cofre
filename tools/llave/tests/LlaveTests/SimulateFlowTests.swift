import XCTest
@testable import Llave

final class SimulateFlowTests: XCTestCase {
    func testSimulatePairingProducesValidFile() async throws {
        let binaryURL = DeviceWatcher.resolveBinary() ?? URL(fileURLWithPath: "/tmp/bin/llave-pair")
        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            throw XCTSkip("llave-pair binary not available for end-to-end simulate test")
        }

        let outDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outDir) }

        let outFile = outDir.appendingPathComponent("Simulated iPhone.mobiledevicepairing")

        let dev = Device(udid: "00008150-SIMULATED-DEV", name: "Simulated iPhone", version: "18.1")
        let pairingService = PairingService(binaryURL: binaryURL)

        var receivedEvents: [LlaveEvent] = []
        let stream = pairingService.pair(device: dev, outURL: outFile, simulate: true)

        for try await event in stream {
            receivedEvents.append(event)
        }

        XCTAssertTrue(receivedEvents.contains(.waitingForUnlock))
        XCTAssertTrue(receivedEvents.contains(.waitingForTrust))
        XCTAssertTrue(receivedEvents.contains(.paired))
        XCTAssertTrue(receivedEvents.contains(.wifiEnabled))
        XCTAssertTrue(receivedEvents.contains(.validated))

        XCTAssertTrue(FileManager.default.fileExists(atPath: outFile.path))

        // Check file permissions are 0600
        let attrs = try FileManager.default.attributesOfItem(atPath: outFile.path)
        let posixPerms = attrs[.posixPermissions] as? NSNumber
        XCTAssertEqual(posixPerms?.intValue, 0o600)

        // Parse plist and verify required keys
        let fileData = try Data(contentsOf: outFile)
        let plistObj = try PropertyListSerialization.propertyList(from: fileData, format: nil) as? [String: Any]
        XCTAssertNotNil(plistObj)

        guard let dict = plistObj else {
            XCTFail("Parsed plist was not a dictionary")
            return
        }

        XCTAssertNotNil(dict["DeviceCertificate"])
        XCTAssertNotNil(dict["HostCertificate"])
        XCTAssertNotNil(dict["HostPrivateKey"])
        XCTAssertNotNil(dict["RootCertificate"])
        XCTAssertNotNil(dict["RootPrivateKey"])
        XCTAssertNotNil(dict["SystemBUID"])
        XCTAssertNotNil(dict["HostID"])
        XCTAssertNotNil(dict["WiFiMACAddress"])
        XCTAssertNotNil(dict["UDID"])

        // RemotePairing keys
        XCTAssertNotNil(dict["public_key"])
        XCTAssertNotNil(dict["private_key"])
        XCTAssertNotNil(dict["identifier"])
    }
}
