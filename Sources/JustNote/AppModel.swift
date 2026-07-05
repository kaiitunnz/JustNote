import AppKit
import Foundation
import SwiftUI

enum NoteSectionEdge {
    case top
    case bottom
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var notes: [Note]
    @Published private(set) var selectedNoteID: UUID?
    @Published private(set) var selectedNoteIDs: Set<UUID>
    @Published private(set) var noteOrderIDs: [UUID]
    @Published var lastError: String?

    private let store: NoteStore
    private var selectionAnchorID: UUID?

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
        selectedNoteIDs = snapshot.selectedNoteID.map { [$0] } ?? []
        selectionAnchorID = snapshot.selectedNoteID
        noteOrderIDs = Self.sanitizedOrder(snapshot.noteOrderIDs, notes: snapshot.notes)
        lastError = loadError

        if notes.isEmpty && snapshot.isFresh {
            createNote()
        } else if selectedNoteID == nil {
            selectedNoteID = orderedNotes.first?.id
            selectedNoteIDs = selectedNoteID.map { [$0] } ?? []
            selectionAnchorID = selectedNoteID
            save()
        } else {
            cleanupSelection()
        }
    }

    var selectedNote: Note? {
        guard let selectedNoteID else { return nil }
        return notes.first { $0.id == selectedNoteID }
    }

    var selectedNotesInDisplayOrder: [Note] {
        notesInDisplayOrder(for: selectedNoteIDs)
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

    func createNote(body: String = "") {
        let now = Date()
        let note = Note(body: body, createdAt: now, updatedAt: now)
        notes.append(note)
        noteOrderIDs.insert(note.id, at: firstUnpinnedOrderIndex)
        setPrimarySelection(note.id, selectedIDs: [note.id], anchorID: note.id)
        save()
    }

    func duplicateNote(_ noteID: UUID) {
        duplicateNotes([noteID])
    }

    func duplicateNotes(_ noteIDs: Set<UUID>) {
        let originals = notesInDisplayOrder(for: noteIDs)
        guard !originals.isEmpty else { return }
        let now = Date()
        let duplicates = originals.map { Note(body: $0.body, createdAt: now, updatedAt: now) }
        notes.append(contentsOf: duplicates)
        let duplicateIDs = duplicates.map(\.id)
        noteOrderIDs.insert(contentsOf: duplicateIDs, at: firstUnpinnedOrderIndex)
        if let primaryID = duplicateIDs.last {
            setPrimarySelection(primaryID, selectedIDs: Set(duplicateIDs), anchorID: primaryID)
        }
        save()
    }

    func deleteSelectedNote() {
        deleteNotes(activeSelectionIDs)
    }

    func deleteNote(_ noteID: UUID) {
        deleteNotes([noteID])
    }

    func deleteNotes(_ noteIDs: Set<UUID>) {
        let noteIDs = noteIDs.intersection(notes.map(\.id))
        guard !noteIDs.isEmpty else { return }

        let originalOrder = orderedNotes.map(\.id)
        let deletedIndices = originalOrder.indices.filter { noteIDs.contains(originalOrder[$0]) }
        notes.removeAll { noteIDs.contains($0.id) }
        noteOrderIDs.removeAll { noteIDs.contains($0) }

        if let selectedNoteID, notes.contains(where: { $0.id == selectedNoteID }) {
            let survivingSelection = selectedNoteIDs
                .subtracting(noteIDs)
                .intersection(notes.map(\.id))
            setPrimarySelection(selectedNoteID, selectedIDs: survivingSelection.union([selectedNoteID]), anchorID: selectedNoteID)
        } else {
            let nextSelection = replacementSelection(afterDeletingIndices: deletedIndices)
            setPrimarySelection(nextSelection, selectedIDs: nextSelection.map { [$0] } ?? [], anchorID: nextSelection)
        }
        save()
    }

    func select(_ noteID: UUID) {
        selectOnly(noteID)
    }

    func selectOnly(_ noteID: UUID) {
        guard notes.contains(where: { $0.id == noteID }) else { return }
        setPrimarySelection(noteID, selectedIDs: [noteID], anchorID: noteID)
        save()
    }

    func toggleSelection(_ noteID: UUID) {
        guard notes.contains(where: { $0.id == noteID }) else { return }
        if selectedNoteIDs.contains(noteID) {
            guard noteID != selectedNoteID, selectedNoteIDs.count > 1 else {
                setPrimarySelection(noteID, selectedIDs: selectedNoteIDs.union([noteID]), anchorID: noteID)
                save()
                return
            }
            selectedNoteIDs.remove(noteID)
            selectionAnchorID = selectedNoteID
        } else {
            selectedNoteIDs.insert(noteID)
            selectedNoteID = noteID
            selectionAnchorID = noteID
        }
        cleanupSelection()
        save()
    }

    func selectRange(to noteID: UUID) {
        let orderedIDs = orderedNotes.map(\.id)
        guard
            let targetIndex = orderedIDs.firstIndex(of: noteID),
            let anchorID = validAnchorID(fallback: noteID),
            let anchorIndex = orderedIDs.firstIndex(of: anchorID)
        else { return }

        let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        setPrimarySelection(noteID, selectedIDs: Set(orderedIDs[bounds]), anchorID: anchorID)
        save()
    }

    func selectAllNotes() {
        let orderedIDs = orderedNotes.map(\.id)
        guard !orderedIDs.isEmpty else {
            setPrimarySelection(nil, selectedIDs: [], anchorID: nil)
            save()
            return
        }
        let primaryID = selectedNoteID.flatMap { orderedIDs.contains($0) ? $0 : nil } ?? orderedIDs[0]
        setPrimarySelection(primaryID, selectedIDs: Set(orderedIDs), anchorID: primaryID)
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
        let targets = activeSelectionIDs
        guard !targets.isEmpty else { return }
        let targetNotes = notesInDisplayOrder(for: targets)
        let shouldPin = !targetNotes.allSatisfy(\.pinned)
        setPinned(targets, pinned: shouldPin)
    }

    func togglePin(_ noteID: UUID) {
        guard let note = notes.first(where: { $0.id == noteID }) else { return }
        setPinned([noteID], pinned: !note.pinned)
    }

    func setPinned(_ noteIDs: Set<UUID>, pinned: Bool) {
        let targetIDs = notesInDisplayOrder(for: noteIDs).map(\.id)
        guard !targetIDs.isEmpty else { return }
        let targetSet = Set(targetIDs)
        let now = Date()
        for index in notes.indices where targetSet.contains(notes[index].id) && notes[index].pinned != pinned {
            notes[index].pinned = pinned
            notes[index].updatedAt = now
        }
        rebuildOrder(moving: targetIDs, pinned: pinned)
        cleanupSelection()
        save()
    }

    func movePinnedNote(_ noteID: UUID, direction: Int) {
        moveNotes([noteID], inPinnedSection: true, direction: direction)
    }

    func moveUnpinnedNote(_ noteID: UUID, direction: Int) {
        moveNotes([noteID], inPinnedSection: false, direction: direction)
    }

    func moveNote(_ noteID: UUID, inPinnedSection pinned: Bool, toIndex requestedIndex: Int) {
        moveNotes([noteID], inPinnedSection: pinned, toIndex: requestedIndex)
    }

    func moveNotes(_ noteIDs: Set<UUID>, inPinnedSection pinned: Bool, direction: Int) {
        let section = pinned ? pinnedNotes : unpinnedNotes
        guard let range = contiguousRange(for: noteIDs, in: section), canMove(range: range, in: section, direction: direction) else {
            return
        }
        moveNotes(noteIDs, inPinnedSection: pinned, toIndex: range.lowerBound + direction)
    }

    func canMoveNotes(_ noteIDs: Set<UUID>, inPinnedSection pinned: Bool, direction: Int) -> Bool {
        let section = pinned ? pinnedNotes : unpinnedNotes
        guard let range = contiguousRange(for: noteIDs, in: section) else { return false }
        return canMove(range: range, in: section, direction: direction)
    }

    func canMoveNotesToEdge(_ noteIDs: Set<UUID>, inPinnedSection pinned: Bool, edge: NoteSectionEdge) -> Bool {
        let section = pinned ? pinnedNotes : unpinnedNotes
        guard let range = contiguousRange(for: noteIDs, in: section) else { return false }
        switch edge {
        case .top:
            return range.lowerBound > 0
        case .bottom:
            return range.upperBound < section.count - 1
        }
    }

    func moveNotes(_ noteIDs: Set<UUID>, inPinnedSection pinned: Bool, toEdge edge: NoteSectionEdge) {
        let section = pinned ? pinnedNotes : unpinnedNotes
        guard canMoveNotesToEdge(noteIDs, inPinnedSection: pinned, edge: edge) else { return }
        switch edge {
        case .top:
            moveNotes(noteIDs, inPinnedSection: pinned, toIndex: 0)
        case .bottom:
            moveNotes(noteIDs, inPinnedSection: pinned, toIndex: section.count - 1)
        }
    }

    func moveNotes(_ noteIDs: Set<UUID>, inPinnedSection pinned: Bool, toIndex requestedIndex: Int) {
        var sectionIDs = (pinned ? pinnedNotes : unpinnedNotes).map(\.id)
        let targetIDs = sectionIDs.filter { noteIDs.contains($0) }
        guard
            targetIDs.count == noteIDs.count,
            let range = contiguousRange(for: noteIDs, in: pinned ? pinnedNotes : unpinnedNotes)
        else { return }

        let targetIndex = min(max(requestedIndex, 0), sectionIDs.count - targetIDs.count)
        guard range.lowerBound != targetIndex else { return }

        sectionIDs.removeAll { noteIDs.contains($0) }
        sectionIDs.insert(contentsOf: targetIDs, at: targetIndex)
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
        revealNotesInFinder([noteID])
    }

    func revealNotesInFinder(_ noteIDs: Set<UUID>) {
        let noteURLs = notesInDisplayOrder(for: noteIDs).map { store.noteBodyURL(for: $0) }
        guard !noteURLs.isEmpty else { return }
        let missingURL = noteURLs.first { !FileManager.default.fileExists(atPath: $0.path) }
        guard missingURL == nil else {
            lastError = "Reveal note failed: \(missingURL!.lastPathComponent) does not exist"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(noteURLs)
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

    func notesInDisplayOrder(for noteIDs: Set<UUID>) -> [Note] {
        guard !noteIDs.isEmpty else { return [] }
        return orderedNotes.filter { noteIDs.contains($0.id) }
    }

    func actionTargetIDs(containing noteID: UUID) -> Set<UUID> {
        selectedNoteIDs.contains(noteID) ? selectedNoteIDs : [noteID]
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

    private func rebuildOrder(moving targetIDs: [UUID], pinned: Bool) {
        let targetSet = Set(targetIDs)
        let currentPinnedIDs = orderedNotes.filter(\.pinned).map(\.id).filter { !targetSet.contains($0) }
        let currentUnpinnedIDs = orderedNotes.filter { !$0.pinned }.map(\.id).filter { !targetSet.contains($0) }
        if pinned {
            noteOrderIDs = targetIDs + currentPinnedIDs + currentUnpinnedIDs
        } else {
            noteOrderIDs = currentPinnedIDs + targetIDs + currentUnpinnedIDs
        }
    }

    private func contiguousRange(for noteIDs: Set<UUID>, in section: [Note]) -> ClosedRange<Int>? {
        guard !noteIDs.isEmpty else { return nil }
        let indices = section.indices.filter { noteIDs.contains(section[$0].id) }
        guard indices.count == noteIDs.count, let first = indices.first, let last = indices.last else { return nil }
        guard last - first + 1 == indices.count else { return nil }
        return first...last
    }

    private func canMove(range: ClosedRange<Int>, in section: [Note], direction: Int) -> Bool {
        if direction < 0 {
            return range.lowerBound > section.startIndex
        }
        if direction > 0 {
            return range.upperBound < section.index(before: section.endIndex)
        }
        return false
    }

    private var activeSelectionIDs: Set<UUID> {
        if !selectedNoteIDs.isEmpty { return selectedNoteIDs }
        return selectedNoteID.map { [$0] } ?? []
    }

    private func setPrimarySelection(_ noteID: UUID?, selectedIDs: Set<UUID>, anchorID: UUID?) {
        selectedNoteID = noteID
        if let noteID {
            selectedNoteIDs = selectedIDs.union([noteID])
        } else {
            selectedNoteIDs = []
        }
        selectionAnchorID = anchorID
        cleanupSelection()
    }

    private func cleanupSelection() {
        let noteIDs = Set(notes.map(\.id))
        if selectedNoteID.map({ !noteIDs.contains($0) }) ?? false {
            selectedNoteID = orderedNotes.first?.id
        }
        selectedNoteIDs = selectedNoteIDs.intersection(noteIDs)
        if let selectedNoteID {
            selectedNoteIDs.insert(selectedNoteID)
        } else {
            selectedNoteIDs = []
        }
        if selectionAnchorID.map({ !noteIDs.contains($0) }) ?? false {
            selectionAnchorID = selectedNoteID
        }
    }

    private func validAnchorID(fallback: UUID) -> UUID? {
        if let selectionAnchorID, notes.contains(where: { $0.id == selectionAnchorID }) {
            return selectionAnchorID
        }
        if let selectedNoteID, notes.contains(where: { $0.id == selectedNoteID }) {
            return selectedNoteID
        }
        return notes.contains(where: { $0.id == fallback }) ? fallback : nil
    }

    private func replacementSelection(afterDeletingIndices deletedIndices: [Int]) -> UUID? {
        let newOrder = orderedNotes.map(\.id)
        guard !newOrder.isEmpty else { return nil }
        let firstDeletedIndex = deletedIndices.min() ?? 0
        if newOrder.indices.contains(firstDeletedIndex) {
            return newOrder[firstDeletedIndex]
        }
        let previousIndex = firstDeletedIndex - 1
        if newOrder.indices.contains(previousIndex) {
            return newOrder[previousIndex]
        }
        return newOrder[0]
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
