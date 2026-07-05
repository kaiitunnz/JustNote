import XCTest
@testable import JustNote

@MainActor
final class JustNoteTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("JustNoteTests")
            .appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    func testModelCreatesFirstNoteOnEmptyStore() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))

        XCTAssertEqual(model.notes.count, 1)
        XCTAssertNotNil(model.selectedNoteID)
        XCTAssertEqual(model.selectedNote?.title, "Untitled")
    }

    func testBodyUpdateAutosavesPlainTextAndDerivedTitle() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let id = try XCTUnwrap(model.selectedNoteID)

        model.updateSelectedBody("Meeting notes\n- ship JustNote")

        let bodyURL = rootURL.appendingPathComponent("Notes").appendingPathComponent("\(id.uuidString).txt")
        XCTAssertEqual(try String(contentsOf: bodyURL, encoding: .utf8), "Meeting notes\n- ship JustNote")

        let reloaded = AppModel(store: try NoteStore(rootURL: rootURL))
        XCTAssertEqual(reloaded.selectedNote?.title, "Meeting notes")
        XCTAssertEqual(reloaded.selectedNote?.body, "Meeting notes\n- ship JustNote")
    }

    func testCreateNoteCanSeedInitialBody() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))

        model.createNote(body: "Pasted note\nfrom clipboard")

        let id = try XCTUnwrap(model.selectedNoteID)
        let bodyURL = rootURL.appendingPathComponent("Notes").appendingPathComponent("\(id.uuidString).txt")
        XCTAssertEqual(model.selectedNote?.body, "Pasted note\nfrom clipboard")
        XCTAssertEqual(try String(contentsOf: bodyURL, encoding: .utf8), "Pasted note\nfrom clipboard")
    }

    func testTitleStripsLeadingMarkdownHeader() {
        XCTAssertEqual(Note.title(from: "# My Note"), "My Note")
        XCTAssertEqual(Note.title(from: "###  Spaced"), "Spaced")
        XCTAssertEqual(Note.title(from: "\n\n## Second line header"), "Second line header")
        XCTAssertEqual(Note.title(from: "#NoSpace"), "#NoSpace")
        XCTAssertEqual(Note.title(from: "####### TooMany"), "####### TooMany")
        XCTAssertEqual(Note.title(from: "###"), "###")
        XCTAssertEqual(Note.title(from: "#   "), "#")
        XCTAssertEqual(Note.title(from: "Plain title"), "Plain title")
    }

    func testSelectAdjacentNoteWrapsAround() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        model.createNote()
        model.createNote()
        let order = model.orderedNotes.map(\.id)
        XCTAssertEqual(order.count, 3)

        model.select(order[0])
        XCTAssertFalse(model.selectAdjacentNote(offset: 1))
        XCTAssertEqual(model.selectedNoteID, order[1])
        XCTAssertFalse(model.selectAdjacentNote(offset: 1))
        XCTAssertEqual(model.selectedNoteID, order[2])
        XCTAssertTrue(model.selectAdjacentNote(offset: 1))
        XCTAssertEqual(model.selectedNoteID, order[0])

        XCTAssertTrue(model.selectAdjacentNote(offset: -1))
        XCTAssertEqual(model.selectedNoteID, order[2])
    }

    func testSelectNoteByIndex() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        model.createNote()
        model.createNote()
        let order = model.orderedNotes.map(\.id)
        XCTAssertEqual(order.count, 3)

        model.selectNote(at: 1)
        XCTAssertEqual(model.selectedNoteID, order[1])
        model.selectNote(at: 0)
        XCTAssertEqual(model.selectedNoteID, order[0])

        model.selectNote(at: 99)
        XCTAssertEqual(model.selectedNoteID, order[0])
        model.selectNote(at: -1)
        XCTAssertEqual(model.selectedNoteID, order[0])
    }

    func testMultiSelectionToggleRangeAndSelectAll() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        model.createNote()
        model.createNote()
        let order = model.orderedNotes.map(\.id)

        model.selectOnly(order[0])
        XCTAssertEqual(model.selectedNoteIDs, [order[0]])

        model.toggleSelection(order[1])
        XCTAssertEqual(model.selectedNoteID, order[1])
        XCTAssertEqual(model.selectedNoteIDs, [order[0], order[1]])

        model.toggleSelection(order[0])
        XCTAssertEqual(model.selectedNoteID, order[1])
        XCTAssertEqual(model.selectedNoteIDs, [order[1]])

        model.selectOnly(order[0])
        model.selectRange(to: order[2])
        XCTAssertEqual(model.selectedNoteID, order[2])
        XCTAssertEqual(model.selectedNoteIDs, Set(order))

        model.selectOnly(order[1])
        model.selectAllNotes()
        XCTAssertEqual(model.selectedNoteID, order[1])
        XCTAssertEqual(model.selectedNoteIDs, Set(order))
    }

    func testSelectAdjacentNoteIsNoOpWithSingleNote() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        XCTAssertEqual(model.orderedNotes.count, 1)
        let only = model.selectedNoteID

        XCTAssertFalse(model.selectAdjacentNote(offset: 1))
        XCTAssertFalse(model.selectAdjacentNote(offset: -1))
        XCTAssertEqual(model.selectedNoteID, only)
    }

    func testPinningPersistsAndSortsPinnedFirst() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let firstID = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("First")
        model.createNote()
        let secondID = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("Second")
        model.select(firstID)
        model.togglePinSelected()

        XCTAssertEqual(model.orderedNotes.first?.id, firstID)

        let reloaded = AppModel(store: try NoteStore(rootURL: rootURL))
        XCTAssertEqual(reloaded.orderedNotes.first?.id, firstID)
        XCTAssertTrue(try XCTUnwrap(reloaded.notes.first { $0.id == firstID }).pinned)
        XCTAssertEqual(reloaded.notes.count, 2)
        XCTAssertNotEqual(firstID, secondID)
    }

    func testTogglePinTargetsSpecificNoteWithoutChangingSelection() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let firstID = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("First")
        model.createNote()
        let secondID = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("Second")

        model.togglePin(firstID)

        XCTAssertEqual(model.selectedNoteID, secondID)
        XCTAssertTrue(try XCTUnwrap(model.notes.first { $0.id == firstID }).pinned)
        XCTAssertFalse(try XCTUnwrap(model.notes.first { $0.id == secondID }).pinned)
        XCTAssertEqual(model.pinnedNotes.map(\.id), [firstID])
    }

    func testDuplicateNoteCopiesBodyIntoSelectedUnpinnedNote() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let originalID = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("Template\n- keep this")
        model.togglePin(originalID)

        model.duplicateNote(originalID)

        let duplicate = try XCTUnwrap(model.selectedNote)
        XCTAssertNotEqual(duplicate.id, originalID)
        XCTAssertEqual(duplicate.body, "Template\n- keep this")
        XCTAssertFalse(duplicate.pinned)
        XCTAssertEqual(model.pinnedNotes.map(\.id), [originalID])
        XCTAssertEqual(model.unpinnedNotes.map(\.id), [duplicate.id])
    }

    func testDuplicateNoteCopiesSpecificNonSelectedNote() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let firstID = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("Template\n- keep this")
        model.createNote()
        let secondID = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("Second")

        model.duplicateNote(firstID)

        let duplicate = try XCTUnwrap(model.selectedNote)
        XCTAssertNotEqual(duplicate.id, firstID)
        XCTAssertNotEqual(duplicate.id, secondID)
        XCTAssertEqual(duplicate.body, "Template\n- keep this")
        XCTAssertEqual(try XCTUnwrap(model.notes.first { $0.id == secondID }).body, "Second")
    }

    func testMovingNotesPersistsWithinPinnedAndUnpinnedSections() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let firstID = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("First")
        model.createNote()
        let secondID = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("Second")
        model.createNote()
        let thirdID = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("Third")

        XCTAssertEqual(model.unpinnedNotes.map(\.id), [thirdID, secondID, firstID])

        model.moveUnpinnedNote(firstID, direction: -1)
        XCTAssertEqual(model.unpinnedNotes.map(\.id), [thirdID, firstID, secondID])

        model.moveNote(thirdID, inPinnedSection: false, toIndex: 2)
        XCTAssertEqual(model.unpinnedNotes.map(\.id), [firstID, secondID, thirdID])

        model.select(firstID)
        model.togglePinSelected()
        model.select(secondID)
        model.togglePinSelected()
        XCTAssertEqual(model.pinnedNotes.map(\.id), [secondID, firstID])
        XCTAssertEqual(model.unpinnedNotes.map(\.id), [thirdID])

        model.movePinnedNote(firstID, direction: -1)
        XCTAssertEqual(model.pinnedNotes.map(\.id), [firstID, secondID])
        XCTAssertEqual(model.unpinnedNotes.map(\.id), [thirdID])

        let reloaded = AppModel(store: try NoteStore(rootURL: rootURL))
        XCTAssertEqual(reloaded.pinnedNotes.map(\.id), [firstID, secondID])
        XCTAssertEqual(reloaded.unpinnedNotes.map(\.id), [thirdID])
    }

    func testDeletingSpecificNonSelectedNoteKeepsCurrentSelection() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let firstID = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("First")
        model.createNote()
        let secondID = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("Second")

        model.deleteNote(firstID)

        XCTAssertEqual(model.notes.map(\.id), [secondID])
        XCTAssertEqual(model.selectedNoteID, secondID)
        let firstBodyURL = rootURL.appendingPathComponent("Notes").appendingPathComponent("\(firstID.uuidString).txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstBodyURL.path))
    }

    func testDeletingSelectedNotesChoosesNextVisibleFallback() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        model.updateSelectedBody("First")
        model.createNote()
        model.updateSelectedBody("Second")
        model.createNote()
        model.updateSelectedBody("Third")
        model.createNote()
        model.updateSelectedBody("Fourth")
        let order = model.orderedNotes.map(\.id)
        XCTAssertEqual(model.unpinnedNotes.map(\.title), ["Fourth", "Third", "Second", "First"])

        model.selectOnly(order[1])
        model.toggleSelection(order[2])
        model.deleteSelectedNote()

        XCTAssertEqual(model.orderedNotes.map(\.id), [order[0], order[3]])
        XCTAssertEqual(model.selectedNoteID, order[3])
        XCTAssertEqual(model.selectedNoteIDs, [order[3]])
    }

    func testDeletingSelectedNoteLeavesValidSelectionOrEmptyState() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let firstID = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("First")
        model.createNote()
        let secondID = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("Second")

        let notesURL = rootURL.appendingPathComponent("Notes")
        let firstBodyURL = notesURL.appendingPathComponent("\(firstID.uuidString).txt")
        let secondBodyURL = notesURL.appendingPathComponent("\(secondID.uuidString).txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstBodyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondBodyURL.path))

        model.deleteSelectedNote()

        XCTAssertEqual(model.notes.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondBodyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstBodyURL.path))
        XCTAssertTrue(model.selectedNoteID.map { id in model.notes.contains { $0.id == id } } ?? false)

        model.deleteSelectedNote()

        XCTAssertTrue(model.notes.isEmpty)
        XCTAssertNil(model.selectedNoteID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstBodyURL.path))

        let reloaded = AppModel(store: try NoteStore(rootURL: rootURL))
        XCTAssertTrue(reloaded.notes.isEmpty)
        XCTAssertNil(reloaded.selectedNoteID)
    }

    func testBatchPinningPreservesVisibleOrderAtDestinationTop() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let firstID = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("First")
        model.createNote()
        let secondID = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("Second")
        model.createNote()
        let thirdID = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("Third")

        model.setPinned([firstID, thirdID], pinned: true)

        XCTAssertEqual(model.pinnedNotes.map(\.id), [thirdID, firstID])
        XCTAssertEqual(model.unpinnedNotes.map(\.id), [secondID])

        model.setPinned([firstID, thirdID], pinned: false)

        XCTAssertEqual(model.pinnedNotes.map(\.id), [])
        XCTAssertEqual(model.unpinnedNotes.map(\.id), [thirdID, firstID, secondID])
    }

    func testBatchDuplicatePreservesVisibleOrderAndSelectsDuplicates() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let firstID = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("First")
        model.createNote()
        let secondID = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("Second")
        model.createNote()
        let thirdID = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("Third")

        model.duplicateNotes([firstID, thirdID])

        let unpinned = model.unpinnedNotes
        XCTAssertEqual(unpinned.map(\.body), ["Third", "First", "Third", "Second", "First"])
        XCTAssertEqual(Set(unpinned.prefix(2).map(\.id)), model.selectedNoteIDs)
        XCTAssertEqual(model.selectedNoteID, unpinned[1].id)
        XCTAssertNotEqual(unpinned[0].id, thirdID)
        XCTAssertNotEqual(unpinned[1].id, firstID)
        XCTAssertEqual(secondID, unpinned[3].id)
    }

    func testBatchMoveRequiresContiguousSameSectionSelection() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        model.updateSelectedBody("First")
        model.createNote()
        model.updateSelectedBody("Second")
        model.createNote()
        model.updateSelectedBody("Third")
        model.createNote()
        model.updateSelectedBody("Fourth")
        let order = model.unpinnedNotes.map(\.id)
        XCTAssertEqual(model.unpinnedNotes.map(\.title), ["Fourth", "Third", "Second", "First"])

        model.moveNotes([order[1], order[2]], inPinnedSection: false, direction: 1)
        XCTAssertEqual(model.unpinnedNotes.map(\.id), [order[0], order[3], order[1], order[2]])

        model.moveNotes([order[0], order[2]], inPinnedSection: false, direction: 1)
        XCTAssertEqual(model.unpinnedNotes.map(\.id), [order[0], order[3], order[1], order[2]])
    }

    func testNoteBodyURLPointsInsideNotesDirectory() throws {
        let store = try NoteStore(rootURL: rootURL)
        let note = Note(body: "File path")

        XCTAssertEqual(
            store.noteBodyURL(for: note),
            rootURL.appendingPathComponent("Notes").appendingPathComponent("\(note.id.uuidString).txt")
        )
    }
}
