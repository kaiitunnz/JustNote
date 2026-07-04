import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var notes: [Note]
    @Published private(set) var selectedNoteID: UUID?
    @Published private(set) var noteOrderIDs: [UUID]
    @Published var lastError: String?

    private let store: NoteStore

    init(store: NoteStore? = nil) {
        var resolvedStore: NoteStore
        let snapshot: NotesSnapshot
        var loadError: String?
        do {
            resolvedStore = try store ?? NoteStore()
            snapshot = try resolvedStore.load()
        } catch {
            resolvedStore = try! NoteStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("JustNoteFallback"))
            snapshot = NotesSnapshot(notes: [], selectedNoteID: nil, isFresh: true)
            loadError = error.localizedDescription
        }

        self.store = resolvedStore
        notes = snapshot.notes
        selectedNoteID = snapshot.selectedNoteID
        noteOrderIDs = Self.sanitizedOrder(snapshot.noteOrderIDs, notes: snapshot.notes)
        lastError = loadError

        if notes.isEmpty && snapshot.isFresh {
            createNote()
        } else if selectedNoteID == nil {
            selectedNoteID = orderedNotes.first?.id
            save()
        }
    }

    var selectedNote: Note? {
        guard let selectedNoteID else { return nil }
        return notes.first { $0.id == selectedNoteID }
    }

    var orderedNotes: [Note] {
        pinnedNotes + unpinnedNotes
    }

    var pinnedNotes: [Note] {
        orderedNotes(pinned: true)
    }

    var unpinnedNotes: [Note] {
        orderedNotes(pinned: false)
    }

    var storagePath: String {
        store.rootURL.path
    }

    var storageURL: URL {
        store.rootURL
    }

    func createNote() {
        let now = Date()
        let note = Note(body: "", createdAt: now, updatedAt: now)
        notes.append(note)
        noteOrderIDs.insert(note.id, at: firstUnpinnedOrderIndex)
        selectedNoteID = note.id
        save()
    }

    func deleteSelectedNote() {
        guard let selectedNoteID else { return }
        deleteNote(selectedNoteID)
    }

    func deleteNote(_ noteID: UUID) {
        guard notes.contains(where: { $0.id == noteID }) else { return }
        notes.removeAll { $0.id == noteID }
        noteOrderIDs.removeAll { $0 == noteID }
        if selectedNoteID.map({ selectedID in notes.contains { $0.id == selectedID } }) != true {
            selectedNoteID = orderedNotes.first?.id
        }
        save()
    }

    func select(_ noteID: UUID) {
        guard notes.contains(where: { $0.id == noteID }) else { return }
        selectedNoteID = noteID
        save()
    }

    /// Moves the selection by `offset` through the visible order, wrapping around.
    /// Returns `true` when the move wrapped past an end (last → first or first → last).
    @discardableResult
    func selectAdjacentNote(offset: Int) -> Bool {
        let ordered = orderedNotes
        guard ordered.count > 1 else { return false }
        guard let current = selectedNoteID, let index = ordered.firstIndex(where: { $0.id == current }) else {
            select(ordered[0].id)
            return false
        }
        let target = index + offset
        let wrapped = target < 0 || target >= ordered.count
        let next = (target % ordered.count + ordered.count) % ordered.count
        select(ordered[next].id)
        return wrapped
    }

    func selectNote(at index: Int) {
        let ordered = orderedNotes
        guard ordered.indices.contains(index) else { return }
        select(ordered[index].id)
    }

    func updateSelectedBody(_ body: String) {
        guard let selectedNoteID, let index = notes.firstIndex(where: { $0.id == selectedNoteID }) else { return }
        guard notes[index].body != body else { return }
        notes[index].body = body
        notes[index].updatedAt = Date()
        save()
    }

    func togglePinSelected() {
        guard let selectedNoteID, let index = notes.firstIndex(where: { $0.id == selectedNoteID }) else { return }
        togglePin(selectedNoteID, at: index)
    }

    func togglePin(_ noteID: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        togglePin(noteID, at: index)
    }

    private func togglePin(_ noteID: UUID, at index: Int) {
        notes[index].pinned.toggle()
        notes[index].updatedAt = Date()
        noteOrderIDs.removeAll { $0 == noteID }
        if notes[index].pinned {
            noteOrderIDs.insert(noteID, at: 0)
        } else {
            noteOrderIDs.insert(noteID, at: firstUnpinnedOrderIndex)
        }
        save()
    }

    func movePinnedNote(_ noteID: UUID, direction: Int) {
        guard let index = pinnedNotes.firstIndex(where: { $0.id == noteID }) else { return }
        moveNote(noteID, inPinnedSection: true, toIndex: index + direction)
    }

    func moveUnpinnedNote(_ noteID: UUID, direction: Int) {
        guard let index = unpinnedNotes.firstIndex(where: { $0.id == noteID }) else { return }
        moveNote(noteID, inPinnedSection: false, toIndex: index + direction)
    }

    func canMovePinnedNote(_ noteID: UUID, direction: Int) -> Bool {
        canMove(noteID, in: pinnedNotes, direction: direction)
    }

    func canMoveUnpinnedNote(_ noteID: UUID, direction: Int) -> Bool {
        canMove(noteID, in: unpinnedNotes, direction: direction)
    }

    func moveNote(_ noteID: UUID, inPinnedSection pinned: Bool, toIndex requestedIndex: Int) {
        var sectionIDs = (pinned ? pinnedNotes : unpinnedNotes).map(\.id)
        guard let currentIndex = sectionIDs.firstIndex(of: noteID) else { return }

        let targetIndex = min(max(requestedIndex, 0), sectionIDs.count - 1)
        guard currentIndex != targetIndex else { return }

        sectionIDs.remove(at: currentIndex)
        sectionIDs.insert(noteID, at: targetIndex)
        rebuildOrder(sectionIDs: sectionIDs, pinned: pinned)
        save()
    }

    func openStorageInFinder() {
        do {
            try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
            if NSWorkspace.shared.open(storageURL) {
                lastError = nil
            } else {
                lastError = "Open folder failed: Finder could not open \(storagePath)"
            }
        } catch {
            lastError = "Open folder failed: \(error.localizedDescription)"
        }
    }

    func revealNoteInFinder(_ noteID: UUID) {
        guard let note = notes.first(where: { $0.id == noteID }) else { return }
        let noteURL = store.noteBodyURL(for: note)
        guard FileManager.default.fileExists(atPath: noteURL.path) else {
            lastError = "Reveal note failed: \(noteURL.lastPathComponent) does not exist"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([noteURL])
        lastError = nil
    }

    func uninstallAndQuit() {
        do {
            try store.removeAll()
            lastError = nil
        } catch {
            lastError = "Uninstall failed: \(error.localizedDescription)"
            return
        }

        let appURL = Bundle.main.bundleURL
        if appURL.pathExtension == "app" {
            NSWorkspace.shared.recycle([appURL]) { _, _ in
                DispatchQueue.main.async {
                    AppDelegate.shared?.isQuitting = true
                    NSApplication.shared.terminate(nil)
                }
            }
        } else {
            AppDelegate.shared?.isQuitting = true
            NSApplication.shared.terminate(nil)
        }
    }

    func bodyBinding() -> Binding<String> {
        Binding(
            get: { self.selectedNote?.body ?? "" },
            set: { self.updateSelectedBody($0) }
        )
    }

    private func orderedNotes(pinned: Bool) -> [Note] {
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        return noteOrderIDs.compactMap { byID[$0] }.filter { $0.pinned == pinned }
    }

    private var firstUnpinnedOrderIndex: Int {
        let pinnedIDs = Set(notes.filter(\.pinned).map(\.id))
        return noteOrderIDs.firstIndex { !pinnedIDs.contains($0) } ?? noteOrderIDs.count
    }

    private func rebuildOrder(sectionIDs: [UUID], pinned: Bool) {
        let otherIDs = (pinned ? unpinnedNotes : pinnedNotes).map(\.id)
        noteOrderIDs = pinned ? sectionIDs + otherIDs : otherIDs + sectionIDs
    }

    private func canMove(_ noteID: UUID, in section: [Note], direction: Int) -> Bool {
        guard let index = section.firstIndex(where: { $0.id == noteID }) else { return false }
        return section.indices.contains(index + direction)
    }

    private func save() {
        do {
            try store.save(NotesSnapshot(notes: notes, selectedNoteID: selectedNoteID, noteOrderIDs: noteOrderIDs))
            lastError = nil
        } catch {
            lastError = "Save failed: \(error.localizedDescription)"
        }
    }

    private static func sanitizedOrder(_ order: [UUID], notes: [Note]) -> [UUID] {
        if order.isEmpty {
            return notes
                .sorted { lhs, rhs in
                    if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
                    if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                    return lhs.createdAt > rhs.createdAt
                }
                .map(\.id)
        }
        let noteIDs = Set(notes.map(\.id))
        var seen: Set<UUID> = []
        var result = order.filter { id in
            noteIDs.contains(id) && seen.insert(id).inserted
        }
        result.append(contentsOf: notes.map(\.id).filter { !seen.contains($0) })
        return result
    }
}
