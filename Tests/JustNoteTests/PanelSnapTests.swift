import XCTest
import AppKit
@testable import JustNote

final class PanelSnapTests: XCTestCase {
    private let target = NSSize(width: 660, height: 480)

    func testSnapSizePullsBothDimensionsWithinThreshold() {
        let result = PanelSnap.snapSize(NSSize(width: 654, height: 486), to: target)

        XCTAssertEqual(result.size, target)
        XCTAssertTrue(result.snappedWidth)
        XCTAssertTrue(result.snappedHeight)
    }

    func testSnapSizeReleasesEachDimensionIndependently() {
        // Width just inside the zone, height well outside it.
        let result = PanelSnap.snapSize(NSSize(width: 668, height: 600), to: target)

        XCTAssertEqual(result.size.width, 660)
        XCTAssertEqual(result.size.height, 600)
        XCTAssertTrue(result.snappedWidth)
        XCTAssertFalse(result.snappedHeight)
    }

    func testSnapSizeIncludesThresholdBoundary() {
        let low = PanelSnap.snapSize(NSSize(width: 660 - 12, height: 480), to: target)
        let high = PanelSnap.snapSize(NSSize(width: 660 + 12, height: 480), to: target)
        let past = PanelSnap.snapSize(NSSize(width: 660 + 13, height: 480), to: target)

        XCTAssertTrue(low.snappedWidth)
        XCTAssertTrue(high.snappedWidth)
        XCTAssertFalse(past.snappedWidth)
        XCTAssertEqual(past.size.width, 673)
    }

    func testSnapOriginCentersEachAxisWithinThreshold() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowSize = NSSize(width: 660, height: 480)
        // Centered origin is (390, 210); nudge both axes just inside the zone.
        let result = PanelSnap.snapOrigin(NSPoint(x: 396, y: 204), windowSize: windowSize, in: visible)

        XCTAssertEqual(result.origin.x, visible.midX - windowSize.width / 2)
        XCTAssertEqual(result.origin.y, visible.midY - windowSize.height / 2)
        XCTAssertTrue(result.snappedX)
        XCTAssertTrue(result.snappedY)
    }

    func testSnapOriginReleasesEachAxisIndependently() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowSize = NSSize(width: 660, height: 480)
        // x near center (390), y far from it.
        let result = PanelSnap.snapOrigin(NSPoint(x: 388, y: 700), windowSize: windowSize, in: visible)

        XCTAssertEqual(result.origin.x, 390)
        XCTAssertEqual(result.origin.y, 700)
        XCTAssertTrue(result.snappedX)
        XCTAssertFalse(result.snappedY)
    }

    func testSnapOriginRespectsVisibleFrameOffset() {
        // A secondary display whose visible frame does not start at the origin.
        let visible = NSRect(x: 1440, y: 0, width: 1280, height: 800)
        let windowSize = NSSize(width: 660, height: 480)
        let centeredX = visible.midX - windowSize.width / 2
        let result = PanelSnap.snapOrigin(NSPoint(x: centeredX + 5, y: 160), windowSize: windowSize, in: visible)

        XCTAssertEqual(result.origin.x, centeredX)
        XCTAssertTrue(result.snappedX)
    }
}
