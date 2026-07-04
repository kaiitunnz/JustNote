import AppKit
import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel
    @State private var showingUninstallConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                editor
            }
            Divider()
            footer
        }
        .frame(width: Theme.panelWidth, height: Theme.panelHeight)
        .tint(Theme.accent)
        .containerBackground(.thinMaterial, for: .window)
        .alert("Uninstall JustNote?", isPresented: $showingUninstallConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive, action: model.uninstallAndQuit)
        } message: {
            Text("This removes ~/Library/Application Support/JustNote, moves the app bundle to the Trash, and quits JustNote.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.18))
                JustNoteMark()
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .padding(7)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("JustNote")
                    .font(Theme.rounded(15, weight: .semibold))
                Text(model.selectedNote?.title ?? "No note selected")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let error = model.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.error)
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .trailing)
            }

            Button(action: model.createNote) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(HeaderIconButtonStyle())
            .help("New note")

            Button(action: model.togglePinSelected) {
                Image(systemName: model.selectedNote?.pinned == true ? "pin.fill" : "pin")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.selectedNote?.pinned == true ? Theme.pinned : .secondary)
            }
            .buttonStyle(HeaderIconButtonStyle())
            .help("Pin note")
            .disabled(model.selectedNote == nil)

            Button(action: model.deleteSelectedNote) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(HeaderIconButtonStyle())
            .help("Delete note")
            .disabled(model.selectedNote == nil)
        }
        .padding(14)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    noteSection("PINNED", notes: model.pinnedNotes, pinned: true)
                    noteSection("NOTES", notes: model.unpinnedNotes, pinned: false)
                }
                .padding(.vertical, 2)
            }

            if !model.recentNotes.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("RECENT")
                        .font(Theme.rounded(10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    ForEach(model.recentNotes.prefix(4)) { note in
                        Button {
                            model.select(note.id)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: note.pinned ? "pin.fill" : "clock")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(note.pinned ? Theme.pinned : Color.secondary.opacity(0.7))
                                Text(note.title)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .contentSurface(cornerRadius: Theme.innerCorner)
            }
        }
        .padding(12)
        .frame(width: Theme.sidebarWidth)
    }

    private func noteSection(_ title: String, notes: [Note], pinned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !notes.isEmpty {
                Text(title)
                    .font(Theme.rounded(10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 2)
                ForEach(notes) { note in
                    NoteRow(
                        note: note,
                        selected: note.id == model.selectedNoteID,
                        canMoveUp: pinned ? model.canMovePinnedNote(note.id, direction: -1) : model.canMoveUnpinnedNote(note.id, direction: -1),
                        canMoveDown: pinned ? model.canMovePinnedNote(note.id, direction: 1) : model.canMoveUnpinnedNote(note.id, direction: 1),
                        select: { model.select(note.id) },
                        moveUp: { pinned ? model.movePinnedNote(note.id, direction: -1) : model.moveUnpinnedNote(note.id, direction: -1) },
                        moveDown: { pinned ? model.movePinnedNote(note.id, direction: 1) : model.moveUnpinnedNote(note.id, direction: 1) }
                    )
                }
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let note = model.selectedNote {
                HStack(spacing: 8) {
                    Image(systemName: note.pinned ? "pin.fill" : "doc.text")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(note.pinned ? Theme.pinned : Theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(note.title)
                            .font(Theme.rounded(13, weight: .semibold))
                            .lineLimit(1)
                        TimestampText(date: note.updatedAt)
                    }
                    Spacer()
                }

                TextEditor(text: model.bodyBinding())
                    .font(Theme.mono(13))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .contentSurface(cornerRadius: Theme.innerCorner)
                    .onTapGesture { }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "note.text.badge.plus")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.accent)
                    Button("Create note", action: model.createNote)
                        .actionButtonStyle(primary: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14)
        .background {
            Color.clear.contentShape(Rectangle()).onTapGesture { resignTextFocus() }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: model.openStorageInFinder) {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 10, weight: .semibold))
                    Text(model.storagePath)
                        .font(Theme.mono(10))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Reveal storage in Finder")
            Spacer()
            Button {
                showingUninstallConfirmation = true
            } label: {
                Label("Uninstall", systemImage: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Button(action: quit) {
                Label("Quit", systemImage: "power")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func quit() {
        AppDelegate.shared?.isQuitting = true
        NSApplication.shared.terminate(nil)
    }
}

private struct NoteRow: View {
    let note: Note
    let selected: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let select: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if note.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Theme.pinned)
                        }
                        Text(note.title)
                            .font(Theme.rounded(11, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        Text(note.preview)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        TimestampText(date: note.updatedAt)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(spacing: 0) {
                reorderButton("chevron.up", disabled: !canMoveUp, action: moveUp)
                reorderButton("chevron.down", disabled: !canMoveDown, action: moveDown)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(selected ? Theme.accent.opacity(0.18) : Color.primary.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner).strokeBorder(selected ? Theme.accent.opacity(0.55) : Color.clear, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Theme.innerCorner))
    }

    private func reorderButton(_ icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 18, height: 16)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.secondary.opacity(0.25) : Color.secondary)
        .disabled(disabled)
    }
}

private struct TimestampText: View {
    let date: Date

    var body: some View {
        Text(Self.text(for: date))
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }

    private static func text(for date: Date) -> String {
        let calendar = Calendar.current
        let time = timeFormatter.string(from: date)
        if calendar.isDateInToday(date) {
            return "Today \(time)"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday \(time)"
        }
        return dateFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH:mm"
        return formatter
    }()
}
