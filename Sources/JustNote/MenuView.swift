import AppKit
import MarkdownView
import SwiftUI
import UniformTypeIdentifiers

struct MenuView: View {
    @ObservedObject var model: AppModel
    @AppStorage("sidebarWidth") private var sidebarWidth = Double(Theme.sidebarWidth)
    @AppStorage("wrapLines") private var wrapLines = true
    @AppStorage("previewMode") private var isPreviewing = false
    @AppStorage("sidebarCollapsed") private var sidebarCollapsed = false
    @State private var showingUninstallConfirmation = false
    @State private var draggingNoteID: UUID?
    @State private var splitDragStartWidth: Double?
    @State private var wrapMessage: String?
    @State private var wrapToken = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                if !sidebarCollapsed {
                    sidebar
                        .frame(width: CGFloat(sidebarWidth))
                        .clipped()
                    Splitter()
                        .gesture(splitDrag)
                }
                editor
            }
            Divider()
            footer
        }
        .frame(width: Theme.panelWidth, height: Theme.panelHeight)
        .background { navigationShortcuts }
        .overlay(alignment: .center) { wrapIndicator }
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

            Button(action: createNote) {
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
                VStack(alignment: .leading, spacing: 2) {
                    noteSection("PINNED", notes: model.pinnedNotes, pinned: true)
                    noteSection("NOTES", notes: model.unpinnedNotes, pinned: false)
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

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
    }

    private func noteSection(_ title: String, notes: [Note], pinned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !notes.isEmpty {
                Text(title)
                    .font(Theme.rounded(10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 2)
                ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                    NoteRow(
                        note: note,
                        selected: note.id == model.selectedNoteID
                    )
                    .onTapGesture { model.select(note.id) }
                    .onDrag {
                        draggingNoteID = note.id
                        return NSItemProvider(object: note.id.uuidString as NSString)
                    }
                    .onDrop(
                        of: [.text],
                        delegate: NoteDropDelegate(
                            model: model,
                            draggingNoteID: $draggingNoteID,
                            pinned: pinned,
                            targetIndex: index
                        )
                    )
                }
                SectionEndDropTarget()
                    .onDrop(
                        of: [.text],
                        delegate: NoteDropDelegate(
                            model: model,
                            draggingNoteID: $draggingNoteID,
                            pinned: pinned,
                            targetIndex: max(notes.count - 1, 0)
                        )
                    )
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let note = model.selectedNote {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { sidebarCollapsed.toggle() }
                    } label: {
                        Image(systemName: sidebarCollapsed ? "sidebar.left" : "sidebar.leading")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(HeaderIconButtonStyle())
                    .help(sidebarCollapsed ? "Show sidebar" : "Hide sidebar")

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
                    if !isPreviewing {
                        Button {
                            wrapLines.toggle()
                        } label: {
                            Image(systemName: wrapLines ? "text.alignleft" : "arrow.left.and.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(HeaderIconButtonStyle())
                        .help(wrapLines ? "Soft wrap is on" : "Soft wrap is off")
                    }
                    Button {
                        isPreviewing.toggle()
                    } label: {
                        Image(systemName: isPreviewing ? "eye" : "pencil")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(HeaderIconButtonStyle())
                    .help(isPreviewing ? "Edit note" : "Preview markdown")
                }

                Group {
                    if isPreviewing {
                        ScrollView {
                            MarkdownText(note.body)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        PlainTextEditor(text: model.bodyBinding(), wrapsLines: wrapLines)
                            .contentShape(Rectangle())
                            .onTapGesture { }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentSurface(cornerRadius: Theme.innerCorner)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "note.text.badge.plus")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.accent)
                    Button("Create note", action: createNote)
                        .actionButtonStyle(primary: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14)
        .background {
            if !isPreviewing {
                Color.clear.contentShape(Rectangle()).onTapGesture { resignTextFocus() }
            }
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

    private func createNote() {
        isPreviewing = false
        model.createNote()
    }

    private var navigationShortcuts: some View {
        Group {
            Button("Next note") { cycle(1) }
                .keyboardShortcut("]", modifiers: .command)
            Button("Previous note") { cycle(-1) }
                .keyboardShortcut("[", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var wrapIndicator: some View {
        if let wrapMessage {
            ZStack {
                Color.black.opacity(0.18)
                VStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text(wrapMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 150, height: 132)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.25), radius: 22, y: 8)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .allowsHitTesting(false)
        }
    }

    private func cycle(_ offset: Int) {
        guard model.selectAdjacentNote(offset: offset) else { return }
        wrapToken += 1
        let token = wrapToken
        withAnimation(.easeOut(duration: 0.15)) {
            wrapMessage = offset > 0 ? "Looped to first note" : "Looped to last note"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            guard wrapToken == token else { return }
            withAnimation(.easeIn(duration: 0.35)) { wrapMessage = nil }
        }
    }

    private func quit() {
        AppDelegate.shared?.isQuitting = true
        NSApplication.shared.terminate(nil)
    }

    private var splitDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if splitDragStartWidth == nil {
                    splitDragStartWidth = sidebarWidth
                }
                let baseWidth = splitDragStartWidth ?? sidebarWidth
                var newWidth = baseWidth + value.translation.width
                if abs(newWidth - Double(Theme.sidebarWidth)) < 15 {
                    newWidth = Double(Theme.sidebarWidth)
                }
                sidebarWidth = min(max(newWidth, Double(Theme.minSidebarWidth)), Double(Theme.maxSidebarWidth))
            }
            .onEnded { _ in
                splitDragStartWidth = nil
            }
    }
}

private struct Splitter: View {
    @State private var hovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 10)
            Rectangle()
                .fill(hovering ? Theme.accent.opacity(0.65) : Color(nsColor: .separatorColor))
                .frame(width: hovering ? 2 : 1)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

private struct NoteRow: View {
    let note: Note
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
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
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(selected ? Theme.accent.opacity(0.18) : Color.primary.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner).strokeBorder(selected ? Theme.accent.opacity(0.55) : Color.clear, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Theme.innerCorner))
    }
}

private struct SectionEndDropTarget: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.primary.opacity(0.001))
            .frame(height: 4)
    }
}

private struct NoteDropDelegate: DropDelegate {
    @ObservedObject var model: AppModel
    @Binding var draggingNoteID: UUID?
    let pinned: Bool
    let targetIndex: Int

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let noteID = draggingNoteID else { return }
        move(noteID)
    }

    func performDrop(info: DropInfo) -> Bool {
        if let noteID = draggingNoteID {
            move(noteID)
            draggingNoteID = nil
            return true
        }

        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let string = item as? NSString, let noteID = UUID(uuidString: string as String) else { return }
            Task { @MainActor in
                move(noteID)
                draggingNoteID = nil
            }
        }
        return true
    }

    func dropExited(info: DropInfo) {}

    private func move(_ noteID: UUID) {
        guard model.notes.first(where: { $0.id == noteID })?.pinned == pinned else { return }
        model.moveNote(noteID, inPinnedSection: pinned, toIndex: targetIndex)
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
