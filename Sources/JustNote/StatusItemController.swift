import AppKit
import SwiftUI

/// Owns the menu-bar status item and the panel popover. Left-click toggles the panel;
/// right-click opens a small menu (Settings, Quit). Replaces `MenuBarExtra`, which exposes
/// no way to open its window programmatically — the global hotkey needs `togglePopover()`.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let menu = NSMenu()

    init(model: AppModel) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: Theme.panelWidth, height: Theme.panelHeight)
        popover.contentViewController = NSHostingController(rootView: MenuView(model: model))

        super.init()

        if let button = statusItem.button {
            button.image = MenuBarIcon.image()
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        buildMenu()
    }

    private func buildMenu() {
        // No key equivalents: this menu isn't installed in the main menu bar, so any shortcut
        // shown here would be live only while the menu is open — misleading as a "global" hint.
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit JustNote", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    /// Shows the panel (activating the app and making the popover key so typing works even when
    /// summoned from another app) or closes it if already open.
    func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func openSettings() {
        AppDelegate.shared?.openSettings()
    }

    @objc private func quit() {
        AppDelegate.shared?.isQuitting = true
        NSApp.terminate(nil)
    }
}
