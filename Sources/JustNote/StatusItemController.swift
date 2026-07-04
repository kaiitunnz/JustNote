import AppKit
import SwiftUI

/// Owns the menu-bar status item and the panel popover. Left-click (or the global hotkey) toggles
/// the panel via `togglePopover()`; Settings and Quit live inside the panel itself. Replaces
/// `MenuBarExtra`, which exposes no way to open its window programmatically.
///
/// The popover uses `.applicationDefined` behavior and manages its own dismissal (mouse-down
/// monitors + app-deactivation) so it survives being summoned over a full-screen app: a
/// `.transient` popover self-closes on the spurious event the menu-bar reveal produces.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var shownAt: Date?

    init(model: AppModel) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.contentSize = NSSize(width: Theme.panelWidth, height: Theme.panelHeight)
        popover.contentViewController = NSHostingController(rootView: MenuView(model: model))

        super.init()

        popover.delegate = self

        if let button = statusItem.button {
            button.image = MenuBarIcon.image()
            button.target = self
            button.action = #selector(togglePopover)
        }
    }

    /// Shows the panel (activating the app and making the popover key so typing works even when
    /// summoned from another app) or closes it if already open.
    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        shownAt = Date()
        // Defer one hop so the activation and (over a full-screen app) menu-bar reveal churn from
        // showing settles before we start listening — otherwise our own handlers fire on it.
        DispatchQueue.main.async { [weak self] in self?.installDismissHandlers() }
    }

    func closePopover() {
        if popover.isShown { popover.performClose(nil) }
    }

    func withDismissHandlersSuspended<T>(_ work: () -> T) -> T {
        let shouldRestore = popover.isShown
        removeDismissHandlers()
        defer {
            if shouldRestore, popover.isShown {
                installDismissHandlers()
            }
        }
        return work()
    }

    /// `.applicationDefined` never auto-closes, so we replicate the transient dismissals we want:
    /// a click in another app (global), a click elsewhere in our own app (local, excluding the
    /// status button and the popover itself), and app deactivation (Cmd-Tab / Mission Control).
    private func installDismissHandlers() {
        guard popover.isShown else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            let clickWindow = event.window
            // A click on the status button routes here too; leave it to the button's own toggle so
            // we don't close-then-reopen. Clicks inside the popover keep it open.
            if clickWindow != self.statusItem.button?.window,
               clickWindow != self.popover.contentViewController?.view.window {
                self.popover.performClose(nil)
            }
            return event
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    /// Ignore the resign churn from summoning over a full-screen app: the menu-bar reveal is an
    /// animated ~200-300ms transition, so gate on time-since-show rather than a single runloop hop.
    @objc private func applicationDidResignActive() {
        if let shownAt, Date().timeIntervalSince(shownAt) < 0.4 { return }
        popover.performClose(nil)
    }

    private func removeDismissHandlers() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
        globalMonitor = nil
        localMonitor = nil
    }
}

extension StatusItemController: NSPopoverDelegate {
    /// Single teardown point: every close (toggle, outside click, deactivation, Settings) routes
    /// through here since the popover never auto-closes.
    func popoverDidClose(_ notification: Notification) {
        removeDismissHandlers()
    }
}
