import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @AppStorage(PanelSummonScreenMode.defaultsKey) private var summonScreenMode = PanelSummonScreenMode.last.rawValue

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle JustNote:", name: .togglePanel)
            } footer: {
                Text("Press this shortcut from any app to show or hide the note panel.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Summon placement:", selection: $summonScreenMode) {
                    ForEach(PanelSummonScreenMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Last keeps the saved frame. Mouse and Focused keep the panel's relative placement on the screen under the pointer or the currently focused screen.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(FixedShortcut.all) { shortcut in
                    HStack {
                        Text(shortcut.action)
                        Spacer()
                        Text(shortcut.keys)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Fixed Shortcuts")
            } footer: {
                Text("These panel shortcuts are built in and are not configurable yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .tint(Theme.accent)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FixedShortcut: Identifiable {
    let action: String
    let keys: String

    var id: String { action }

    static let all = [
        FixedShortcut(action: "New note", keys: "⌘N"),
        FixedShortcut(action: "Delete selected note(s)", keys: "⌘⇧D"),
        FixedShortcut(action: "Pin or unpin selected note(s)", keys: "⌘⇧P"),
        FixedShortcut(action: "Select all notes", keys: "⌘⌥A"),
        FixedShortcut(action: "Show or hide sidebar", keys: "⌘⇧E"),
        FixedShortcut(action: "Preview or edit Markdown", keys: "⌘⇧V"),
        FixedShortcut(action: "Toggle soft wrap", keys: "⌘⌥W"),
        FixedShortcut(action: "Reveal notes folder", keys: "⌘⇧R"),
    ]
}
