import AppKit
import Carbon
import KeyboardShortcuts
import SwiftUI

@main
struct JustNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.period, modifiers: [.option]))
}

/// Owns the app lifecycle: menu-bar-only at rest, a Dock icon only while the Settings window is
/// open, and a soft ⌘Q that hides back to the menu bar. Only the panel's Quit button (which sets
/// `isQuitting`) fully terminates; system logout/shutdown is never vetoed.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// NSApp.delegate is SwiftUI's internal wrapper (not this instance), so views and the
    /// status-item controller reach the adaptor through this reference.
    static private(set) var shared: AppDelegate?

    var isQuitting = false
    private(set) var statusItemController: StatusItemController!
    private var model: AppModel!

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model = AppModel()
        statusItemController = StatusItemController(model: model)
        KeyboardShortcuts.onKeyUp(for: .togglePanel) {
            AppDelegate.shared?.statusItemController.togglePopover()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    /// Opens the Settings scene. The app must be `.regular` first, or the window won't come
    /// forward from an accessory app; the send is deferred one runloop hop so the policy flip
    /// settles before AppKit routes `showSettingsWindow:`.
    func openSettings() {
        prepareToShowWindow()
        DispatchQueue.main.async {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    /// Return to menu-bar-only once the Settings window closes. `willCloseNotification` fires
    /// before the window leaves `NSApp.windows`, so defer the count until it has.
    @objc private func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            guard !self.hasTitledWindow else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// The status item is itself an always-present window, so `hasVisibleWindows` can't be
    /// trusted — count titled windows instead (miniaturized ones included, so a Dock click
    /// deminiaturizes rather than reopening Settings on top).
    private var hasTitledWindow: Bool {
        NSApp.windows.contains {
            $0.styleMask.contains(.titled) && ($0.isVisible || $0.isMiniaturized)
        }
    }

    /// A Dock click with no open window opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !hasTitledWindow else { return true }
        openSettings()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isQuitting { return .terminateNow }
        // Never veto system logout / restart / shutdown.
        if NSAppleEventManager.shared().currentAppleEvent?.eventID == kAEQuitApplication {
            return .terminateNow
        }
        // App-menu ⌘Q while the Settings window is up: hide to the menu bar instead of quitting.
        for window in NSApp.windows
        where window.styleMask.contains(.titled) && (window.isVisible || window.isMiniaturized) {
            window.close()
        }
        NSApp.setActivationPolicy(.accessory)
        return .terminateCancel
    }
}
