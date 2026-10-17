import AppKit
import SwiftUI
import XCTest
@testable import JustNote

@MainActor
final class EditorScrollPastEndTests: XCTestCase {
    func testLongNotesHavePersistentSpaceBelowTheFinalLine() throws {
        for markdown in [false, true] {
            try withEditor(longNote, markdown: markdown) { view, _ in
                let scroll = try XCTUnwrap(view.enclosingScrollView)
                let bottom = try contentBottom(view)
                XCTAssertGreaterThan(view.frame.height - bottom, scroll.contentView.bounds.height * 0.4)
                let document = try XCTUnwrap(scroll.documentView)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: document.frame.height - scroll.contentView.bounds.height))
                scroll.reflectScrolledClipView(scroll.contentView)
                settle()
                let visibleBottom = bottom - view.convert(scroll.contentView.bounds, from: scroll.contentView).minY
                XCTAssertLessThan(visibleBottom, scroll.contentView.bounds.height * 0.65)
                XCTAssertGreaterThan(visibleBottom, scroll.contentView.bounds.height * 0.4)
                XCTAssertEqual(view.string, longNote)
            }
        }
    }

    func testShortAndEmptyNotesKeepTheirNaturalBlankSpace() throws {
        for markdown in [false, true] {
            for source in ["", "One line.", "One line.\n"] {
                try withEditor(source, markdown: markdown) { view, _ in
                    let scroll = try XCTUnwrap(view.enclosingScrollView)
                    XCTAssertEqual(try XCTUnwrap(scroll.documentView).frame.height, scroll.contentView.bounds.height, accuracy: 1)
                    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 1)
                    XCTAssertEqual(view.string, source)
                }
            }
        }
    }

    func testResizingShortNotesDoesNotLeaveStaleMinimumHeight() throws {
        for markdown in [false, true] {
            for wraps in [false, true] where !markdown || wraps {
                try withEditor("Short", markdown: markdown, wraps: wraps) { view, window in
                    window.setContentSize(NSSize(width: 400, height: 250))
                    window.contentView?.layoutSubtreeIfNeeded()
                    settle()
                    let scroll = try XCTUnwrap(view.enclosingScrollView)
                    XCTAssertEqual(try XCTUnwrap(scroll.documentView).frame.height, scroll.contentView.bounds.height, accuracy: 1)
                    XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 1)
                }
            }
        }
    }

    func testHostedExtentsMatchSharedPolicyThroughActivationRamp() throws {
        for markdown in [false, true] {
            for count in [1, 8, 14, 20, 40] {
                let source = Array(repeating: "Line", count: count).joined(separator: "\n")
                try withEditor(source, markdown: markdown) { view, _ in
                    let scroll = try XCTUnwrap(view.enclosingScrollView)
                    let base = ceil(try contentBottom(view) + view.textContainerInset.height)
                    let font = try XCTUnwrap(view.font)
                    let lineHeight = markdown ? ceil(font.ascender - font.descender + font.leading)
                        : try XCTUnwrap(view.layoutManager).defaultLineHeight(for: font)
                    let expected = EditorBottomSpace.documentHeight(contentHeight: base,
                        viewportHeight: scroll.contentView.bounds.height, lineHeight: lineHeight)
                    XCTAssertEqual(try XCTUnwrap(scroll.documentView).frame.height, expected, accuracy: 1)
                }
            }
        }
    }

    func testPlainTextExtentSurvivesTypingUndoAndRepeatedSizing() throws {
        try withEditor(longNote + "\n", markdown: false) { view, _ in
            view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
            let before = view.frame.height
            let scroll = try XCTUnwrap(view.enclosingScrollView)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: before - scroll.contentView.bounds.height))
            let origin = scroll.contentView.bounds.origin
            view.insertText("X", replacementRange: view.selectedRange())
            let typedHeight = view.frame.height
            settle()
            XCTAssertEqual(view.frame.height, typedHeight, accuracy: 1)
            XCTAssertEqual(scroll.contentView.bounds.minY, origin.y, accuracy: 1)
            view.undoManager?.undo()
            settle()
            XCTAssertEqual(view.string, longNote + "\n")
            XCTAssertEqual(view.frame.height, before, accuracy: 1)
            let selection = view.selectedRange()
            for _ in 0..<10 { view.sizeToFit() }
            settle()
            XCTAssertEqual(view.frame.height, before, accuracy: 1)
            XCTAssertEqual(view.selectedRange(), selection)
        }
    }

    func testMarkdownTypingAtTheBottomKeepsCaretVisible() throws {
        try withEditor(longNote + "\n", markdown: true) { view, _ in
            view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
            let before = view.frame.height
            let scroll = try XCTUnwrap(view.enclosingScrollView)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: before - scroll.contentView.bounds.height))
            let origin = scroll.contentView.bounds.origin
            view.insertText("X", replacementRange: view.selectedRange())
            let typedHeight = view.frame.height
            settle()
            XCTAssertEqual(view.frame.height, typedHeight, accuracy: 1)
            XCTAssertEqual(scroll.contentView.bounds.minY, origin.y, accuracy: 1)
            view.undoManager?.undo()
            settle()
            XCTAssertEqual(view.string, longNote + "\n")
            XCTAssertEqual(view.frame.height, before, accuracy: 1)
        }
    }

    func testViewportResizeRefreshesBothEditorsWithAndWithoutWrap() throws {
        for markdown in [false, true] {
            for wraps in [false, true] where !markdown || wraps {
                try withEditor(longNote, markdown: markdown, wraps: wraps) { view, window in
                    let oldHeight = view.frame.height
                    window.setContentSize(NSSize(width: 450, height: 600))
                    window.contentView?.layoutSubtreeIfNeeded()
                    settle()
                    let bottom = try contentBottom(view)
                    XCTAssertGreaterThan(view.frame.height, oldHeight + 80)
                    XCTAssertGreaterThan(view.frame.height - bottom, 250)
                    XCTAssertEqual(view.string, longNote)
                }
            }
        }
    }

    func testExternalReplacementFontAndWrapChangesRefreshPlainExtent() throws {
        try withDocument(longNote, markdown: false) { view, window, document in
            let scroll = try XCTUnwrap(view.enclosingScrollView)
            let initial = view.frame.height
            scroll.contentView.scroll(to: NSPoint(x: 0, y: initial - scroll.contentView.bounds.height))
            document.text = "short"
            settle()
            XCTAssertEqual(try XCTUnwrap(scroll.documentView).frame.height, scroll.contentView.bounds.height, accuracy: 1)
            XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 1)
            document.text = String(repeating: "very long line ", count: 300)
            settle()
            let wrapped = view.frame.height
            document.wraps = false
            settle()
            XCTAssertEqual(try XCTUnwrap(scroll.documentView).frame.height, scroll.contentView.bounds.height, accuracy: 1)
            XCTAssertGreaterThan(view.frame.width, scroll.contentView.bounds.width * 2)
            document.wraps = true
            document.fontSize = 22
            settle()
            XCTAssertGreaterThan(view.frame.height, wrapped)
            window.setContentSize(NSSize(width: 400, height: 400))
            window.contentView?.layoutSubtreeIfNeeded()
            settle()
            XCTAssertGreaterThan(view.frame.height, wrapped)
        }
    }

    func testFinalRenderedBlocksRetainBottomSpace() throws {
        for block in ["| A | B |\n| --- | --- |\n| one | two |", "```swift\nlet value = 42\n```"] {
            try withEditor(longNote + "\n\n" + block, markdown: true) { view, _ in
                let scroll = try XCTUnwrap(view.enclosingScrollView)
                XCTAssertGreaterThan(view.frame.height - (try contentBottom(view)), scroll.contentView.bounds.height * 0.35)
            }
        }
    }

    func testPlainBlankSpaceClickPlacesCaretAtEndWithoutChangingText() throws {
        try withEditor(longNote, markdown: false) { view, window in
            let scroll = try XCTUnwrap(view.enclosingScrollView)
            let bottom = try contentBottom(view)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: view.frame.height - scroll.contentView.bounds.height))
            let origin = scroll.contentView.bounds.origin
            let point = view.convert(NSPoint(x: 30, y: bottom + 50), to: nil)
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            view.mouseDown(with: event)
            settle()
            XCTAssertEqual(view.selectedRange(), NSRange(location: (longNote as NSString).length, length: 0))
            XCTAssertEqual(view.string, longNote)
            XCTAssertEqual(scroll.contentView.bounds.origin, origin)
        }
    }

    private var longNote: String {
        (0..<100).map { "Paragraph \($0): ordinary text.\n" }.joined() + "Final line."
    }

    private func contentBottom(_ view: NSTextView) throws -> CGFloat {
        if let layout = view.textLayoutManager {
            layout.ensureLayout(for: layout.documentRange)
            var bottom: CGFloat = 0
            layout.enumerateTextSegments(in: NSTextRange(location: layout.documentRange.endLocation), type: .standard, options: []) { _, rect, _, _ in
                bottom = rect.maxY
                return false
            }
            return bottom + view.textContainerOrigin.y
        }
        let layout = try XCTUnwrap(view.layoutManager)
        let container = try XCTUnwrap(view.textContainer)
        layout.ensureLayout(for: container)
        return max(layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY) + view.textContainerOrigin.y
    }

    private func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }

    private func withEditor(_ source: String, markdown: Bool, wraps: Bool = true, body: (NSTextView, NSWindow) throws -> Void) throws {
        try withDocument(source, markdown: markdown, wraps: wraps) { view, window, _ in try body(view, window) }
    }

    private func withDocument(_ source: String, markdown: Bool, wraps: Bool = true, body: (NSTextView, NSWindow, Document) throws -> Void) throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let document = Document(source, markdown: markdown, wraps: wraps)
        let root = Harness(document: document)
        let host = NSHostingView(rootView: root)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        settle()
        defer { window.contentView = nil; window.close() }
        try body(XCTUnwrap(host.textViews.first), window, document)
    }

    private final class Document: ObservableObject {
        @Published var text: String
        @Published var fontSize: CGFloat = 13
        @Published var wraps: Bool
        let markdown: Bool
        let id = UUID()
        init(_ text: String, markdown: Bool, wraps: Bool) {
            self.text = text
            self.markdown = markdown
            self.wraps = wraps
        }
    }

    private struct Harness: View {
        @ObservedObject var document: Document
        var body: some View {
            if document.markdown {
                LiveMarkdownEditor(text: $document.text, documentID: document.id, retainedDocumentIDs: [document.id], fontSize: document.fontSize)
            } else {
                PlainTextEditor(text: $document.text, wrapsLines: document.wraps, fontSize: document.fontSize)
            }
        }
    }
}
