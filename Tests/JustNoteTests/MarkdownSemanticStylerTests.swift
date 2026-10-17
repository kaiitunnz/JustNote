import AppKit
import SwiftUI
import XCTest
@testable import JustNote

@MainActor
final class MarkdownSemanticStylerTests: XCTestCase {
    func testTypingKeepsSemanticColorBeforeReturningToTheRunLoop() throws {
        let source = "Start\n\n**bold** and ordinary text\n\nEnd"
        try withEditor(source) { textView, document in
            let storage = try XCTUnwrap(textView.textStorage)
            let bold = (source as NSString).range(of: "bold")
            let originalColor = try foreground(in: storage, at: bold.location)
            XCTAssertEqual(originalColor, MarkdownPalette.pink)
            let insertionPoint = (source as NSString).range(of: "ordinary text").upperBound
            textView.setSelectedRange(NSRange(location: insertionPoint, length: 0))
            settle()
            textView.insertText("!", replacementRange: textView.selectedRange())
            XCTAssertEqual(try foreground(in: storage, at: bold.location), originalColor)
            settle()
            XCTAssertEqual(document.text, source.replacingOccurrences(of: "ordinary text", with: "ordinary text!"))
        }
    }

    func testPaletteIsFinalBeforeLayoutReceivesTheEngineTransaction() throws {
        let source = "Start\n\n**bold** and `inline`\n\nEnd"
        try withEditor(source) { textView, _ in
            let storage = try XCTUnwrap(textView.textStorage)
            let bold = (source as NSString).range(of: "bold")
            let recorder = StorageRecorder()
            recorder.onProcessed = { storage in
                XCTAssertEqual(storage.attribute(.foregroundColor, at: bold.location, effectiveRange: nil) as? NSColor, MarkdownPalette.pink)
            }
            storage.delegate = recorder
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: (source as NSString).paragraphRange(for: bold))
            storage.endEditing()
            XCTAssertEqual(recorder.processedCount, 1)
            settle()
            XCTAssertEqual(recorder.processedCount, 1, "Palette application must not queue a second storage/layout edit")
        }
    }

    func testMarkerRevealAndRehidePreserveInlineAndFencedCodeStyling() throws {
        let source = "Start\n\n**bold** and *italic* and `inline`\n\n```swift\nlet value = 42\n```\n\nEnd"
        try withEditor(source) { textView, _ in
            let storage = try XCTUnwrap(textView.textStorage)
            let bold = (source as NSString).range(of: "bold")
            let inline = (source as NSString).range(of: "inline")
            let fenced = (source as NSString).range(of: "let value")
            XCTAssertEqual(try foreground(in: storage, at: inline.location), MarkdownPalette.purple)
            XCTAssertNil(storage.attribute(.backgroundColor, at: inline.location, effectiveRange: nil))
            let codeBackground = try XCTUnwrap(storage.attribute(.backgroundColor, at: fenced.location, effectiveRange: nil) as? NSColor)
            XCTAssertGreaterThan(codeBackground.alphaComponent, 0.5)
            textView.setSelectedRange(NSRange(location: bold.location + 1, length: 0))
            XCTAssertEqual(try foreground(in: storage, at: bold.location), NSColor.labelColor)
            textView.setSelectedRange(NSRange(location: storage.length, length: 0))
            XCTAssertEqual(try foreground(in: storage, at: bold.location), MarkdownPalette.pink)
            XCTAssertEqual(storage.attribute(.backgroundColor, at: fenced.location, effectiveRange: nil) as? NSColor, codeBackground)
            XCTAssertNil(storage.attribute(.backgroundColor, at: inline.location, effectiveRange: nil))
        }
    }

    func testUnchangedTokenSelectionDoesNotProduceStorageEdits() throws {
        let source = "Start\n\n**bold** and ordinary text\n\nEnd"
        try withEditor(source) { textView, _ in
            let location = (source as NSString).range(of: "ordinary").location
            textView.setSelectedRange(NSRange(location: location, length: 0))
            settle()
            let storage = try XCTUnwrap(textView.textStorage)
            let recorder = StorageRecorder()
            storage.delegate = recorder
            textView.setSelectedRange(NSRange(location: location + 1, length: 0))
            settle()
            XCTAssertEqual(recorder.processedCount, 0)
        }
    }

    func testUnicodeEditingUndoAndAppearanceKeepTheSemanticPalette() throws {
        let source = "Start\n\n**café 🧑🏽‍💻** and ordinary text\n\nEnd"
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try withEditor(source, appearance: appearance) { textView, _ in
                let storage = try XCTUnwrap(textView.textStorage)
                let emphasized = (source as NSString).range(of: "café")
                let insertion = (source as NSString).range(of: "ordinary text").upperBound
                textView.setSelectedRange(NSRange(location: insertion, length: 0))
                for _ in 0..<12 {
                    textView.insertText("é", replacementRange: textView.selectedRange())
                    XCTAssertEqual(try foreground(in: storage, at: emphasized.location), MarkdownPalette.pink)
                }
                settle()
                textView.breakUndoCoalescing()
                textView.undoManager?.undo()
                settle()
                XCTAssertEqual(textView.string, source)
                XCTAssertEqual(try foreground(in: storage, at: emphasized.location), MarkdownPalette.pink)
                textView.undoManager?.redo()
                XCTAssertTrue(textView.string.contains("ordinary text" + String(repeating: "é", count: 12)))
                XCTAssertEqual(try foreground(in: storage, at: emphasized.location), MarkdownPalette.pink)
            }
        }
    }

    func testEditingAndCaretMovementPreserveAScrolledViewport() throws {
        let source = (0..<180).map { "Paragraph \($0): **bold** and ordinary text.\n\n" }.joined()
        try withEditor(source) { textView, _ in
            let scrollView = try XCTUnwrap(textView.enclosingScrollView)
            let layout = try XCTUnwrap(textView.textLayoutManager)
            layout.ensureLayout(for: layout.documentRange)
            for paragraph in [85, 170] {
                let line = (textView.string as NSString).range(of: "Paragraph \(paragraph):")
                let insertion = line.upperBound + 22
                textView.setSelectedRange(NSRange(location: insertion, length: 0))
                let location = try XCTUnwrap(layout.textContentManager?.location(layout.documentRange.location, offsetBy: insertion))
                var targetY: CGFloat?
                layout.enumerateTextLayoutFragments(from: location, options: [.ensuresLayout]) { fragment in
                    targetY = fragment.layoutFragmentFrame.minY - scrollView.contentView.bounds.height / 3
                    return false
                }
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: try XCTUnwrap(targetY)))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                settle()
                let origin = scrollView.contentView.bounds.origin
                XCTAssertGreaterThan(origin.y, 0)
                textView.insertText("!", replacementRange: textView.selectedRange())
                XCTAssertEqual(scrollView.contentView.bounds.origin.y, origin.y, accuracy: 1)
                textView.deleteBackward(nil)
                textView.setSelectedRange(NSRange(location: insertion + 1, length: 0))
                XCTAssertEqual(scrollView.contentView.bounds.origin.y, origin.y, accuracy: 1)
                settle()
                XCTAssertEqual(scrollView.contentView.bounds.origin.y, origin.y, accuracy: 1)
            }
        }
    }

    func testStylerReleasesItsStorageObservation() throws {
        let storage = NSTextStorage(string: "**bold**")
        storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 13), range: NSRange(location: 0, length: storage.length))
        var styler: MarkdownSemanticStyler? = MarkdownSemanticStyler(storage: storage)
        weak var reference = styler
        XCTAssertNotNil(reference)
        styler = nil
        XCTAssertNil(reference)
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: storage.length))
        XCTAssertEqual(try foreground(in: storage, at: 2), NSColor.labelColor)
    }

    func testEngineRestylePreservesHeadingEmphasisAndQuoteColors() throws {
        let source = "Start\n\n### Blue heading\n\n*italic* and ordinary text\n\n> Quoted text\n\nEnd"
        try withEditor(source) { textView, _ in
            let storage = try XCTUnwrap(textView.textStorage)
            let examples: [(String, NSColor)] = [
                ("Blue heading", MarkdownPalette.blue),
                ("italic", MarkdownPalette.pink),
                ("Quoted text", MarkdownPalette.teal)
            ]
            for (content, color) in examples {
                let range = (source as NSString).range(of: content)
                XCTAssertEqual(try foreground(in: storage, at: range.location), color)
                storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
                XCTAssertEqual(try foreground(in: storage, at: range.location), color)
            }
        }
    }

    private func foreground(in storage: NSTextStorage, at index: Int) throws -> NSColor {
        try XCTUnwrap(storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor)
    }

    private func settle() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }

    private func withEditor(
        _ source: String,
        appearance: NSAppearance.Name = .aqua,
        body: (NSTextView, Document) throws -> Void
    ) throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        let document = Document(source)
        let documentID = UUID()
        let hostingView = NSHostingView(rootView: LiveMarkdownEditor(
            text: Binding(get: { document.text }, set: { document.text = $0 }),
            documentID: documentID,
            retainedDocumentIDs: [documentID],
            fontSize: 13
        ))
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        defer {
            window.contentView = nil
            window.close()
        }
        settle()
        try body(XCTUnwrap(hostingView.textViews.first), document)
    }

    private final class Document {
        var text: String
        init(_ text: String) { self.text = text }
    }

    private final class StorageRecorder: NSObject, NSTextStorageDelegate {
        var processedCount = 0
        var onProcessed: ((NSTextStorage) -> Void)?

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            processedCount += 1
            onProcessed?(textStorage)
        }
    }
}
