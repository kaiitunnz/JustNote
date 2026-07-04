import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var notes: [Note]
    @Published private(set) var selectedNoteID: UUID?
    @Published private(set) var recentNoteIDs: [UUID]
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
            snapshot = NotesSnapshot(notes: [], selectedNoteID: nil, recentNoteIDs: [])
            loadError = error.localizedDescription
        }

        self.store = resolvedStore
        notes = snapshot.notes
        selectedNoteID = snapshot.selectedNoteID
        recentNoteIDs = snapshot.recentNoteIDs
        lastError = loadError

        if notes.isEmpty {
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
        notes.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.createdAt > rhs.createdAt
        }
    }

    var recentNotes: [Note] {
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        return recentNoteIDs.compactMap { byID[$0] }
    }

    var storagePath: String {
        store.rootURL.path
    }

    func createNote() {
        let now = Date()
        let note = Note(body: "", createdAt: now, updatedAt: now)
        notes.append(note)
        selectedNoteID = note.id
        touchRecent(note.id)
        save()
    }

    func deleteSelectedNote() {
        guard let selectedNoteID else { return }
        notes.removeAll { $0.id == selectedNoteID }
        recentNoteIDs.removeAll { $0 == selectedNoteID }
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
        save()
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

    private func save() {
        do {
            try store.save(NotesSnapshot(notes: notes, selectedNoteID: selectedNoteID, recentNoteIDs: recentNoteIDs))
            lastError = nil
        } catch {
            lastError = "Save failed: \(error.localizedDescription)"
        }
    }
}
