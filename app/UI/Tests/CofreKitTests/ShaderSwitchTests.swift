import XCTest
@testable import CofreKit

final class ShaderSwitchTests: XCTestCase {
    func testTurnsShadersOffOnlyAfterAShaderCrash() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = dir.appendingPathComponent("config")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try "shaderPack=BSL.zip\nenableShaders=true\n".write(to: config.appendingPathComponent("iris.properties"), atomically: true, encoding: .utf8)
        XCTAssertTrue(ShaderSwitch.isOn(in: dir))
        XCTAssertTrue(ShaderSwitch.causedCrash("at net.irisshaders.iris.Iris.reload", gameDirectory: dir))
        XCTAssertFalse(ShaderSwitch.causedCrash("java.lang.OutOfMemoryError", gameDirectory: dir))
        try ShaderSwitch.turnOff(in: dir)
        XCTAssertFalse(ShaderSwitch.isOn(in: dir))
        let text = try String(contentsOf: config.appendingPathComponent("iris.properties"), encoding: .utf8)
        XCTAssertTrue(text.contains("shaderPack=BSL.zip"), "other settings stay")
    }
}
