import AppKit
import SwiftUI

/// A borderless panel that can still become key so its hosted text view accepts input — the
/// standard construction for a Spotlight/Alfred-style summon panel. A plain borderless window
/// refuses key/main status, which would leave the editor unable to receive typing.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns the summoned note panel: a free-floating `NSPanel` toggled by the global shortcut, shown
/// centered over the active screen (including full-screen spaces), and dismissed on the shortcut,
/// Escape, or losing key. Replaces the status-item popover, whose anchor to a menu-bar button was
/// the source of the keyboard bugs on macOS 26/27; a standalone key window has no such anchor.
@MainActor
final class PanelController: NSObject {
    private let panel: FloatingPanel
    private var escapeMonitor: Any?
    private var shownAt: Date?
    private var dismissSuspended = false

    /// Grace period after showing during which a resign-key event is ignored: summoning over a
    /// full-screen space can churn key status before the panel settles, and self-dismissing then
    /// would make the panel impossible to summon there.
    private let showGrace: TimeInterval = 0.35

    init(model: AppModel) {
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth, height: Theme.panelHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
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
        positionOnActiveScreen()
        installEscapeMonitor()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
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
            if let key = NSApp.keyWindow, key != self.panel { return }
            if let main = NSApp.mainWindow, main != self.panel { return }
            self.close()
        }
    }

    /// Single teardown point for the key monitor, robust to every close path.
    func windowWillClose(_ notification: Notification) {
        removeEscapeMonitor()
    }
}
