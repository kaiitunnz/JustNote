import AppKit
import SwiftUI
import XCTest
@testable import JustNote

@MainActor
final class MarkdownClosingDelimiterTests: XCTestCase {
    func testAutoInsertedClosersOnlyMoveTheCaret() throws {
        for (open, close) in [("(", ")"), ("[", "]"), ("{", "}")] {
            try withEditor("") { state, _, window in
                let view = try XCTUnwrap(state.view)
                window.makeFirstResponder(view)
                view.insertText(open, replacementRange: view.selectedRange())
                view.insertText("body", replacementRange: view.selectedRange())
                settle()
                let expected = open + "body" + close
                XCTAssertEqual(state.text, expected)
                view.keyDown(with: key(close))
                settle()
                XCTAssertEqual(state.text, expected)
                XCTAssertEqual(view.string, expected)
                XCTAssertEqual(view.selectedRange(), NSRange(location: expected.utf16.count, length: 0))
            }
        }
    }

    func testUnicodeWikiLinkClosersPreserveStoredMetadata() throws {
        let source = "👩🏽‍💻 é [[Name|opaque]]"
        try withEditor(source) { state, _, window in
            let view = try XCTUnwrap(state.view)
            window.makeFirstResponder(view)
            let close = (view.string as NSString).range(of: "]]").location
            XCTAssertNotEqual(close, NSNotFound)
            view.setSelectedRange(NSRange(location: close, length: 0))
            for _ in 0..<2 { view.keyDown(with: key("]")) }
            settle()
            XCTAssertEqual(state.text, source)
            XCTAssertEqual(view.selectedRange(), NSRange(location: view.string.utf16.count, length: 0))
            view.insertText("!", replacementRange: view.selectedRange())
            settle()
            XCTAssertEqual(state.text, source + "!")
        }
    }

    func testUndoAfterTypeThroughRestoresTheBoundText() throws {
        try withEditor("()") { state, _, window in
            let view = try XCTUnwrap(state.view)
            window.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: 1, length: 0))
            view.undoManager?.removeAllActions()
            view.insertText("body", replacementRange: view.selectedRange())
            settle()
            view.breakUndoCoalescing()
            view.keyDown(with: key(")"))
            settle()
            XCTAssertEqual(state.text, "(body)")
            view.undoManager?.undo()
            settle()
            XCTAssertEqual(view.string, "()")
            XCTAssertEqual(state.text, "()")
            view.undoManager?.redo()
            settle()
            XCTAssertEqual(state.text, "(body)")
        }
    }

    func testPlainTextAndFindKeepLiteralInsertion() throws {
        try withEditor("()", markdown: false) { state, _, window in
            let view = try XCTUnwrap(state.view)
            window.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: 1, length: 0))
            view.keyDown(with: key(")"))
            settle()
            XCTAssertEqual(state.text, "())")
        }
        try withEditor("()") { state, find, window in
            find.open()
            settle()
            let field = try XCTUnwrap(window.firstResponder as? NSTextView)
            XCTAssertTrue(field.isFieldEditor)
            field.insertText("()", replacementRange: field.selectedRange())
            field.setSelectedRange(NSRange(location: 1, length: 0))
            field.keyDown(with: key(")"))
            settle()
            XCTAssertEqual(find.query, "())")
            XCTAssertEqual(state.text, "()")
        }
    }

    func testSelectionReplacementAndProgrammaticInputRemainLiteral() throws {
        try withEditor("text)") { state, _, window in
            let view = try XCTUnwrap(state.view)
            window.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: 0, length: 4))
            view.keyDown(with: key(")"))
            settle()
            XCTAssertEqual(state.text, "))")
            view.insertText(")", replacementRange: view.selectedRange())
            settle()
            XCTAssertEqual(state.text, ")))")
        }
    }

    func testExistingPairStillWorksAfterNoteSwitch() throws {
        try withEditor("(body)") { state, _, window in
            let originalID = state.noteID
            let otherID = UUID()
            state.retainedIDs.insert(otherID)
            state.noteID = otherID
            state.text = "Other note"
            settle()
            state.noteID = originalID
            state.text = "(body)"
            settle()
            let view = try XCTUnwrap(state.view)
            window.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: 5, length: 0))
            view.keyDown(with: key(")"))
            settle()
            XCTAssertEqual(state.text, "(body)")
            XCTAssertEqual(view.selectedRange(), NSRange(location: 6, length: 0))
        }
    }

    private func key(_ character: String) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero,
                         modifierFlags: character == "]" ? [] : .shift,
                         timestamp: 0, windowNumber: 0, context: nil,
                         characters: character, charactersIgnoringModifiers: character,
                         isARepeat: false, keyCode: character == ")" ? 29 : 30)!
    }

    private func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15)) }

    private func withEditor(_ text: String, markdown: Bool = true,
                            body: (ClosingEditorState, NoteFindController, NSWindow) throws -> Void) throws {
        let state = ClosingEditorState(text: text)
        let find = NoteFindController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ClosingEditorHarness(state: state, find: find, markdown: markdown))
        window.makeKeyAndOrderFront(nil)
        settle()
        defer { find.close(refocus: false); find.detach(); window.contentView = nil; window.close() }
        try body(state, find, window)
    }
}

@MainActor
private final class ClosingEditorState: ObservableObject {
    @Published var noteID = UUID()
    @Published var text: String
    var retainedIDs: Set<UUID> = []
    weak var view: NSTextView?
    init(text: String) { self.text = text; retainedIDs = [noteID] }
}

private struct ClosingEditorHarness: View {
    @ObservedObject var state: ClosingEditorState
    @ObservedObject var find: NoteFindController
    let markdown: Bool

    var body: some View {
        Group {
            if markdown {
                LiveMarkdownEditor(text: $state.text, documentID: state.noteID, retainedDocumentIDs: state.retainedIDs, fontSize: 13,
                                   onRegister: register, isInteractionExcluded: { find.containsOverlay($0) })
            } else {
                PlainTextEditor(text: $state.text, wrapsLines: true, fontSize: 13, onRegister: register)
            }
        }
        .modifier(NoteFindOverlay(find: find))
        .onAppear { updateScope() }
        .onChange(of: state.noteID) { _, _ in updateScope() }
    }

    private func register(_ view: NSTextView) {
        state.view = view
        find.bind(view, noteID: state.noteID, mode: markdown ? .markdown : .plainText)
    }

    private func updateScope() { find.setScope(noteID: state.noteID, mode: markdown ? .markdown : .plainText) }
}
