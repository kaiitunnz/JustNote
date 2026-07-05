# RFC 0001: Shortcut-summoned floating panel

- Status: Draft
- Author: Noppanat Wadlom
- Created: 2026-07-05

## Summary

Replace the menu-bar status item and its anchored `NSPopover` with a free-floating `NSPanel` that the user summons with a global shortcut. Launching the JustNote app (Finder, Spotlight, Dock) opens the Settings window, which is where the shortcut is displayed and configured. JustNote stays a background (accessory) app with no persistent menu-bar icon.

## Motivation

JustNote presents its panel as an `NSPopover` anchored to an `NSStatusItem` button. That coupling is the source of a class of keyboard bugs on recent macOS: when the panel is open and a keystroke reaches no consuming control, macOS routes it to the popover's anchor — the status-item button — and posts a *synthesized* click to it, firing the button's toggle action. Symptoms observed on macOS 26/27:

- Pressing Space or Return dismisses the panel.
- The first Space/Return immediately after opening is absorbed instead of typed, because macOS hands that first keystroke to the menu-bar item upstream of any application-level hook.

The shipped fix (drop button clicks whose event source is not the HID system while the panel is open) stops the dismissal, but it is a workaround on the symptom. The first-keystroke absorption is not fixable from the application: the keystroke is consumed before it reaches any responder, key-window, focus, or event-monitor hook the app controls. Both behaviors disappear only if the panel is not anchored to a menu-bar button.

## Root cause

The panel is an `NSPopover` whose anchor is an `NSStatusBarButton`, a control with a target/action that macOS activates on behalf of the menu-bar item. A standalone key window has no such anchor and receives keyboard input normally.

## Proposal

Present the panel as a standalone `NSPanel` and summon it with the existing global shortcut. The load-bearing decision is not "menu bar vs. background app" — it is "popover anchored to a status-item button" vs. "free-floating key window." Those are separable, which yields two options:

- **Option A — drop the status item.** No menu-bar icon. The global shortcut is the only summon; launching the app opens Settings for discovery and configuration.
- **Option B — hybrid.** Keep the menu-bar icon but open a standalone `NSPanel` (not an anchored popover) from both the icon and the shortcut.

Option B likely fixes the keyboard bug because the panel is its own key window, but a click on the icon still routes through the menu-bar item, so the first-keystroke capture *may* persist for the click-to-open path; a summon via shortcut is unaffected in either option. The deciding axis between A and B is discoverability, not correctness.

## Detailed design

**Panel.** A borderless `NSPanel` subclass that overrides `canBecomeKey` (and `canBecomeMain`) to return `true` — a borderless panel does not accept key/text input otherwise. This is the standard construction for Spotlight/Alfred-style panels. It hosts the existing SwiftUI `MenuView` unchanged; the material background and rounded chrome move from the popover onto the panel.

**Summon and dismiss.** The global shortcut toggles the panel. Dismiss on Escape, on resigning key (click outside), or on the toggle shortcut. This replaces the current dismissal machinery — the global and local mouse-down monitors and the `applicationDidResignActive` time-gate — which exist specifically because popovers over full-screen spaces misbehave.

**Full-screen spaces.** A panel with `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` and a floating window level appears over full-screen apps natively, covering the case the current `.applicationDefined` popover and its monitors work around.

**Positioning.** Center on the active screen (Spotlight-like). Remembering the last position or making the panel draggable can follow.

**Activation policy.** Remain `.accessory`. Launching or reopening the app while it is running opens the Settings window: `applicationShouldHandleReopen` already opens Settings when no window is visible, and `openSettings()` already flips to `.regular` to surface a Dock icon while Settings is up.

**First launch.** With no menu-bar icon, the first launch opens Settings to teach the shortcut, rather than opening an empty panel the user cannot find again.

## What this removes

- The synthesized-click workaround in `StatusItemController`.
- The global/local mouse-down dismiss monitors and the `applicationDidResignActive` time-gate.
- The status-item creation and menu-bar icon assets.

Net: the fix is structural rather than defensive, and the dismissal path becomes standard window behavior.

## Trade-offs

Discoverability is the primary cost of Option A. The menu-bar icon is the visible affordance for "the app exists" and a one-click open; without it, a user who forgets the shortcut has only "launch the app → Settings" as a pointer-driven entry point. Mitigations: a sensible default shortcut, a first-launch Settings screen that states it, and optional launch-at-login. This is a product decision; Option B keeps the icon at the cost of leaving the click-to-open first-keystroke question open.

## Migration

`MenuView` and the model are reusable as-is. Work concentrates in:

- A new `PanelController` (and `NSPanel` subclass) replacing `StatusItemController`: summon, position, dismiss, key handling.
- `JustNoteApp` / `AppDelegate`: first-launch and relaunch-opens-Settings behavior; confirm the accessory policy.
- Deleting the status-item and monitor code.

No data or storage changes.

## Risks and open questions

- **Discoverability without an icon** (Option A) — the main open product question.
- **`NSPanel` key acceptance and over-full-screen behavior on macOS 26/27** — the status-item behavior surprised us here, so these want a spike before committing: a borderless key-accepting `NSPanel` shown over a full-screen space, confirming it takes text input and that no first-keystroke capture remains.
- **Shortcut conflicts** — a taken shortcut leaves the user reliant on launch→Settings to rebind; acceptable, but argues for a good default.

## Alternatives considered

- **Keep the popover, keep the workaround.** Rejected as the long-term shape: it leaves the first-keystroke absorption unfixable and retains the dismissal-monitor complexity.
- **Option B (hybrid).** Viable if the menu-bar icon is a product requirement; carries the unresolved click-to-open first-keystroke question.

## Out of scope

Panel theming beyond porting the current chrome, position persistence, and launch-at-login are follow-ups, not prerequisites.
