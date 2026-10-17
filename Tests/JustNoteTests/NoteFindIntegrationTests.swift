import AppKit
import SwiftUI
import XCTest
@testable import JustNote

@MainActor
final class NoteFindIntegrationTests: XCTestCase {
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
                                   onRegister: { find.bind($0, noteID: state.noteID, mode: .markdown) })
            } else {
                PlainTextEditor(text: $state.text, wrapsLines: true, fontSize: 13,
                                onRegister: { find.bind($0, noteID: state.noteID, mode: .plainText) })
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
    var findFields: [NSTextField] {
        (self as? NSTextField).map { [$0] } ?? subviews.flatMap(\.findFields)
    }
}
