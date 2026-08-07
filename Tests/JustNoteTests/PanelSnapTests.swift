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

    func testSnapOriginStaysEngagedWithinReleaseHysteresis() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowSize = NSSize(width: 660, height: 480)
        let centeredX = visible.midX - windowSize.width / 2

        let engaged = PanelSnap.snapOrigin(
            NSPoint(x: centeredX + 10, y: 100),
            windowSize: windowSize,
            in: visible
        )
        let held = PanelSnap.snapOrigin(
            NSPoint(x: centeredX + 20, y: 100),
            windowSize: windowSize,
            in: visible,
            snappedX: engaged.snappedX
        )

        XCTAssertTrue(engaged.snappedX)
        XCTAssertTrue(held.snappedX)
        XCTAssertEqual(held.origin.x, centeredX)
    }

    func testSnapOriginReleasesAfterHysteresisAndCanReengage() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowSize = NSSize(width: 660, height: 480)
        let centeredX = visible.midX - windowSize.width / 2

        let released = PanelSnap.snapOrigin(
            NSPoint(x: centeredX + PanelSnap.releaseThreshold + 1, y: 100),
            windowSize: windowSize,
            in: visible,
            snappedX: true
        )
        let reengaged = PanelSnap.snapOrigin(
            NSPoint(x: centeredX + PanelSnap.threshold, y: 100),
            windowSize: windowSize,
            in: visible
        )

        XCTAssertFalse(released.snappedX)
        XCTAssertEqual(released.origin.x, centeredX + PanelSnap.releaseThreshold + 1)
        XCTAssertTrue(reengaged.snappedX)
        XCTAssertEqual(reengaged.origin.x, centeredX)
    }

    @MainActor
    func testPanelDragHandlePassesThroughControls() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        let button = NSButton(frame: NSRect(x: 20, y: 8, width: 28, height: 24))
        let accessibilityButton = RoleOnlyButtonView(frame: NSRect(x: 80, y: 8, width: 28, height: 24))
        content.addSubview(button)
        content.addSubview(accessibilityButton)

        let handle = PanelDragHandle(frame: content.bounds)
        handle.passThroughEvents(to: content)

        XCTAssertNil(handle.hitTest(NSPoint(x: 34, y: 20)))
        XCTAssertNil(handle.hitTest(NSPoint(x: 94, y: 20)))
        XCTAssertTrue(handle.hitTest(NSPoint(x: 150, y: 20)) === handle)
    }

    @MainActor
    func testPanelDragHandlePassesThroughAccessibilityOnlyControls() {
        let content = AccessibilityHitTestView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        let handle = PanelDragHandle(frame: content.bounds)
        handle.passThroughEvents(to: content)

        XCTAssertNil(handle.hitTest(NSPoint(x: 34, y: 20)))
        XCTAssertTrue(handle.hitTest(NSPoint(x: 150, y: 20)) === handle)
    }

    @MainActor
    func testPanelDragHandleReportsOnlyAnActiveGesture() throws {
        let handle = PanelDragHandle(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        var began = 0
        var moved = 0
        var ended = 0
        handle.onDragBegan = { began += 1 }
        handle.onDrag = { moved += 1 }
        handle.onDragEnded = { ended += 1 }

        let down = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        let dragged = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: NSPoint(x: 20, y: 10),
            modifierFlags: [],
            timestamp: 0.1,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        let up = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: NSPoint(x: 20, y: 10),
            modifierFlags: [],
            timestamp: 0.2,
            windowNumber: 0,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 1
        ))

        handle.mouseDragged(with: dragged)
        handle.mouseDown(with: down)
        handle.mouseDragged(with: dragged)
        handle.mouseUp(with: up)
        handle.mouseDragged(with: dragged)

        XCTAssertEqual(began, 1)
        XCTAssertEqual(moved, 1)
        XCTAssertEqual(ended, 1)
    }
}

private final class RoleOnlyButtonView: NSView {
    override func accessibilityRole() -> NSAccessibility.Role? {
        NSAccessibility.Role(rawValue: "AXButton")
    }
}

private final class AccessibilityHitTestView: NSView {
    private let button = RoleOnlyButtonView(frame: NSRect(x: 20, y: 8, width: 28, height: 24))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(button)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        point.x >= button.frame.minX && point.x <= button.frame.maxX &&
            point.y >= button.frame.minY && point.y <= button.frame.maxY ? button : self
    }
}
