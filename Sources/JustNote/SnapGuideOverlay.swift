import AppKit

/// A transparent, click-through overlay that draws center alignment guides while the panel is being
/// dragged. It lives in its own borderless window so updating it never moves — or fights — the panel
/// being dragged; the panel commits to center only on release. A vertical guide marks the screen's
/// horizontal center (shown while the x-axis is within the snap threshold), a horizontal guide the
/// vertical center.
@MainActor
final class SnapGuideOverlay {
    private let window: NSPanel
    private let guideView = GuideView()

    init() {
        window = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        window.isFloatingPanel = true
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = guideView
    }

    /// Show the guides for the axes currently in the snap zone over `visibleFrame`, or hide entirely
    /// when neither axis is snapping.
    func update(visibleFrame: NSRect, showVertical: Bool, showHorizontal: Bool) {
        guard showVertical || showHorizontal else {
            hide()
            return
        }
        if window.frame != visibleFrame {
            window.setFrame(visibleFrame, display: false)
        }
        guideView.apply(showVertical: showVertical, showHorizontal: showHorizontal)
        if !window.isVisible {
            window.orderFront(nil)
        }
    }

    func hide() {
        guideView.apply(showVertical: false, showHorizontal: false)
        if window.isVisible {
            window.orderOut(nil)
        }
    }
}

private final class GuideView: NSView {
    private var showVertical = false
    private var showHorizontal = false

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(showVertical: Bool, showHorizontal: Bool) {
        guard showVertical != self.showVertical || showHorizontal != self.showHorizontal else { return }
        self.showVertical = showVertical
        self.showHorizontal = showHorizontal
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard showVertical || showHorizontal else { return }

        let accent = NSColor(srgbRed: 0.52, green: 0.68, blue: 0.94, alpha: 1) // Theme.accent
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let glow = NSShadow()
        glow.shadowColor = accent.withAlphaComponent(0.6)
        glow.shadowBlurRadius = 8
        glow.shadowOffset = .zero
        glow.set()

        accent.withAlphaComponent(0.95).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2
        path.lineCapStyle = .round
        if showVertical {
            path.move(to: NSPoint(x: bounds.midX, y: bounds.minY))
            path.line(to: NSPoint(x: bounds.midX, y: bounds.maxY))
        }
        if showHorizontal {
            path.move(to: NSPoint(x: bounds.minX, y: bounds.midY))
            path.line(to: NSPoint(x: bounds.maxX, y: bounds.midY))
        }
        path.stroke()
    }
}
