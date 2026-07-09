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
                HStack {
                    Text("Open panel:")
                    Spacer()
                    Picker("Open panel", selection: $summonScreenMode) {
                        ForEach(PanelSummonScreenMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }
            } footer: {
                Text("Choose where the shortcut opens the panel.")
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
