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

    func testSelectAdjacentNoteIsNoOpWithSingleNote() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        XCTAssertEqual(model.orderedNotes.count, 1)
        let only = model.selectedNoteID

        XCTAssertFalse(model.selectAdjacentNote(offset: 1))
        XCTAssertFalse(model.selectAdjacentNote(offset: -1))
        XCTAssertEqual(model.selectedNoteID, only)
    }

    func testSelectingNotesUpdatesRecentOrder() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let firstID = try XCTUnwrap(model.selectedNoteID)
        model.createNote()
        let secondID = try XCTUnwrap(model.selectedNoteID)

        model.select(firstID)

        XCTAssertEqual(model.recentNoteIDs.prefix(2), [firstID, secondID])
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

    func testDeletingSelectedNoteLeavesValidSelectionOrEmptyState() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        model.createNote()

        model.deleteSelectedNote()

        XCTAssertEqual(model.notes.count, 1)
        XCTAssertTrue(model.selectedNoteID.map { id in model.notes.contains { $0.id == id } } ?? false)

        model.deleteSelectedNote()

        XCTAssertTrue(model.notes.isEmpty)
        XCTAssertNil(model.selectedNoteID)
        XCTAssertTrue(model.recentNoteIDs.isEmpty)

        let reloaded = AppModel(store: try NoteStore(rootURL: rootURL))
        XCTAssertTrue(reloaded.notes.isEmpty)
        XCTAssertNil(reloaded.selectedNoteID)
    }
}
