import AppKit
import SwiftUI

enum PanelSummonScreenMode: String, CaseIterable, Identifiable {
    case last
    case mouse
    case focused

    static let defaultsKey = "panelSummonScreenMode"

    var id: Self { self }

    var title: String {
        switch self {
        case .last:
            return "Last position"
        case .mouse:
            return "Mouse screen"
        case .focused:
            return "Focused screen"
        }
    }
}

struct PanelSummonPlacement {
    static func reproject(frame: NSRect, from sourceVisible: NSRect, to targetVisible: NSRect, minSize: NSSize) -> NSRect? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        guard sourceVisible.width > 0, sourceVisible.height > 0 else { return nil }
        guard targetVisible.width > 0, targetVisible.height > 0 else { return nil }

        let width = min(max(minSize.width, frame.width), targetVisible.width)
        let height = min(max(minSize.height, frame.height), targetVisible.height)
        let x = targetVisible.minX + (frame.minX - sourceVisible.minX) / sourceVisible.width * targetVisible.width
        let y = targetVisible.minY + (frame.minY - sourceVisible.minY) / sourceVisible.height * targetVisible.height

        return NSRect(
            x: min(max(x, targetVisible.minX), targetVisible.maxX - width),
            y: min(max(y, targetVisible.minY), targetVisible.maxY - height),
            width: width,
            height: height
        )
    }
}

/// A chromeless panel that always accepts key/main so its hosted text view receives input. The
/// overrides matter for the borderless-adjacent configuration (a bare panel can refuse key status)
/// and are harmless for the titled window used here.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

}

/// Owns the summoned note panel: a free-floating `NSPanel` toggled by the global shortcut, shown
/// over a user-selected target screen (including full-screen spaces), and dismissed on the
/// shortcut, Escape, or losing key. It is user-movable and -resizable, and its frame persists
/// across summons and app restarts. Replaces the status-item popover, whose anchor to a menu-bar
/// button was the source of the keyboard bugs on macOS 26/27; a standalone key window has no such
/// anchor.
@MainActor
final class PanelController: NSObject {
    private let panel: FloatingPanel
    private let dragHandle: PanelDragHandle
    private var dragHandleHeightConstraint: NSLayoutConstraint?
    private var escapeMonitor: Any?
    private var shownAt: Date?
    private var dismissSuspended = false
    private var hasPositioned = false

    /// Per-dimension resize snap state, so the alignment haptic fires once when a dimension engages
    /// the default size rather than repeatedly while it stays snapped.
    private var snappedWidth = false
    private var snappedHeight = false

    /// State captured by the app-owned title strip while it is dragging the panel.
    private var dragStartMouseLocation: NSPoint?
    private var dragStartOrigin: NSPoint?
    private var dragSnappedX = false
    private var dragSnappedY = false
    private weak var dragSnapScreen: NSScreen?
    private var dragSnapVisibleFrame: NSRect?

    /// True when a saved frame was restored at launch — first summon then keeps it instead of
    /// re-centering.
    private var restoredSavedFrame = false

    private static let frameAutosaveName = NSWindow.FrameAutosaveName("JustNotePanelFrame")

    /// Grace period after showing during which a resign-key event is ignored: summoning over a
    /// full-screen space can churn key status before the panel settles, and self-dismissing then
    /// would make the panel impossible to summon there.
    private let showGrace: TimeInterval = 0.35

    init(model: AppModel) {
        dragHandle = PanelDragHandle()
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth, height: Theme.panelHeight),
            styleMask: [.titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )

