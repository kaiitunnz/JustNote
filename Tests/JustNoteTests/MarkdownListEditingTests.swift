import AppKit
import SwiftUI
import XCTest
@testable import JustNote

@MainActor
final class MarkdownListEditingTests: XCTestCase {
    func testNativeListCommandsUpdateNumbersAndBinding() throws {
        try withEditor("1. Alpha\n2. Beta\n3. Gamma") { state, _, window in
            let view = try XCTUnwrap(state.view)
            window.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: NSMaxRange((view.string as NSString).range(of: "Beta")), length: 0))
            view.doCommand(by: #selector(NSResponder.insertTab(_:)))
            settle()
            XCTAssertEqual(state.text, "1. Alpha\n\t1. Beta\n2. Gamma")
            view.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
            settle()
            XCTAssertEqual(state.text, "1. Alpha\n2. Beta\n3. Gamma")
            view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            settle()
            XCTAssertEqual(state.text, "1. Alpha\n2. Beta\n3. \n4. Gamma")
        }
    }

    func testSelectedItemsAndDeepNestingRemainEditable() throws {
        try withEditor("1. Root\n2. Beta\n3. Gamma\n4. Last") { state, _, window in
            let view = try XCTUnwrap(state.view)
            window.makeFirstResponder(view)
            let start = (view.string as NSString).range(of: "2. Beta").location
            let end = (view.string as NSString).range(of: "4. Last").location
            view.setSelectedRange(NSRange(location: start, length: end - start))
            view.doCommand(by: #selector(NSResponder.insertTab(_:)))
            settle()
            XCTAssertEqual(state.text, "1. Root\n\t1. Beta\n\t2. Gamma\n2. Last")
            XCTAssertGreaterThan(view.selectedRange().length, 0)
            for _ in 0..<4 { view.doCommand(by: #selector(NSResponder.insertTab(_:))); settle() }
            XCTAssertEqual(state.text, "1. Root\n" + String(repeating: "\t", count: 5) + "1. Beta\n" + String(repeating: "\t", count: 5) + "2. Gamma\n2. Last")
        }
    }

    func testListUndoSurvivesNoteSwitchAndPreservesOpaqueLinks() throws {
        let source = "1. Alpha\n2. Beta [[Name|opaque]] ![[Picture|image|240]]\n3. Gamma"
        try withEditor(source) { state, _, window in
            let view = try XCTUnwrap(state.view)
            window.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: NSMaxRange((view.string as NSString).range(of: "Beta")), length: 0))
            let selection = view.selectedRange()
            let undo = try XCTUnwrap(view.undoManager)
            undo.removeAllActions()
            undo.groupsByEvent = false
            undo.beginUndoGrouping()
            view.doCommand(by: #selector(NSResponder.insertTab(_:)))
            undo.endUndoGrouping()
            settle()
            let edited = "1. Alpha\n\t1. Beta [[Name|opaque]] ![[Picture|image|240]]\n2. Gamma"
            XCTAssertEqual(state.text, edited)
            let originalID = state.noteID
            let otherID = UUID()
            state.retainedIDs.insert(otherID)
            state.noteID = otherID
            state.text = "Other note"
            settle()
            state.noteID = originalID
            state.text = edited
            settle()
            let restored = try XCTUnwrap(state.view)
            restored.undoManager?.undo()
            settle()
            XCTAssertEqual(state.text, source)
            XCTAssertEqual(restored.selectedRange(), selection)
            restored.undoManager?.redo()
            settle()
            XCTAssertEqual(state.text, edited)
        }
    }

    func testListHelpersDoNotRunInCodeOrFindField() throws {
        let source = "1. Alpha\n\n~~~\n2. Code\n~~~"
        try withEditor(source) { state, find, window in
            let view = try XCTUnwrap(state.view)
            window.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: NSMaxRange((view.string as NSString).range(of: "Code")), length: 0))
            view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            settle()
            XCTAssertEqual(state.text, "1. Alpha\n\n~~~\n2. Code\n\n~~~")
            let before = state.text
            find.open()
            settle()
            let fieldEditor = try XCTUnwrap(window.firstResponder as? NSTextView)
            XCTAssertTrue(fieldEditor.isFieldEditor)
            fieldEditor.insertText("2. Query", replacementRange: fieldEditor.selectedRange())
            fieldEditor.doCommand(by: #selector(NSResponder.insertTab(_:)))
            settle()
            XCTAssertEqual(state.text, before)
        }
    }

    func testListCommandsResumeAfterNestedCodeBlock() throws {
        let prefix = "- Parent\n  ```\n  8. Code\n\n"
        try withEditor(prefix + "1. Alpha\n2. Beta\n3. Gamma") { state, _, window in
            let view = try XCTUnwrap(state.view)
            window.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: NSMaxRange((view.string as NSString).range(of: "Beta")), length: 0))
            view.doCommand(by: #selector(NSResponder.insertTab(_:)))
            settle()
            XCTAssertEqual(state.text, prefix + "1. Alpha\n\t1. Beta\n2. Gamma")
            view.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
            settle()
            XCTAssertEqual(state.text, prefix + "1. Alpha\n2. Beta\n3. Gamma")
            view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            settle()
            XCTAssertEqual(state.text, prefix + "1. Alpha\n2. Beta\n3. \n4. Gamma")
        }
    }

    func testPlainTextTabKeepsLiteralEditingBehavior() throws {
        try withEditor("1. Alpha\n2. Beta", markdown: false) { state, _, window in
            let view = try XCTUnwrap(state.view)
            window.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
            view.doCommand(by: #selector(NSResponder.insertTab(_:)))
            settle()
            XCTAssertEqual(state.text, "1. Alpha\n2. Beta\t")
        }
    }

    private func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15)) }

    private func withEditor(_ text: String, markdown: Bool = true,
                            body: (ListEditorState, NoteFindController, NSWindow) throws -> Void) throws {
        let state = ListEditorState(text: text)
        let find = NoteFindController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ListEditorHarness(state: state, find: find, markdown: markdown))
        window.makeKeyAndOrderFront(nil)
        settle()
        defer { find.close(refocus: false); find.detach(); window.contentView = nil; window.close() }
        try body(state, find, window)
    }
}

@MainActor
private final class ListEditorState: ObservableObject {
    @Published var noteID = UUID()
    @Published var text: String
    var retainedIDs: Set<UUID> = []
    weak var view: NSTextView?
    init(text: String) { self.text = text; retainedIDs = [noteID] }
}

private struct ListEditorHarness: View {
    @ObservedObject var state: ListEditorState
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
