import AppKit
import SwiftUI
import XCTest
@testable import JustNote

@MainActor
final class NoteFindIntegrationTests: XCTestCase {
    func testEditorCursorExcludesOverlayControlsButKeepsQueryTextCursor() throws {
        for mode in [EditorMode.markdown, .plainText] {
            try withEditor { state, find, window in
                state.mode = mode
                settle()
                let view = try XCTUnwrap(find.textView)
                let region = try XCTUnwrap(window.contentView?.findRegions.first)
                let field = try XCTUnwrap(window.contentView?.findFields.first)
                find.open()
                settle()
                let buttonPoint = region.convert(NSPoint(x: region.bounds.maxX - 10, y: region.bounds.midY), to: nil)
                let fieldPoint = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil)
                XCTAssertTrue(find.excludesEditorCursor(at: buttonPoint))
                XCTAssertTrue(find.containsOverlay(buttonPoint))
                XCTAssertFalse(find.excludesEditorCursor(at: fieldPoint))
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: buttonPoint, modifierFlags: [],
                                                           timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                           eventNumber: 0, clickCount: 0, pressure: 0))
                NSCursor.iBeam.set()
                view.mouseMoved(with: event)
                XCTAssertTrue(NSCursor.current.isEqual(NSCursor.arrow))
                NSCursor.iBeam.set()
                let entered = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: buttonPoint, modifierFlags: [],
                                                                  timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                                  eventNumber: 0, trackingNumber: 0, userData: nil))
                view.mouseEntered(with: entered)
                XCTAssertTrue(NSCursor.current.isEqual(NSCursor.arrow))
                NSCursor.arrow.set()
                let updated = try XCTUnwrap(NSEvent.enterExitEvent(with: .cursorUpdate, location: buttonPoint, modifierFlags: [],
                                                                  timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                                  eventNumber: 0, trackingNumber: 0, userData: nil))
                view.cursorUpdate(with: updated)
                XCTAssertTrue(NSCursor.current.isEqual(NSCursor.arrow), "Cursor updates must honor Find exclusions in \(mode)")
                field.mouseMoved(with: event)
                field.mouseEntered(with: entered)
                field.cursorUpdate(with: updated)
                XCTAssertTrue(NSCursor.current.isEqual(NSCursor.arrow), "The query field must not claim control cursors")
                let fieldEvent = try XCTUnwrap(NSEvent.enterExitEvent(with: .cursorUpdate, location: fieldPoint, modifierFlags: [],
                                                                     timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                                     eventNumber: 0, trackingNumber: 0, userData: nil))
                let fieldMove = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: fieldPoint, modifierFlags: [],
                                                               timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                               eventNumber: 0, clickCount: 0, pressure: 0))
                NSCursor.iBeam.set()
                view.mouseMoved(with: fieldMove)
                XCTAssertTrue(NSCursor.current.isEqual(NSCursor.iBeam), "The note movement cursor must yield to the query in \(mode)")
                NSCursor.iBeam.set()
                view.cursorUpdate(with: fieldEvent)
                XCTAssertTrue(NSCursor.current.isEqual(NSCursor.iBeam), "The note cursor must yield to the query in \(mode)")
                NSCursor.arrow.set()
                field.cursorUpdate(with: fieldEvent)
                XCTAssertTrue(NSCursor.current.isEqual(NSCursor.iBeam))
                find.close()
                XCTAssertFalse(find.excludesEditorCursor(at: buttonPoint))
                XCTAssertFalse(find.containsOverlay(buttonPoint))
            }
        }
    }

    func testOpeningAndRefocusingFindTransfersFocusSynchronously() throws {
        try withEditor { _, find, window in
            let field = try XCTUnwrap(window.contentView?.findFields.first)
            let note = try XCTUnwrap(find.textView)
            window.makeFirstResponder(note)
            find.open()
            XCTAssertTrue(window.firstResponder === field.currentEditor())
            find.setQuery("same")
            settle()
            window.makeFirstResponder(note)
            find.open()
            XCTAssertTrue(window.firstResponder === field.currentEditor())
            XCTAssertEqual((field.currentEditor() as? NSTextView)?.selectedRange(), NSRange(location: 0, length: 4))
        }
    }

    func testFindOverlayPreservesEditorGeometryAndRevealsObscuredFirstLine() throws {
        try withEditor { state, find, window in
            state.text = String(repeating: "x", count: 45) + " target"
            settle()
            let view = try XCTUnwrap(find.textView)
            let scroll = try XCTUnwrap(view.enclosingScrollView)
            let frame = scroll.convert(scroll.bounds, to: window.contentView)
            let origin = scroll.contentView.bounds.origin
            find.open()
            settle()
            XCTAssertEqual(scroll.convert(scroll.bounds, to: window.contentView), frame)
            XCTAssertEqual(scroll.contentView.bounds.origin, origin)
            XCTAssertGreaterThan(find.overlaySize.width, 100)
            find.setQuery("target")
            settle()
            let layout = try XCTUnwrap(view.textLayoutManager)
            let offset = try XCTUnwrap(find.matches.first?.location)
            let location = try XCTUnwrap(layout.textContentManager?.location(layout.documentRange.location, offsetBy: offset))
            var y: CGFloat = 0
            layout.enumerateTextSegments(in: NSTextRange(location: location), type: .standard, options: []) { _, rect, _, _ in
                y = rect.minY + view.textContainerOrigin.y
                return false
            }
            XCTAssertGreaterThanOrEqual(y - scroll.contentView.bounds.minY, find.overlaySize.height + 15)
            find.close()
            settle()
            XCTAssertEqual(scroll.contentInsets.top, 0)
            XCTAssertGreaterThanOrEqual(scroll.contentView.bounds.minY, 0)
        }
    }

    func testDisplayedWikiLinkSuffixDoesNotPreventBinding() throws {
        try withEditor { state, find, _ in
            state.text = "[[Name|9B493F29-E93A-48FC-9BF7-769901B4EB87]] target"
            state.noteID = UUID()
            settle()
            let view = try XCTUnwrap(find.textView)
            XCTAssertNotEqual(view.string, state.text)
            find.open()
            find.setQuery("target")
            settle()
            XCTAssertEqual(find.matches, [(view.string as NSString).range(of: "target")])
            XCTAssertEqual(view.selectedRange(), find.matches.first)
        }
    }

    func testPlainTextFirstLineStaysClearOfOverlayAfterExtentRefresh() throws {
        try withEditor { state, find, _ in
            state.mode = .plainText
            state.text = String(repeating: "x", count: 45) + " target"
            settle()
            let view = try XCTUnwrap(find.textView as? EndAnchoredTextView)
            let scroll = try XCTUnwrap(view.enclosingScrollView)
            find.open()
            find.setQuery("target")
            settle()
            let layout = try XCTUnwrap(view.layoutManager)
            let container = try XCTUnwrap(view.textContainer)
            let range = try XCTUnwrap(find.matches.first)
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
            view.refreshDocumentExtent()
            settle()
            XCTAssertGreaterThanOrEqual(rect.minY - scroll.contentView.bounds.minY, find.overlaySize.height + 15)
            find.close()
            settle()
            XCTAssertEqual(scroll.contentInsets.top, 0)
            XCTAssertGreaterThanOrEqual(scroll.contentView.bounds.minY, 0)
        }
    }

    func testFindFieldIsExcludedFromRegistrationStylingAndFormatting() throws {
        try withEditor { state, find, window in
            find.open()
            find.setQuery("same")
            settle()
            let field = try XCTUnwrap(window.contentView?.findFields.first)
            window.makeFirstResponder(field)
            let fieldEditor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            XCTAssertTrue(fieldEditor.isFieldEditor)
            XCTAssertFalse(find.textView === fieldEditor)
            let before = NSAttributedString(attributedString: fieldEditor.textStorage!)
            EditorCommandRouter.shared.register(fieldEditor)
            EditorCommandRouter.shared.perform(.bold, mode: .markdown, requiresEditorFocus: true)
            XCTAssertEqual(state.text, "same")
            XCTAssertTrue(fieldEditor.textStorage!.isEqual(to: before))
            XCTAssertNil(EditorCommandRouter.shared.editor(requiresFocus: true))

            state.noteID = UUID()
            state.text = "same"
            settle()
            XCTAssertFalse(find.textView === fieldEditor)
            XCTAssertTrue(fieldEditor.textStorage!.isEqual(to: before))
            XCTAssertEqual(find.matches.count, 1)
            XCTAssertEqual(find.textView?.string, "same")

            state.text = ""
            find.setQuery("")
            state.noteID = UUID()
            settle()
            XCTAssertFalse(find.textView === fieldEditor)
            XCTAssertEqual(find.textView?.string, "")
        }
    }

    func testModeAndNoteChangesRetainQueryWithCurrentResults() throws {
        try withEditor { state, find, _ in
            find.open()
            find.setQuery("same")
            settle()
            let oldMarkdown = try XCTUnwrap(find.textView)
            state.mode = .plainText
            settle()
            XCTAssertTrue(find.textView is EndAnchoredTextView)
            XCTAssertFalse(find.textView === oldMarkdown)
            XCTAssertEqual(find.query, "same")
            XCTAssertEqual(find.matches.count, 1)
            state.noteID = UUID()
            state.text = "different"
            settle()
            XCTAssertEqual(find.status, "No matches")
            XCTAssertEqual(find.textView?.string, "different")
            state.mode = .markdown
            settle()
            XCTAssertFalse(find.textView is EndAnchoredTextView)
            XCTAssertEqual(find.textView?.string, "different")
            XCTAssertEqual(find.query, "same")
            find.close()
            settle()
            XCTAssertTrue(find.query.isEmpty)
        }
    }

    private func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15)) }

    private func withEditor(_ body: (FindEditorState, NoteFindController, NSWindow) throws -> Void) throws {
        let state = FindEditorState()
        let find = NoteFindController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: FindEditorHarness(state: state, find: find))
        window.makeKeyAndOrderFront(nil)
        settle()
        defer { find.close(refocus: false); find.detach(); window.contentView = nil; window.close() }
        try body(state, find, window)
    }
}