        super.init()

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: Theme.minPanelWidth, height: Theme.minPanelHeight)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        // Native titlebar movement is WindowServer-owned and cannot be reconciled with live frame
        // snapping. PanelDragHandle owns the complete titlebar-height region below.
        panel.isMovable = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.delegate = self

        // Material + rounded chrome that the popover used to supply, now carried by the panel:
        // a visual-effect content view clipped to the theme corner, with the SwiftUI panel on top.
        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = Theme.corner
        effectView.layer?.masksToBounds = true

        let hostingView = NSHostingView(rootView: MenuView(model: model))
        hostingView.safeAreaRegions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: effectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])

        dragHandle.translatesAutoresizingMaskIntoConstraints = false
        dragHandle.passThroughEvents(to: hostingView)
        dragHandle.onDragBegan = { [weak self] in self?.beginPanelDrag() }
        dragHandle.onDrag = { [weak self] in self?.continuePanelDrag() }
        dragHandle.onDragEnded = { [weak self] in self?.endPanelDrag() }
        effectView.addSubview(dragHandle)
        NSLayoutConstraint.activate([
            dragHandle.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            dragHandle.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            dragHandle.topAnchor.constraint(equalTo: effectView.topAnchor),
        ])
        dragHandleHeightConstraint = dragHandle.heightAnchor.constraint(equalToConstant: 0)
        dragHandleHeightConstraint?.isActive = true

        panel.contentView = effectView
        updateDragHandleHeight()

        // Persist and restore the user's frame across launches. With an autosave name set, the
        // panel writes its frame to UserDefaults on every move/resize automatically; `setFrameUsingName`
        // restores it (false when nothing is saved yet).
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        restoredSavedFrame = panel.setFrameUsingName(Self.frameAutosaveName)
    }

    /// Toggle entry point for the global shortcut: summon if hidden, dismiss if already up.
    func toggle() {
        if panel.isVisible {
            close()
        } else {
            show()
        }
    }

    private func show() {
        let focusedScreen = NSScreen.main
        positionForSummon(focusedScreen: focusedScreen)
        installEscapeMonitor()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        shownAt = Date()
    }

    func close() {
        if panel.isVisible { panel.close() }
    }

    /// Run `work` with resign-key dismissal suppressed, so an app-modal alert opened from the panel
    /// (e.g. the delete confirmation) doesn't close the panel out from under itself.
    func withDismissSuspended<T>(_ work: () -> T) -> T {
        let previous = dismissSuspended
        dismissSuspended = true
        defer { dismissSuspended = previous }
        return work()
    }

    /// Decide where the panel appears on summon. `last` keeps today's absolute saved-frame behavior;
    /// `mouse` and `focused` reproject the current frame's size and placement ratios onto the target
    /// screen's visible frame, falling back to the Spotlight-style default when that geometry is no
    /// longer usable.
    private func positionForSummon(focusedScreen: NSScreen?) {
        let isFirstSummon = !hasPositioned
        hasPositioned = true

        let mouseScreen = screenContainingMouse()
        switch summonScreenMode {
        case .last:
            positionForLastSummon(isFirstSummon: isFirstSummon, fallbackScreen: mouseScreen ?? focusedScreen)
        case .mouse:
            positionRelativeToTargetScreen(
                mouseScreen ?? focusedScreen,
                hasUsefulCurrentFrame: !isFirstSummon || restoredSavedFrame
            )
        case .focused:
            positionRelativeToTargetScreen(
                focusedScreen ?? mouseScreen,
                hasUsefulCurrentFrame: !isFirstSummon || restoredSavedFrame
            )
        }
    }

    /// Center horizontally and sit in the upper third (Spotlight-like) of the screen under the
    /// pointer, falling back to the supplied screen or the main screen.
    private func positionDefault(on screen: NSScreen?) {
        let screen = screen ?? screenContainingMouse() ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            panel.center()
            return
        }
        let size = NSSize(
            width: min(panel.frame.width, visible.width),
            height: min(panel.frame.height, visible.height)
        )
        let x = visible.midX - size.width / 2
        let y = visible.minY + visible.height * 0.62 - size.height / 2
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: false)
    }

    /// A frame is usable if most of it lands on a single screen's visible area — mere edge contact
    /// (e.g. a frame saved on a now-disconnected larger display) recenters instead.
    private func frameIsVisible(_ frame: NSRect) -> Bool {
        let area = frame.width * frame.height
        guard area > 0 else { return false }
        return NSScreen.screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(frame)
            return (overlap.width * overlap.height) >= area * 0.6
        }
    }

    private var summonScreenMode: PanelSummonScreenMode {
        PanelSummonScreenMode(rawValue: UserDefaults.standard.string(forKey: PanelSummonScreenMode.defaultsKey) ?? "")
            ?? .last
    }

    private func positionForLastSummon(isFirstSummon: Bool, fallbackScreen: NSScreen?) {
        if isFirstSummon, !restoredSavedFrame {
            positionDefault(on: fallbackScreen)
        }
        if !frameIsVisible(panel.frame) {
            positionDefault(on: fallbackScreen)
        }
    }

    private func positionRelativeToTargetScreen(_ targetScreen: NSScreen?, hasUsefulCurrentFrame: Bool) {
        guard let targetScreen else {
            positionDefault(on: nil)
            return
        }
        guard hasUsefulCurrentFrame else {
            positionDefault(on: targetScreen)
            return
        }
        guard
            let sourceScreen = screenContainingLargestVisibleArea(of: panel.frame),
            let reprojected = PanelSummonPlacement.reproject(
                frame: panel.frame,
                from: sourceScreen.visibleFrame,
                to: targetScreen.visibleFrame,
                minSize: panel.minSize
            )
        else {
            positionDefault(on: targetScreen)
            return
        }
        panel.setFrame(reprojected, display: false)
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    private func screenContainingLargestVisibleArea(of frame: NSRect) -> NSScreen? {
        let match = NSScreen.screens
            .map { screen in
                let overlap = screen.visibleFrame.intersection(frame)
                return (screen, overlap.width * overlap.height)
            }
            .max { $0.1 < $1.1 }
        guard let match, match.1 > 0 else { return nil }
        return match.0
    }

    /// Escape must dismiss even while the note editor is first responder, where `cancelOperation`
    /// never reaches the panel (the text view swallows Escape as `complete:`). A local key monitor
    /// runs ahead of the text system — but it must yield to an active input-method composition, so
    /// CJK users can still cancel marked text with Escape.
    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, event.window == self.panel else { return event }
            if let textView = self.panel.firstResponder as? NSTextView, textView.hasMarkedText() {
                return event
            }
            self.close()
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }

    private func beginPanelDrag() {
        guard panel.isVisible, !panel.inLiveResize else { return }
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartOrigin = panel.frame.origin
        dragSnappedX = false
        dragSnappedY = false
        dragSnapScreen = nil
        dragSnapVisibleFrame = nil
    }

    private func continuePanelDrag() {
        guard
            let startMouse = dragStartMouseLocation,
            let startOrigin = dragStartOrigin,
            panel.isVisible,
            !panel.inLiveResize
        else { return }

        let mouse = NSEvent.mouseLocation
        let proposedOrigin = NSPoint(
            x: startOrigin.x + mouse.x - startMouse.x,
            y: startOrigin.y + mouse.y - startMouse.y
        )
        let proposedFrame = NSRect(origin: proposedOrigin, size: panel.frame.size)
        let screen = screenContainingLargestVisibleArea(of: proposedFrame)
            ?? screenContainingMouse()
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            panel.setFrameOrigin(proposedOrigin)
            return
        }

        if dragSnapScreen !== screen || dragSnapVisibleFrame != visible {
            // A center target belongs to a specific display. Re-arm both axes when crossing to a
            // new target so the new display uses the engage threshold and emits its own haptic.
            dragSnappedX = false
            dragSnappedY = false
            dragSnapScreen = screen
            dragSnapVisibleFrame = visible
        }

        let result = PanelSnap.snapOrigin(
            proposedOrigin,
            windowSize: panel.frame.size,
            in: visible,
            snappedX: dragSnappedX,
            snappedY: dragSnappedY
        )
        if (result.snappedX && !dragSnappedX) || (result.snappedY && !dragSnappedY) {
            PanelSnap.performAlignmentHaptic()
        }
        dragSnappedX = result.snappedX
        dragSnappedY = result.snappedY
        panel.setFrameOrigin(result.origin)
    }

    private func endPanelDrag() {
        dragStartMouseLocation = nil
        dragStartOrigin = nil
        dragSnappedX = false
        dragSnappedY = false
        dragSnapScreen = nil
        dragSnapVisibleFrame = nil
    }

    /// The full-size-content-view content extends under the titlebar. Use AppKit's unobscured
    /// content layout rect instead of duplicating the current titlebar height, which can vary with
    /// appearance, toolbar configuration, or future window-style changes.
    private func updateDragHandleHeight() {
        guard let constraint = dragHandleHeightConstraint else { return }
        let titlebarHeight = panel.frame.height - panel.contentLayoutRect.height
        let height = max(0, titlebarHeight)
        dragHandle.setActiveHeight(height)
        constraint.constant = height
    }
}

