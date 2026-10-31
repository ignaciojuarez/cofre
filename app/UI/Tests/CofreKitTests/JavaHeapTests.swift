import XCTest

@testable import CofreKit

final class JavaHeapTests: XCTestCase {
    func testAutoFollowsWorkloadAndHalfTheDevice() {
        XCTAssertEqual(JavaHeap.autoMB(loader: .vanilla, modCount: 0, physicalMB: 12_288), 2048)
        XCTAssertEqual(JavaHeap.autoMB(loader: .fabric, modCount: 12, physicalMB: 12_288), 3072)
        XCTAssertEqual(JavaHeap.autoMB(loader: .neoforge, modCount: 150, physicalMB: 12_288), 6144)
        XCTAssertEqual(JavaHeap.autoMB(loader: .neoforge, modCount: 150, physicalMB: 3_900), 1950)
    }

    func testClampUsesCurrentHeadroom() {
        // iPad mini: about 2.7 GB available to the process; reserve 1.5 GB for native graphics memory.
        XCTAssertEqual(JavaHeap.clamp(1950, availableMB: 2_750), 896)
        XCTAssertEqual(JavaHeap.clamp(4096, availableMB: 2_750), 896)
        XCTAssertEqual(JavaHeap.clamp(2048, availableMB: 8_000), 2048)
        XCTAssertEqual(JavaHeap.clamp(2048, availableMB: 0), 2048)
    }

    func testLargeDeviceAutoSizesStayUnchanged() {
        let vanilla = JavaHeap.autoMB(loader: .vanilla, modCount: 0, physicalMB: 12_288)
        let fabric = JavaHeap.autoMB(loader: .fabric, modCount: 12, physicalMB: 12_288)
        let neoforge = JavaHeap.autoMB(loader: .neoforge, modCount: 0, physicalMB: 12_288)
        XCTAssertEqual(JavaHeap.clamp(vanilla, availableMB: 6_000), 2048)
        XCTAssertEqual(JavaHeap.clamp(fabric, availableMB: 6_000), 3072)
        XCTAssertEqual(JavaHeap.clamp(neoforge, availableMB: 6_000), 4096)
    }

    func testExhaustedHeadroomNeverInflates() {
        XCTAssertEqual(JavaHeap.clamp(4096, availableMB: 1_000), JavaHeap.minimumMB)
    }
}
