import AppKit
import SwiftUI

/// A chromeless panel that always accepts key/main so its hosted text view receives input. The
/// overrides matter for the borderless-adjacent configuration (a bare panel can refuse key status)
/// and are harmless for the titled window used here.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns the summoned note panel: a free-floating `NSPanel` toggled by the global shortcut, shown
/// over the active screen (including full-screen spaces), and dismissed on the shortcut, Escape, or
/// losing key. It is user-movable and -resizable, and its frame persists across summons and app
/// restarts. Replaces the status-item popover, whose anchor to a menu-bar button was the source of
/// the keyboard bugs on macOS 26/27; a standalone key window has no such anchor.
@MainActor
final class PanelController: NSObject {
    private let panel: FloatingPanel
    private var escapeMonitor: Any?
    private var shownAt: Date?
    private var dismissSuspended = false
    private var hasPositioned = false

    /// True when a saved frame was restored at launch — first summon then keeps it instead of
    /// re-centering.
    private var restoredSavedFrame = false

    private static let frameAutosaveName = NSWindow.FrameAutosaveName("JustNotePanelFrame")

    /// Grace period after showing during which a resign-key event is ignored: summoning over a
    /// full-screen space can churn key status before the panel settles, and self-dismissing then
    /// would make the panel impossible to summon there.
    private let showGrace: TimeInterval = 0.35

    init(model: AppModel) {
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
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: effectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])

        panel.contentView = effectView

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
        positionForSummon()
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

    /// Decide where the panel appears on summon. The first summon centers Spotlight-style unless a
    /// saved frame was restored at launch; later summons keep the frame the user left it at (the
    /// panel isn't released between summons). Any summon whose frame is no longer on a screen — e.g.
    /// a display was disconnected — recenters.
    private func positionForSummon() {
        if !hasPositioned {
            hasPositioned = true
            if !restoredSavedFrame { positionOnActiveScreen() }
        }
        if !frameIsVisible(panel.frame) { positionOnActiveScreen() }
    }

    /// Center horizontally and sit in the upper third (Spotlight-like) of the screen under the
    /// pointer, falling back to the main screen.
    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            panel.center()
            return
        }
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.minY + visible.height * 0.62 - size.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
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

    /// Single teardown point for the key monitor, robust to every close path.
    func windowWillClose(_ notification: Notification) {
        removeEscapeMonitor()
    }

    /// `.resizable` makes the panel zoomable, so a double-click on the transparent titlebar (which
    /// overlaps the header) would balloon it to fill the screen and persist that frame. Suppress it.
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        false
    }
}
