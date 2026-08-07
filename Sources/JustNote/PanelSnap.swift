import AppKit

/// Magnetic-snap geometry for the floating panel: pure functions that pull a proposed size or origin
/// to a target when it lands within `threshold`, each component independently. Origin snapping can use
/// a wider release threshold to provide magnetic hysteresis. Kept free of window state so it is
/// unit-testable; the callers own the per-gesture "already snapped" tracking that drives haptics.
enum PanelSnap {
    /// Snap distance in points. Tight on purpose — the panel sticks only when the cursor is nearly on
    /// the target, and releases the moment it is pulled past.
    static let threshold: CGFloat = 12

    /// Once engaged, keep the panel stuck until it is pulled farther away than the engage distance.
    /// The gap prevents the panel from chattering when the pointer hovers around the snap boundary.
    static let releaseThreshold: CGFloat = 24

    /// Snap a proposed frame size toward `target`, width and height independently.
    static func snapSize(_ size: NSSize, to target: NSSize, threshold: CGFloat = threshold)
        -> (size: NSSize, snappedWidth: Bool, snappedHeight: Bool) {
        let width = snap(size.width, to: target.width, threshold: threshold, releaseThreshold: threshold, wasSnapped: false)
        let height = snap(size.height, to: target.height, threshold: threshold, releaseThreshold: threshold, wasSnapped: false)
        return (NSSize(width: width.value, height: height.value), width.snapped, height.snapped)
    }

    /// Snap a proposed origin so the window centers within `visible`, x and y independently. The
    /// centered origin places the window's midpoint on the visible frame's midpoint.
    static func snapOrigin(_ origin: NSPoint, windowSize: NSSize, in visible: NSRect,
                           threshold: CGFloat = threshold,
                           releaseThreshold: CGFloat = releaseThreshold,
                           snappedX: Bool = false,
                           snappedY: Bool = false)
        -> (origin: NSPoint, snappedX: Bool, snappedY: Bool) {
        let centeredX = visible.midX - windowSize.width / 2
        let centeredY = visible.midY - windowSize.height / 2
        let x = snap(origin.x, to: centeredX, threshold: threshold, releaseThreshold: releaseThreshold, wasSnapped: snappedX)
        let y = snap(origin.y, to: centeredY, threshold: threshold, releaseThreshold: releaseThreshold, wasSnapped: snappedY)
        return (NSPoint(x: x.value, y: y.value), x.snapped, y.snapped)
    }

    private static func snap(
        _ value: CGFloat,
        to target: CGFloat,
        threshold: CGFloat,
        releaseThreshold: CGFloat,
        wasSnapped: Bool
    )
        -> (value: CGFloat, snapped: Bool) {
        let distance = abs(value - target)
        let limit = wasSnapped ? releaseThreshold : threshold
        return distance <= limit ? (target, true) : (value, false)
    }

    /// Fire the system alignment haptic used for snap-to-guide feedback. A no-op on hardware without a
    /// Force Touch trackpad, so it needs no availability guard.
    static func performAlignmentHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
