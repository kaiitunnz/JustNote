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
    @State private var wrapIcon: String?
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
        .frame(minWidth: Theme.minPanelWidth, maxWidth: .infinity, minHeight: Theme.minPanelHeight, maxHeight: .infinity)
        .background { keyboardShortcuts }
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
                Text(selectionSubtitle)
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
                Image(systemName: selectedNotesAllPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selectedNotesAllPinned ? Theme.pinned : .secondary)
            }
            .buttonStyle(HeaderIconButtonStyle())
            .help(selectedNotesAllPinned ? "Unpin selected notes" : "Pin selected notes")
            .disabled(!hasSelectedNotes)

            Button(action: requestDeleteSelectedNotes) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(HeaderIconButtonStyle())
            .help("Delete selected notes")
            .disabled(!hasSelectedNotes)
        }
        .padding(14)
        .collapsesSelectionOnTap(model)
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
        }
        .padding(12)
        .collapsesSelectionOnTap(model)
        .contextMenu {
            sidebarContextMenu
        }
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
                        selected: model.selectedNoteIDs.contains(note.id),
                        primary: note.id == model.selectedNoteID
                    )
                    .onTapGesture { select(note) }
                    .contextMenu {
                        noteContextMenu(note, pinned: pinned, targetIDs: model.actionTargetIDs(containing: note.id))
                    }
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

    @ViewBuilder
    private var sidebarContextMenu: some View {
        Button {
            createNote()
        } label: {
            Label("New Note", systemImage: "square.and.pencil")
        }

        Button {
            pasteAsNewNote()
        } label: {
            Label("Paste as New Note", systemImage: "doc.on.clipboard")
        }
        .disabled(pasteboardText == nil)
    }

    @ViewBuilder
    private func noteContextMenu(_ note: Note, pinned: Bool, targetIDs: Set<UUID>) -> some View {
        let targetNotes = model.notesInDisplayOrder(for: targetIDs)
        let count = targetNotes.count
        let allPinned = targetNotes.allSatisfy(\.pinned)
        let allUnpinned = targetNotes.allSatisfy { !$0.pinned }

        if allPinned {
            Button {
                model.setPinned(targetIDs, pinned: false)
            } label: {
                Label(count == 1 ? "Unpin Note" : "Unpin Selected", systemImage: "pin.slash")
            }
        } else if allUnpinned {
            Button {
                model.setPinned(targetIDs, pinned: true)
            } label: {
                Label(count == 1 ? "Pin Note" : "Pin Selected", systemImage: "pin")
            }
        } else {
            Button {
                model.setPinned(targetIDs, pinned: true)
            } label: {
                Label("Pin Selected", systemImage: "pin")
            }
            Button {
                model.setPinned(targetIDs, pinned: false)
            } label: {
                Label("Unpin Selected", systemImage: "pin.slash")
            }
        }

        Divider()

        Button {
            model.moveNotes(targetIDs, inPinnedSection: pinned, toEdge: .top)
        } label: {
            Label("Move to Top", systemImage: "arrow.up.to.line")
        }
        .disabled(!model.canMoveNotesToEdge(targetIDs, inPinnedSection: pinned, edge: .top))

        Button {
            model.moveNotes(targetIDs, inPinnedSection: pinned, direction: -1)
        } label: {
            Label("Move Up", systemImage: "arrow.up")
        }
        .disabled(!model.canMoveNotes(targetIDs, inPinnedSection: pinned, direction: -1))

        Button {
            model.moveNotes(targetIDs, inPinnedSection: pinned, direction: 1)
        } label: {
            Label("Move Down", systemImage: "arrow.down")
        }
        .disabled(!model.canMoveNotes(targetIDs, inPinnedSection: pinned, direction: 1))

        Button {
            model.moveNotes(targetIDs, inPinnedSection: pinned, toEdge: .bottom)
        } label: {
            Label("Move to Bottom", systemImage: "arrow.down.to.line")
        }
        .disabled(!model.canMoveNotesToEdge(targetIDs, inPinnedSection: pinned, edge: .bottom))

        Divider()

        Button {
            model.duplicateNotes(targetIDs)
        } label: {
            Label(count == 1 ? "Duplicate Note" : "Duplicate Selected", systemImage: "plus.square.on.square")
        }

        Button {
            model.revealNotesInFinder(targetIDs)
        } label: {
            Label(count == 1 ? "Reveal in Finder" : "Reveal Selected in Finder", systemImage: "folder")
        }

        Button {
            copyTitles(targetIDs)
        } label: {
            Label(count == 1 ? "Copy Title" : "Copy Titles", systemImage: "doc.on.doc")
        }

        Button {
            copyContents(targetIDs)
        } label: {
            Label(count == 1 ? "Copy Note Contents" : "Copy Contents", systemImage: "doc.text")
        }

        Divider()

        Button(role: .destructive) {
            requestDeleteNotes(targetIDs)
        } label: {
            Label(count == 1 ? "Delete Note..." : "Delete Selected...", systemImage: "trash")
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let note = model.selectedNote {
                HStack(spacing: 8) {
                    Button {
                        toggleSidebar()
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
                        togglePreviewMode()
                    } label: {
                        Image(systemName: isPreviewing ? "eye" : "pencil")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(HeaderIconButtonStyle())
                    .help(isPreviewing ? "Edit note" : "Preview markdown")
                }
                .collapsesSelectionOnTap(model)

                Group {
                    if isPreviewing {
                        ScrollView {
                            MarkdownText(note.body)
                                .markdownCodeBlockStyle(NormalizedCodeBlockStyle())
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                        // Simultaneous, not collapsesSelectionOnTap, so tapping a Markdown link still opens it.
                        .simultaneousGesture(TapGesture().onEnded { model.collapseSelectionToPrimary() })
                    } else {
                        PlainTextEditor(
                            text: model.bodyBinding(),
                            wrapsLines: wrapLines,
                            // NSTextView eats clicks at the AppKit layer, so it collapses from its own mouseDown.
                            onInteract: { model.collapseSelectionToPrimary() }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { }  // Swallows editor taps so they don't fall through to the background collapse below.
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
            // Like collapsesSelectionOnTap, but also drops text focus when tapping around the editor.
            Color.clear.contentShape(Rectangle()).onTapGesture {
                model.collapseSelectionToPrimary()
                if !isPreviewing { resignTextFocus() }
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
                AppDelegate.shared?.openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
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
        .collapsesSelectionOnTap(model)
    }

    private func createNote() {
        isPreviewing = false
        model.createNote()
    }

    private var hasSelectedNotes: Bool {
        !model.selectedNoteIDs.isEmpty
    }

    private var selectedNotesAllPinned: Bool {
        let notes = model.selectedNotesInDisplayOrder
        return !notes.isEmpty && notes.allSatisfy(\.pinned)
    }

    private var selectionSubtitle: String {
        let count = model.selectedNoteIDs.count
        if count > 1 {
            return "\(count) notes selected"
        }
        return model.selectedNote?.title ?? "No note selected"
    }

    private func select(_ note: Note) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift) {
            model.selectRange(to: note.id)
        } else if modifiers.contains(.command) {
            model.toggleSelection(note.id)
        } else {
            model.selectOnly(note.id)
        }
    }

    private func requestDeleteSelectedNotes() {
        requestDeleteNotes(model.selectedNoteIDs)
    }

    private func requestDeleteNotes(_ noteIDs: Set<UUID>) {
        let notes = model.notesInDisplayOrder(for: noteIDs)
        guard !notes.isEmpty else { return }
        let alert = NSAlert()
        if notes.count == 1 {
            alert.messageText = "Delete note?"
            alert.informativeText = "Delete \"\(notes[0].title)\"? This cannot be undone."
        } else {
            alert.messageText = "Delete \(notes.count) notes?"
            alert.informativeText = "This cannot be undone."
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        let response = AppDelegate.shared?.panelController.withDismissSuspended {
            alert.runModal()
        } ?? alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        model.deleteNotes(noteIDs)
    }

    private func copyTitles(_ noteIDs: Set<UUID>) {
        let titles = model.notesInDisplayOrder(for: noteIDs).map(\.title)
        guard !titles.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(titles.joined(separator: "\n"), forType: .string)
    }

    private func copyContents(_ noteIDs: Set<UUID>) {
        let contents = model.notesInDisplayOrder(for: noteIDs).map(\.body)
        guard !contents.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(contents.joined(separator: "\n\n"), forType: .string)
    }

    private func pasteAsNewNote() {
        guard let text = pasteboardText else { return }
        isPreviewing = false
        model.createNote(body: text)
    }

    private var pasteboardText: String? {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return nil }
        return text
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.18)) { sidebarCollapsed.toggle() }
    }

    private func togglePreviewMode() {
        guard model.selectedNote != nil else { return }
        isPreviewing.toggle()
    }

    private var keyboardShortcuts: some View {
        Group {
            Button("New note") { createNote() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Delete selected notes") { requestDeleteSelectedNotes() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!hasSelectedNotes)
            Button("Pin selected notes") { model.togglePinSelected() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!hasSelectedNotes)
            Button("Select all notes") { model.selectAllNotes() }
                .keyboardShortcut("a", modifiers: [.command, .option])
            Button("Toggle sidebar") { toggleSidebar() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Toggle Markdown preview") { togglePreviewMode() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(model.selectedNote == nil)
            Button("Toggle soft wrap") { wrapLines.toggle() }
                .keyboardShortcut("w", modifiers: [.command, .option])
            Button("Reveal notes folder") { model.openStorageInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Next note") { cycle(1) }
                .keyboardShortcut("]", modifiers: .command)
            Button("Previous note") { cycle(-1) }
                .keyboardShortcut("[", modifiers: .command)
            ForEach(1...8, id: \.self) { n in
                Button("Jump to note \(n)") { model.selectNote(at: n - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
            Button("Jump to last note") { model.selectNote(at: model.orderedNotes.count - 1) }
                .keyboardShortcut("9", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var wrapIndicator: some View {
        if let wrapIcon {
            ZStack {
                Color.black.opacity(0.18)
                    .transition(.opacity)
                Image(systemName: wrapIcon)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 116, height: 116)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    .shadow(color: .black.opacity(0.25), radius: 22, y: 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            .allowsHitTesting(false)
        }
    }

    private func cycle(_ offset: Int) {
        guard model.selectAdjacentNote(offset: offset) else { return }
        wrapToken += 1
        let token = wrapToken
        withAnimation(.easeOut(duration: 0.15)) {
            wrapIcon = offset > 0 ? "arrow.clockwise" : "arrow.counterclockwise"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard wrapToken == token else { return }
            withAnimation(.easeIn(duration: 0.25)) { wrapIcon = nil }
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
    let primary: Bool

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
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(backgroundColor))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner).strokeBorder(borderColor, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Theme.innerCorner))
    }

    private var backgroundColor: Color {
        if primary { return Theme.accent.opacity(0.22) }
        if selected { return Theme.accent.opacity(0.1) }
        return Color.black.opacity(0.18)
    }

    private var borderColor: Color {
        if primary { return Theme.accent.opacity(0.65) }
        if selected { return Theme.accent.opacity(0.35) }
        return Color.white.opacity(0.06)
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

private extension View {
    /// Collapses a transient multi-selection back to the primary note when this region is tapped.
    /// Applied to every non-card region of the panel (header, sidebar, editor header, footer). It uses
    /// `onTapGesture` so note cards and buttons keep gesture priority — a tap collapses only when it
    /// lands on inert chrome, never stealing a card selection or a pin/delete press. The editor
    /// background additionally resigns text focus, the Markdown preview uses a simultaneous tap so
    /// links still open, and the plain-text editor collapses from its AppKit `mouseDown` hook.
    func collapsesSelectionOnTap(_ model: AppModel) -> some View {
        contentShape(Rectangle())
            .onTapGesture { model.collapseSelectionToPrimary() }
    }
}
