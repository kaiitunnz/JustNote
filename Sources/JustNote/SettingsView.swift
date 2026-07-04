import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle JustNote:", name: .togglePanel)
            } footer: {
                Text("Press this shortcut from any app to show or hide the note panel.")
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