@MainActor
private final class FindEditorState: ObservableObject {
    @Published var noteID = UUID()
    @Published var text = "same"
    @Published var mode: EditorMode = .markdown
}

private struct FindEditorHarness: View {
    @ObservedObject var state: FindEditorState
    @ObservedObject var find: NoteFindController

    var body: some View {
        VStack {
            if state.mode == .markdown {
                LiveMarkdownEditor(text: $state.text, documentID: state.noteID, retainedDocumentIDs: [state.noteID], fontSize: 13,
                                   onRegister: { find.bind($0, noteID: state.noteID, mode: .markdown) },
                                   isCursorExcluded: { find.excludesEditorCursor(at: $0) },
                                   isInteractionExcluded: { find.containsOverlay($0) })
            } else {
                PlainTextEditor(text: $state.text, wrapsLines: true, fontSize: 13,
                                onRegister: { find.bind($0, noteID: state.noteID, mode: .plainText) },
                                isCursorExcluded: { find.excludesEditorCursor(at: $0) })
            }
        }
        .modifier(NoteFindOverlay(find: find))
        .onAppear { updateScope() }
        .onChange(of: state.noteID) { _, _ in updateScope() }
        .onChange(of: state.mode) { _, _ in updateScope() }
    }

    private func updateScope() { find.setScope(noteID: state.noteID, mode: state.mode) }
}

private extension NSView {
    var findRegions: [NoteFindRegionView] {
        (self as? NoteFindRegionView).map { [$0] } ?? subviews.flatMap(\.findRegions)
    }

    var findFields: [NSTextField] {
        (self as? NSTextField).map { [$0] } ?? subviews.flatMap(\.findFields)
    }
}
