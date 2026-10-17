import AppKit
import SwiftUI
import XCTest
@testable import JustNote

@MainActor
final class NoteFindTests: XCTestCase {
    func testLiteralUnicodeMatchingUsesUTF16Ranges() {
        let text = "😀 Café cafe\u{301} CAFÉ a.b axb\nline"
        let matches = NoteFindMatcher.ranges(of: "cafe", in: text)
        XCTAssertEqual(matches.map { (text as NSString).substring(with: $0) }, ["Café", "cafe\u{301}", "CAFÉ"])
        XCTAssertEqual(matches.first?.location, 3)
        XCTAssertEqual(NoteFindMatcher.ranges(of: "a.b", in: text).count, 1)
        XCTAssertEqual(NoteFindMatcher.ranges(of: "axb\nline", in: text).count, 1)
        XCTAssertTrue(NoteFindMatcher.ranges(of: "", in: text).isEmpty)
        XCTAssertEqual(NoteFindMatcher.ranges(of: "aa", in: "aaa"), [NSRange(location: 0, length: 2)])
    }

    func testNavigationWrapsAndEmptyQueryPreservesSelection() {
        withPlain("one two one") { find, view in
            find.open()
            find.setQuery("one")
            XCTAssertEqual(find.status, "1 of 2")
            XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 3))
            find.move(backward: true)
            XCTAssertEqual(find.currentIndex, 1)
            find.move()
            XCTAssertEqual(find.currentIndex, 0)
            find.setQuery("")
            XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 3))
            find.setQuery("absent")
            XCTAssertEqual(find.status, "No matches")
            find.move()
            XCTAssertEqual(find.currentIndex, 0)
        }
    }

    func testTemporaryHighlightsPreserveStorageAndClearOnClose() throws {
        try withPlain("one two one") { find, view in
            let storage = try XCTUnwrap(view.textStorage)
            storage.addAttribute(.backgroundColor, value: NSColor.systemBlue, range: NSRange(location: 0, length: 3))
            let before = NSAttributedString(attributedString: storage)
            find.open()
            find.setQuery("one")
            XCTAssertNotNil(view.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil))
            XCTAssertTrue(storage.isEqual(to: before))
            find.close()
            XCTAssertNil(view.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil))
            XCTAssertTrue(storage.isEqual(to: before))
            XCTAssertTrue(find.query.isEmpty)
        }
    }

    func testEditsRefreshWithoutMovingCaretOrViewportAndUndoRefreshes() {
        withPlain(String(repeating: "one two\n", count: 100)) { find, view in
            find.open()
            find.setQuery("one")
            view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
            view.scrollRangeToVisible(view.selectedRange())
            view.insertText("one", replacementRange: view.selectedRange())
            let selection = view.selectedRange()
            let origin = view.enclosingScrollView!.contentView.bounds.origin
            settle()
            XCTAssertEqual(find.matches.count, 101)
            XCTAssertEqual(view.selectedRange(), selection)
            XCTAssertEqual(view.enclosingScrollView!.contentView.bounds.origin, origin)
            view.undoManager?.undo()
            settle()
            XCTAssertEqual(find.matches.count, 100)
        }
    }

    func testScopeRejectsStaleBindingAndRetainsQuery() {
        withPlain("same") { find, oldView in
            find.open()
            find.setQuery("same")
            let newID = UUID()
            find.setScope(noteID: newID, mode: .plainText)
            XCTAssertTrue(find.matches.isEmpty)
            XCTAssertEqual(find.query, "same")
            XCTAssertNil(oldView.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil))
            find.bind(oldView, noteID: UUID(), mode: .plainText)
            XCTAssertNil(find.textView)
            let newView = NSTextView()
            newView.string = "same"
            find.bind(newView, noteID: newID, mode: .plainText)
            XCTAssertTrue(find.textView === newView)
            XCTAssertEqual(find.matches.count, 1)
            find.setScope(noteID: newID, mode: .markdown)
            find.bind(oldView, noteID: newID, mode: .plainText)
            XCTAssertNil(find.textView)
            find.setScope(noteID: nil, mode: .markdown)
            XCTAssertFalse(find.isVisible)
            XCTAssertTrue(find.query.isEmpty)
        }
    }

    func testFieldEditorCannotBind() {
        let find = NoteFindController()
        let id = UUID()
        find.setScope(noteID: id, mode: .plainText)
        let view = NSTextView()
        view.isFieldEditor = true
        find.bind(view, noteID: id, mode: .plainText)
        XCTAssertNil(find.textView)
    }

    func testTypingWithFindClosedOrEmptyDoesNotPublishSearchRefreshes() {
        withPlain("ordinary text") { find, view in
            var updates = 0
            let observer = find.objectWillChange.sink { updates += 1 }
            view.insertText("X", replacementRange: NSRange(location: 0, length: 0))
            settle()
            XCTAssertEqual(updates, 0)
            find.open()
            updates = 0
            view.insertText("Y", replacementRange: NSRange(location: 0, length: 0))
            settle()
            XCTAssertEqual(updates, 0)
            withExtendedLifetime(observer) {}
        }
    }

    func testShortcutsRequireExactModifiersAndEscapeClosesFindFirst() {
        withPlain("one one") { find, _ in
            func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags) -> NSEvent {
                NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                 windowNumber: 0, context: nil, characters: code == 3 ? "f" : "g", charactersIgnoringModifiers: code == 3 ? "f" : "g",
                                 isARepeat: false, keyCode: code)!
            }
            XCTAssertFalse(find.handleKey(key(3, [.command, .option])))
            XCTAssertTrue(find.handleKey(key(3, .control)))
            find.setQuery("one")
            XCTAssertTrue(find.handleKey(key(5, [.command, .shift])))
            XCTAssertEqual(find.currentIndex, 1)
            XCTAssertTrue(find.handleKey(key(5, .command)))
            XCTAssertEqual(find.currentIndex, 0)
            let focus = find.focusRequest
            XCTAssertTrue(find.handleKey(key(3, .command)))
            XCTAssertGreaterThan(find.focusRequest, focus)
            XCTAssertTrue(find.handleKey(key(53, [])))
            XCTAssertFalse(find.isVisible)
            XCTAssertFalse(find.handleKey(key(53, [])))
            let remapped = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .control, timestamp: 0,
                                            windowNumber: 0, context: nil, characters: "f", charactersIgnoringModifiers: "f",
                                            isARepeat: false, keyCode: 32)!
            XCTAssertTrue(find.handleKey(remapped))
            let physicalF = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .control, timestamp: 0,
                                             windowNumber: 0, context: nil, characters: "u", charactersIgnoringModifiers: "u",
                                             isARepeat: false, keyCode: 3)!
            XCTAssertFalse(find.handleKey(physicalF))
        }
    }

    func testUnwrappedMatchRevealsHorizontally() {
        withPlain(String(repeating: "wide ", count: 100) + "target") { find, view in
            view.isHorizontallyResizable = true
            view.textContainer?.widthTracksTextView = false
            view.textContainer?.containerSize = NSSize(width: 100000, height: 100000)
            view.maxSize = NSSize(width: 100000, height: 100000)
            view.sizeToFit()
            find.open()
            find.setQuery("target")
            settle()
            XCTAssertGreaterThan(view.enclosingScrollView!.contentView.bounds.minX, 1000)
            XCTAssertEqual(view.selectedRange(), (view.string as NSString).range(of: "target"))
        }
    }

    func testMarkdownTableLinkMatchRevealsSourceAndLocalSegment() throws {
        let source = "Start\n\n| Row | Value |\n| --- | --- |\n"
            + (0..<80).map { "| \($0) | [target\($0)](https://example.com/\($0)) |\n" }.joined()
            + "\nAfter table.\n"
        try withMarkdown(source) { find, view in
            find.open()
            find.setQuery("target79")
            settle()
            let range = try XCTUnwrap(find.matches.first)
            XCTAssertEqual(view.selectedRange(), range)
            let font = try XCTUnwrap(view.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
            XCTAssertGreaterThan(font.pointSize, 1)
            let layout = try XCTUnwrap(view.textLayoutManager)
            let location = try XCTUnwrap(layout.textContentManager?.location(layout.documentRange.location, offsetBy: range.location))
            var rect = NSRect.zero
            layout.enumerateTextSegments(in: NSTextRange(location: location), type: .standard, options: []) { _, frame, _, _ in
                rect = frame.offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
                return false
            }
            let scroll = try XCTUnwrap(view.enclosingScrollView)
            XCTAssertTrue(scroll.contentView.bounds.intersects(rect))
            XCTAssertGreaterThan(scroll.contentView.bounds.minY, 500)
            XCTAssertEqual(view.string, source)
        }
    }

    func testMarkdownEditRefreshDoesNotReturnToFirstMatch() throws {
        let source = "Start target.\n\n" + String(repeating: "Following paragraph.\n\n", count: 100)
        try withMarkdown(source) { find, view in
            find.open()
            find.setQuery("target")
            settle()
            view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
            view.scrollRangeToVisible(view.selectedRange())
            view.insertText("target", replacementRange: view.selectedRange())
            let selection = view.selectedRange()
            let origin = view.enclosingScrollView!.contentView.bounds.origin
            settle()
            XCTAssertEqual(find.matches.count, 2)
            XCTAssertEqual(view.selectedRange(), selection)
            XCTAssertEqual(view.enclosingScrollView!.contentView.bounds.origin, origin)
        }
    }

    func testMarkdownRenderingHighlightsSurviveLayoutWithoutChangingCodeBackground() throws {
        let source = "Start\n\n```swift\nlet target = 1\n```\n\nEnd target.\n"
        try withMarkdown(source) { find, view in
            let offset = (source as NSString).range(of: "let target").location
            let before = view.textStorage?.attribute(.backgroundColor, at: offset, effectiveRange: nil) as? NSColor
            find.open()
            find.setQuery("target")
            settle()
            XCTAssertEqual(view.textStorage?.attribute(.backgroundColor, at: offset, effectiveRange: nil) as? NSColor, before)
            let layout = try XCTUnwrap(view.textLayoutManager)
            layout.invalidateLayout(for: layout.documentRange)
            layout.ensureLayout(for: layout.documentRange)
            view.displayIfNeeded()
            var backgrounds = 0
            layout.enumerateRenderingAttributes(from: layout.documentRange.location, reverse: false) { _, attrs, _ in
                if attrs[.backgroundColor] != nil { backgrounds += 1 }
                return true
            }
            XCTAssertGreaterThan(backgrounds, 0)
            find.close()
            XCTAssertEqual(view.textStorage?.attribute(.backgroundColor, at: offset, effectiveRange: nil) as? NSColor, before)
        }
    }

    func testMarkdownQueryChangesAndCloseClearEarlierHighlights() throws {
        try withMarkdown("Start target\n\n```swift\nlet target = 1\n```\n\nEnd target.\n") { find, view in
            find.open()
            for query in ["t", "ta", "tar", "target"] { find.setQuery(query); settle() }
            let layout = try XCTUnwrap(view.textLayoutManager)
            func highlightedOffsets() -> Set<Int> {
                var offsets: Set<Int> = []
                layout.enumerateRenderingAttributes(from: layout.documentRange.location, reverse: false) { _, attrs, range in
                    if attrs[.backgroundColor] != nil, let content = layout.textContentManager {
                        let start = content.offset(from: layout.documentRange.location, to: range.location)
                        let end = content.offset(from: layout.documentRange.location, to: range.endLocation)
                        offsets.formUnion(start..<end)
                    }
                    return true
                }
                return offsets
            }
            let expected = Set(find.matches.flatMap { Array($0.location..<NSMaxRange($0)) })
            XCTAssertEqual(highlightedOffsets(), expected)
            find.close()
            settle()
            XCTAssertTrue(highlightedOffsets().isEmpty)
        }
    }

    private func settle() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
    }

    private func withPlain(_ source: String, body: (NoteFindController, NSTextView) throws -> Void) rethrows {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        let view = UndoTextView(frame: scroll.bounds)
        _ = view.layoutManager
        view.allowsUndo = true
        view.string = source
        view.font = .systemFont(ofSize: 13)
        scroll.documentView = view
        window.contentView = scroll
        window.makeFirstResponder(view)
        view.sizeToFit()
        let find = NoteFindController()
        let id = UUID()
        find.setScope(noteID: id, mode: .plainText)
        find.bind(view, noteID: id, mode: .plainText)
        defer { find.detach(); window.close() }
        try body(find, view)
    }

    private func withMarkdown(_ source: String, body: (NoteFindController, NSTextView) throws -> Void) throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let id = UUID()
        let host = NSHostingView(rootView: LiveMarkdownEditor(text: .constant(source), documentID: id, retainedDocumentIDs: [id], fontSize: 13))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        settle()
        let view = try XCTUnwrap(host.textViews.first)
        let find = NoteFindController()
        find.setScope(noteID: id, mode: .markdown)
        find.bind(view, noteID: id, mode: .markdown)
        defer { find.detach(); window.close() }
        try body(find, view)
    }
}

private final class UndoTextView: NSTextView {
    private let testUndoManager = UndoManager()
    override var undoManager: UndoManager? { testUndoManager }
}
