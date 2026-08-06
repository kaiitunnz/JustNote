import XCTest
import AppKit
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

    func testEditorModePreferenceDefaultsToMarkdown() {
        let suiteName = "JustNoteTests.editorMode.default.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(EditorModePreference.initialValue(defaults: defaults), EditorMode.markdown.rawValue)
        XCTAssertEqual(defaults.string(forKey: EditorModePreference.key), EditorMode.markdown.rawValue)
        XCTAssertNil(defaults.object(forKey: EditorModePreference.legacyPreviewKey))
    }

    func testEditorModePreferenceMigratesLegacyPreviewMode() {
        let markdownSuiteName = "JustNoteTests.editorMode.legacy.markdown.\(UUID().uuidString)"
        let markdownDefaults = UserDefaults(suiteName: markdownSuiteName)!
        defer { markdownDefaults.removePersistentDomain(forName: markdownSuiteName) }
        markdownDefaults.set(true, forKey: EditorModePreference.legacyPreviewKey)
        XCTAssertEqual(EditorModePreference.initialValue(defaults: markdownDefaults), EditorMode.markdown.rawValue)
        XCTAssertNil(markdownDefaults.object(forKey: EditorModePreference.legacyPreviewKey))

        let plainSuiteName = "JustNoteTests.editorMode.legacy.plain.\(UUID().uuidString)"
        let plainDefaults = UserDefaults(suiteName: plainSuiteName)!
        defer { plainDefaults.removePersistentDomain(forName: plainSuiteName) }
        plainDefaults.set(false, forKey: EditorModePreference.legacyPreviewKey)
        XCTAssertEqual(EditorModePreference.initialValue(defaults: plainDefaults), EditorMode.plainText.rawValue)
        XCTAssertNil(plainDefaults.object(forKey: EditorModePreference.legacyPreviewKey))
    }

    func testEditorModePreferenceKeepsExplicitMode() {
        let suiteName = "JustNoteTests.editorMode.explicit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(EditorMode.plainText.rawValue, forKey: EditorModePreference.key)
        defaults.set(true, forKey: EditorModePreference.legacyPreviewKey)

        XCTAssertEqual(EditorModePreference.initialValue(defaults: defaults), EditorMode.plainText.rawValue)
        XCTAssertNil(defaults.object(forKey: EditorModePreference.legacyPreviewKey))
    }

    func testEditorFontSizeStepsAlongRamp() {
        // Adjacent stops, including the coarsening near the top of the ramp.
        XCTAssertEqual(EditorFontSize.increased(from: 13), 14)
        XCTAssertEqual(EditorFontSize.decreased(from: 13), 12)
        XCTAssertEqual(EditorFontSize.increased(from: 16), 18)
        XCTAssertEqual(EditorFontSize.decreased(from: 20), 18)
    }

    func testEditorFontSizeSnapsOffRampValuesInDirectionOfTravel() {
        XCTAssertEqual(EditorFontSize.increased(from: 17), 18)
        XCTAssertEqual(EditorFontSize.decreased(from: 17), 16)
        XCTAssertEqual(EditorFontSize.increased(from: 30), 32)
        XCTAssertEqual(EditorFontSize.decreased(from: 30), 28)
    }

    func testEditorFontSizeGrowsUncappedAboveRamp() {
        XCTAssertEqual(EditorFontSize.increased(from: 32), 32 + EditorFontSize.stepAboveRamp)
        XCTAssertEqual(EditorFontSize.increased(from: 100), 104)
        // Coming back down snaps to the top stop, then walks the ramp.
        XCTAssertEqual(EditorFontSize.decreased(from: 36), 32)
        XCTAssertEqual(EditorFontSize.decreased(from: 33), 32)
    }

    func testEditorFontSizeShrinksByOneBelowRampDownToFloor() {
        XCTAssertEqual(EditorFontSize.decreased(from: 9), 8)
        XCTAssertEqual(EditorFontSize.increased(from: 8), 9)
        XCTAssertEqual(EditorFontSize.increased(from: 5), 6)
        // The floor is a correctness guard, not a style minimum.
        XCTAssertEqual(EditorFontSize.decreased(from: EditorFontSize.minSize), EditorFontSize.minSize)
        XCTAssertEqual(EditorFontSize.decreased(from: 3), EditorFontSize.minSize)
    }

    func testEditorFontSizeCurrentDefaultsWhenUnset() {
        let suiteName = "JustNoteTests.fontSize.default.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(EditorFontSize.current(defaults: defaults), EditorFontSize.defaultSize)
    }

    func testEditorFontSizeCurrentReadsUncappedAndFloors() {
        let suiteName = "JustNoteTests.fontSize.persisted.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // No upper cap: a large persisted value passes through unchanged.
        defaults.set(72, forKey: EditorFontSize.key)
        XCTAssertEqual(EditorFontSize.current(defaults: defaults), 72)

        // Below the correctness floor: sanitized up to minSize.
        defaults.set(0, forKey: EditorFontSize.key)
        XCTAssertEqual(EditorFontSize.current(defaults: defaults), EditorFontSize.minSize)
    }

    func testMarkdownParagraphGapHitTestUsesOpenLowerBound() {
        XCTAssertFalse(MarkdownParagraphGapHitTest.contains(y: 40, lastLineMaxY: 40, fragmentMaxY: 52))
        XCTAssertTrue(MarkdownParagraphGapHitTest.contains(y: 46, lastLineMaxY: 40, fragmentMaxY: 52))
        XCTAssertTrue(MarkdownParagraphGapHitTest.contains(y: 52, lastLineMaxY: 40, fragmentMaxY: 52))
        XCTAssertFalse(MarkdownParagraphGapHitTest.contains(y: 53, lastLineMaxY: 40, fragmentMaxY: 52))
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

    func testCollapseSelectionToPrimaryDropsExtraSelection() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        model.createNote()
        model.createNote()
        let order = model.orderedNotes.map(\.id)

        model.selectOnly(order[0])
        model.toggleSelection(order[1])
        model.toggleSelection(order[2])
        XCTAssertEqual(model.selectedNoteID, order[2])
        XCTAssertEqual(model.selectedNoteIDs, Set(order))

        model.collapseSelectionToPrimary()
        XCTAssertEqual(model.selectedNoteID, order[2])
        XCTAssertEqual(model.selectedNoteIDs, [order[2]])

        // A subsequent range selection anchors at the collapsed primary.
        model.selectRange(to: order[0])
        XCTAssertEqual(model.selectedNoteIDs, Set(order))
    }

    func testCollapseSelectionToPrimaryIsNoOpWhenSingle() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let id = try XCTUnwrap(model.selectedNoteID)
        XCTAssertEqual(model.selectedNoteIDs, [id])

        model.collapseSelectionToPrimary()
        XCTAssertEqual(model.selectedNoteID, id)
        XCTAssertEqual(model.selectedNoteIDs, [id])
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

    func testDragPinsNoteAcrossSectionsAtRequestedIndex() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let (a, b, c) = try seedThreeUnpinned(model)
        XCTAssertEqual(model.unpinnedNotes.map(\.id), [c, b, a])
        let before = try XCTUnwrap(model.notes.first { $0.id == a }).updatedAt

        model.moveNote(a, toSection: true, toIndex: 0)

        XCTAssertEqual(model.pinnedNotes.map(\.id), [a])
        XCTAssertEqual(model.unpinnedNotes.map(\.id), [c, b])
        XCTAssertTrue(try XCTUnwrap(model.notes.first { $0.id == a }).pinned)
        XCTAssertGreaterThan(try XCTUnwrap(model.notes.first { $0.id == a }).updatedAt, before)
    }

    func testDragUnpinsNoteAcrossSections() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let (a, b, c) = try seedThreeUnpinned(model)
        model.setPinned([a, b], pinned: true)

        model.moveNote(a, toSection: false, toIndex: 0)

        XCTAssertFalse(try XCTUnwrap(model.notes.first { $0.id == a }).pinned)
        XCTAssertEqual(model.pinnedNotes.map(\.id), [b])
        XCTAssertEqual(model.unpinnedNotes.map(\.id), [a, c])
    }

    func testCrossSectionDropAtEndLandsLast() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let (a, b, c) = try seedThreeUnpinned(model)
        model.setPinned([b, c], pinned: true)
        XCTAssertEqual(model.pinnedNotes.map(\.id), [c, b])

        model.moveNote(a, toSection: true, toIndex: model.pinnedNotes.count)

        XCTAssertEqual(model.pinnedNotes.map(\.id), [c, b, a])
        XCTAssertTrue(model.unpinnedNotes.isEmpty)
    }

    func testMultiSelectDragSpanningBothSectionsMovesTogether() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let (a, b, c) = try seedThreeUnpinned(model)
        model.setPinned([a], pinned: true)
        XCTAssertEqual(model.pinnedNotes.map(\.id), [a])
        XCTAssertEqual(model.unpinnedNotes.map(\.id), [c, b])

        model.moveNotes([a, c], toSection: false, toIndex: 0)

        XCTAssertTrue(model.pinnedNotes.isEmpty)
        XCTAssertEqual(model.unpinnedNotes.map(\.id), [a, c, b])
        XCTAssertFalse(try XCTUnwrap(model.notes.first { $0.id == a }).pinned)
        XCTAssertFalse(try XCTUnwrap(model.notes.first { $0.id == c }).pinned)
    }

    func testCrossSectionMoveBumpsOnlyFlippedNotes() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let (a, _, c) = try seedThreeUnpinned(model)
        model.setPinned([a], pinned: true)
        let aBefore = try XCTUnwrap(model.notes.first { $0.id == a }).updatedAt
        let cBefore = try XCTUnwrap(model.notes.first { $0.id == c }).updatedAt

        model.moveNotes([a, c], toSection: true, toIndex: 0)

        XCTAssertEqual(try XCTUnwrap(model.notes.first { $0.id == a }).updatedAt, aBefore)
        XCTAssertGreaterThan(try XCTUnwrap(model.notes.first { $0.id == c }).updatedAt, cBefore)
    }

    func testMoveToSectionClampsOutOfRangeIndex() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let (a, b, c) = try seedThreeUnpinned(model)
        XCTAssertEqual(model.unpinnedNotes.map(\.id), [c, b, a])

        model.moveNote(c, toSection: false, toIndex: .max)
        XCTAssertEqual(model.unpinnedNotes.map(\.id), [b, a, c])

        model.moveNote(c, toSection: false, toIndex: -5)
        XCTAssertEqual(model.unpinnedNotes.map(\.id), [c, b, a])
    }

    func testSameSectionReorderViaToSectionLeavesTimestampsUnchanged() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let (a, b, c) = try seedThreeUnpinned(model)
        let before = Dictionary(uniqueKeysWithValues: model.notes.map { ($0.id, $0.updatedAt) })

        model.moveNote(c, toSection: false, toIndex: 2)

        XCTAssertEqual(model.unpinnedNotes.map(\.id), [b, a, c])
        for id in [a, b, c] {
            XCTAssertEqual(try XCTUnwrap(model.notes.first { $0.id == id }).updatedAt, before[id])
        }
    }

    func testCrossSectionMovePersistsAcrossReload() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let (a, b, c) = try seedThreeUnpinned(model)
        model.moveNote(a, toSection: true, toIndex: 0)
        model.moveNote(b, toSection: true, toIndex: 1)
        XCTAssertEqual(model.pinnedNotes.map(\.id), [a, b])
        XCTAssertEqual(model.unpinnedNotes.map(\.id), [c])

        let reloaded = AppModel(store: try NoteStore(rootURL: rootURL))
        XCTAssertEqual(reloaded.pinnedNotes.map(\.id), [a, b])
        XCTAssertEqual(reloaded.unpinnedNotes.map(\.id), [c])
    }

    func testNotesWouldMoveDetectsNoOpPositions() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        let (a, b, c) = try seedThreeUnpinned(model)
        XCTAssertEqual(model.unpinnedNotes.map(\.id), [c, b, a])

        // c sits at display index 0; dropping it before itself is a no-op.
        XCTAssertFalse(model.notesWouldMove([c], toSection: false, toIndex: 0))
        // Moving c down past b changes the order.
        XCTAssertTrue(model.notesWouldMove([c], toSection: false, toIndex: 1))
        // Crossing into the pinned section always changes (pin flips) even if the id order is unchanged.
        XCTAssertTrue(model.notesWouldMove([c], toSection: true, toIndex: 0))
        // b sits at index 1; dropping it in either flanking gap is a no-op.
        XCTAssertFalse(model.notesWouldMove([b], toSection: false, toIndex: 1))
    }

    /// Seeds three unpinned notes with bodies A/B/C; returns their ids.
    /// Newest-first insertion means the resulting unpinned order is [c, b, a].
    private func seedThreeUnpinned(_ model: AppModel) throws -> (a: UUID, b: UUID, c: UUID) {
        let a = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("A")
        model.createNote()
        let b = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("B")
        model.createNote()
        let c = try XCTUnwrap(model.selectedNoteID)
        model.updateSelectedBody("C")
        return (a, b, c)
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

    func testDeletingNonPrimaryFromGroupKeepsPrimaryAndRemainingSelection() throws {
        let model = AppModel(store: try NoteStore(rootURL: rootURL))
        model.updateSelectedBody("First")
        model.createNote()
        model.updateSelectedBody("Second")
        model.createNote()
        model.updateSelectedBody("Third")
        let order = model.orderedNotes.map(\.id)

        model.selectOnly(order[0])
        model.toggleSelection(order[1])
        model.toggleSelection(order[2])
        XCTAssertEqual(model.selectedNoteID, order[2])
        XCTAssertEqual(model.selectedNoteIDs, Set(order))

        model.deleteNotes([order[0]])

        XCTAssertEqual(model.orderedNotes.map(\.id), [order[1], order[2]])
        XCTAssertEqual(model.selectedNoteID, order[2])
        XCTAssertEqual(model.selectedNoteIDs, [order[1], order[2]])
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

    func testPanelSummonPlacementReprojectsFrameByVisibleFrameRatios() throws {
        let frame = NSRect(x: 100, y: 200, width: 500, height: 400)
        let source = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let target = NSRect(x: 2_000, y: 100, width: 2_000, height: 1_200)

        let reprojected = try XCTUnwrap(PanelSummonPlacement.reproject(
            frame: frame,
            from: source,
            to: target,
            minSize: NSSize(width: 200, height: 150)
        ))

        XCTAssertEqual(reprojected, NSRect(x: 2_200, y: 400, width: 500, height: 400))
    }

    func testPanelSummonPlacementClampsFrameIntoTargetVisibleFrame() throws {
        let frame = NSRect(x: 800, y: 650, width: 400, height: 200)
        let source = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let target = NSRect(x: 0, y: 0, width: 600, height: 400)

        let reprojected = try XCTUnwrap(PanelSummonPlacement.reproject(
            frame: frame,
            from: source,
            to: target,
            minSize: NSSize(width: 200, height: 100)
        ))

        XCTAssertEqual(reprojected, NSRect(x: 200, y: 200, width: 400, height: 200))
    }
}
