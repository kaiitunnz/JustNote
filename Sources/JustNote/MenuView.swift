import AppKit
import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel

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
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(model.orderedNotes) { note in
                        noteButton(note)
                    }
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

    private func noteButton(_ note: Note) -> some View {
        Button {
            model.select(note.id)
        } label: {
            NoteRow(note: note, selected: note.id == model.selectedNoteID)
        }
        .buttonStyle(.plain)
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
                        Text(note.updatedAt, style: .relative)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
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
            Image(systemName: "externaldrive")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(model.storagePath)
                .font(Theme.mono(10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if note.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.pinned)
                }
                Text(note.title)
                    .font(Theme.rounded(12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(note.preview)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(note.updatedAt, style: .relative)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(selected ? Theme.accent.opacity(0.18) : Color.primary.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner).strokeBorder(selected ? Theme.accent.opacity(0.55) : Color.clear, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Theme.innerCorner))
    }
}
