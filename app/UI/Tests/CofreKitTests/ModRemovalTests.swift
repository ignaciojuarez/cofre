import XCTest
@testable import CofreKit

final class ModRemovalTests: XCTestCase {
    private func node(
        _ id: String, _ dependencies: [String] = [], direct: Bool = false, protected: Bool = false
    ) -> InstalledModNode {
        InstalledModNode(
            id: id, name: id, aliases: [id], dependencies: dependencies.map { ModDependency(id: $0) },
            installedDirectly: direct, protectedFromRemoval: protected)
    }

    func testSharedDependencyStays() {
        let nodes = [node("a", ["shared"]), node("b", ["shared"]), node("shared")]
        XCTAssertTrue(ModRemovalPlanner.options(removing: "a", from: nodes).isEmpty)
    }

    func testExclusiveDependencyIsOffered() {
        let nodes = [node("a", ["library"]), node("library")]
        XCTAssertEqual(ModRemovalPlanner.options(removing: "a", from: nodes).map(\.id), ["library"])
    }

    func testExclusiveDependenciesRecurse() {
        let nodes = [node("a", ["b"]), node("b", ["c"]), node("c")]
        XCTAssertEqual(ModRemovalPlanner.options(removing: "a", from: nodes).map(\.id), ["b", "c"])
    }

    func testUncheckedParentKeepsItsDependency() {
        let nodes = [node("a", ["b"]), node("b", ["c"]), node("c")]
        XCTAssertTrue(ModRemovalPlanner.selected(removing: "a", candidates: ["c"], from: nodes).isEmpty)
        XCTAssertEqual(ModRemovalPlanner.selected(removing: "a", candidates: ["b"], from: nodes).map(\.id), ["b"])
    }

    func testKitModsAreProtected() {
        let nodes = [node("a", ["metal"]), node("metal", direct: false, protected: true)]
        XCTAssertTrue(ModRemovalPlanner.options(removing: "a", from: nodes).isEmpty)
    }

    func testDirectlyInstalledDependencyIsProtected() {
        let nodes = [node("a", ["library"]), node("library", direct: true)]
        XCTAssertTrue(ModRemovalPlanner.options(removing: "a", from: nodes).isEmpty)
    }
}
