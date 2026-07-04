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