extension PanelController: NSWindowDelegate {
    /// Dismiss on losing key (click outside / switch apps), unless suppressed, still within the
    /// post-show grace period, or another of our own windows took key/main — the delete `NSAlert`,
    /// the uninstall alert, and the Settings window all legitimately steal key without meaning the
    /// panel should close.
    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible, !self.dismissSuspended else { return }
            if let shownAt = self.shownAt, Date().timeIntervalSince(shownAt) < self.showGrace { return }
            // The panel regained key by the time this runs (e.g. an app-modal alert opened and
            // closed): a stale resign event must not close it.
            if NSApp.keyWindow == self.panel { return }
            if let key = NSApp.keyWindow, key != self.panel { return }
            if let main = NSApp.mainWindow, main != self.panel { return }
            self.close()
        }
    }

    /// Single teardown point for the event monitors, robust to every close path.
    func windowWillClose(_ notification: Notification) {
        removeEscapeMonitor()
        endPanelDrag()
    }

    /// `.resizable` makes the panel zoomable, so a double-click on the transparent titlebar (which
    /// overlaps the header) would balloon it to fill the screen and persist that frame. Suppress it.
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        false
    }

    /// Magnetically snap each dimension to the default panel size during a live resize. Returning the
    /// snapped size keeps the dragged edge anchored while the size sticks at the default within the
    /// threshold and releases once pulled past it. Only the dimension the drag actually changes is
    /// eligible — dragging one edge must not tug the perpendicular dimension to the default (and fire
    /// its haptic) when it happens to already sit near it.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let current = sender.frame.size
        var result = PanelSnap.snapSize(
            frameSize,
            to: NSSize(width: Theme.panelWidth, height: Theme.panelHeight)
        )
        if frameSize.width == current.width {
            result.size.width = frameSize.width
            result.snappedWidth = false
        }
        if frameSize.height == current.height {
            result.size.height = frameSize.height
            result.snappedHeight = false
        }
        if (result.snappedWidth && !snappedWidth) || (result.snappedHeight && !snappedHeight) {
            PanelSnap.performAlignmentHaptic()
        }
        snappedWidth = result.snappedWidth
        snappedHeight = result.snappedHeight
        return result.size
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        snappedWidth = false
        snappedHeight = false
    }

    func windowDidResize(_ notification: Notification) {
        updateDragHandleHeight()
    }

}
