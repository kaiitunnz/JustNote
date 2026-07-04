import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var notes: [Note]
    @Published private(set) var selectedNoteID: UUID?
    @Published private(set) var recentNoteIDs: [UUID]
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
            snapshot = NotesSnapshot(notes: [], selectedNoteID: nil, recentNoteIDs: [], isFresh: true)
            loadError = error.localizedDescription
        }

        self.store = resolvedStore
        notes = snapshot.notes
        selectedNoteID = snapshot.selectedNoteID
        recentNoteIDs = snapshot.recentNoteIDs
        noteOrderIDs = Self.sanitizedOrder(snapshot.noteOrderIDs, notes: snapshot.notes)
        lastError = loadError

        if notes.isEmpty && snapshot.isFresh {
            createNote()
        } else if selectedNoteID == nil {
            selectedNoteID = orderedNotes.first?.id
            if let selectedNoteID { touchRecent(selectedNoteID) }
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

    var recentNotes: [Note] {
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        return recentNoteIDs.compactMap { byID[$0] }
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
        touchRecent(note.id)
        save()
    }

    func deleteSelectedNote() {
        guard let selectedNoteID else { return }
        notes.removeAll { $0.id == selectedNoteID }
        recentNoteIDs.removeAll { $0 == selectedNoteID }
        noteOrderIDs.removeAll { $0 == selectedNoteID }
        self.selectedNoteID = orderedNotes.first?.id
        if let next = self.selectedNoteID {
            touchRecent(next)
        }
        save()
    }

    func select(_ noteID: UUID) {
        guard notes.contains(where: { $0.id == noteID }) else { return }
        selectedNoteID = noteID
        touchRecent(noteID)
        save()
    }

    func updateSelectedBody(_ body: String) {
        guard let selectedNoteID, let index = notes.firstIndex(where: { $0.id == selectedNoteID }) else { return }
        guard notes[index].body != body else { return }
        notes[index].body = body
        notes[index].updatedAt = Date()
        touchRecent(selectedNoteID)
        save()
    }

    func togglePinSelected() {
        guard let selectedNoteID, let index = notes.firstIndex(where: { $0.id == selectedNoteID }) else { return }
        notes[index].pinned.toggle()
        notes[index].updatedAt = Date()
        noteOrderIDs.removeAll { $0 == selectedNoteID }
        if notes[index].pinned {
            noteOrderIDs.insert(selectedNoteID, at: 0)
        } else {
            noteOrderIDs.insert(selectedNoteID, at: firstUnpinnedOrderIndex)
        }
        save()
    }

    func movePinnedNote(_ noteID: UUID, direction: Int) {
        move(noteID, inPinnedSection: true, direction: direction)
    }

    func moveUnpinnedNote(_ noteID: UUID, direction: Int) {
        move(noteID, inPinnedSection: false, direction: direction)
    }

    func canMovePinnedNote(_ noteID: UUID, direction: Int) -> Bool {
        canMove(noteID, in: pinnedNotes, direction: direction)
    }

    func canMoveUnpinnedNote(_ noteID: UUID, direction: Int) -> Bool {
        canMove(noteID, in: unpinnedNotes, direction: direction)
    }

    func openStorageInFinder() {
        do {
            try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([storageURL])
            lastError = nil
        } catch {
            lastError = "Open folder failed: \(error.localizedDescription)"
        }
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

    private func touchRecent(_ noteID: UUID) {
        recentNoteIDs.removeAll { $0 == noteID }
        recentNoteIDs.insert(noteID, at: 0)
        let validIDs = Set(notes.map(\.id))
        recentNoteIDs = Array(recentNoteIDs.filter { validIDs.contains($0) }.prefix(8))
    }

    private func orderedNotes(pinned: Bool) -> [Note] {
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        return noteOrderIDs.compactMap { byID[$0] }.filter { $0.pinned == pinned }
    }

    private var firstUnpinnedOrderIndex: Int {
        let pinnedIDs = Set(notes.filter(\.pinned).map(\.id))
        return noteOrderIDs.firstIndex { !pinnedIDs.contains($0) } ?? noteOrderIDs.count
    }

    private func move(_ noteID: UUID, inPinnedSection pinned: Bool, direction: Int) {
        var sectionIDs = (pinned ? pinnedNotes : unpinnedNotes).map(\.id)
        guard let index = sectionIDs.firstIndex(of: noteID) else { return }
        let newIndex = index + direction
        guard sectionIDs.indices.contains(newIndex) else { return }
        sectionIDs.swapAt(index, newIndex)
        let otherIDs = (pinned ? unpinnedNotes : pinnedNotes).map(\.id)
        noteOrderIDs = pinned ? sectionIDs + otherIDs : otherIDs + sectionIDs
        save()
    }

    private func canMove(_ noteID: UUID, in section: [Note], direction: Int) -> Bool {
        guard let index = section.firstIndex(where: { $0.id == noteID }) else { return false }
        return section.indices.contains(index + direction)
    }

    private func save() {
        do {
            try store.save(NotesSnapshot(notes: notes, selectedNoteID: selectedNoteID, recentNoteIDs: recentNoteIDs, noteOrderIDs: noteOrderIDs))
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
