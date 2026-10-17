import AppKit
import SwiftUI
import XCTest
@testable import JustNote

@MainActor
final class MarkdownTableViewportTests: XCTestCase {
    func testTypingBelowALargeTablePreservesViewport() throws {
        let source = sample()
        try withEditor(source) { textView in
            let scrollView = try XCTUnwrap(textView.enclosingScrollView)
            let insertion = (source as NSString).range(of: "Following paragraph 10: ordinary text.").upperBound
            textView.setSelectedRange(NSRange(location: insertion, length: 0))
            try position(insertion, in: textView)
            let before = scrollView.contentView.bounds.origin.y
            XCTAssertGreaterThan(before, 500)
            textView.insertText("X", replacementRange: textView.selectedRange())
            XCTAssertEqual(scrollView.contentView.bounds.origin.y, before, accuracy: 1)
            settle()
            XCTAssertEqual(scrollView.contentView.bounds.origin.y, before, accuracy: 1)
        }
    }

    func testLeavingTableKeepsClickedFollowingTextAtItsVisiblePosition() throws {
        let source = sample()
        try withEditor(source) { textView in
            let table = (source as NSString).range(of: "Value for row 79").location
            textView.setSelectedRange(NSRange(location: table, length: 0))
            let after = (source as NSString).range(of: "Following paragraph 1:").location
            try position(after, in: textView)
            let scrollView = try XCTUnwrap(textView.enclosingScrollView)
            let visibleY = try caretY(after, in: textView) - scrollView.contentView.bounds.minY
            textView.setSelectedRange(NSRange(location: after, length: 0))
            let newVisibleY = try caretY(after, in: textView) - scrollView.contentView.bounds.minY
            XCTAssertEqual(newVisibleY, visibleY, accuracy: 1)
            settle()
            XCTAssertEqual(try caretY(after, in: textView) - scrollView.contentView.bounds.minY, visibleY, accuracy: 1)
            XCTAssertEqual(textView.selectedRange(), NSRange(location: after, length: 0))
            XCTAssertEqual(textView.string, source)
        }
    }

    func testKeyboardExitKeepsFollowingTextVisible() throws {
        let source = sample()
        try withEditor(source) { textView in
            let row = (source as NSString).range(of: "| 79 | Value").location
            let after = (source as NSString).range(of: "After table anchor.").location
            textView.setSelectedRange(NSRange(location: row, length: 0))
            try position(after, in: textView)
            let scroll = try XCTUnwrap(textView.enclosingScrollView)
            let visibleY = try caretY(after, in: textView) - scroll.contentView.bounds.minY
            textView.moveDown(nil)
            textView.moveDown(nil)
            settle()
            XCTAssertEqual(textView.selectedRange().location, after)
            XCTAssertEqual(try caretY(after, in: textView) - scroll.contentView.bounds.minY, visibleY, accuracy: 1)
            XCTAssertEqual(textView.string, source)
        }
    }

    func testWrappedWideTableExitAtLargerFontPreservesViewport() throws {
        let header = "| LongColumnOne | LongColumnTwo | LongColumnThree | LongColumnFour | LongColumnFive |\n| --- | --- | --- | --- | --- |\n"
        let source = "Start\n\n" + header
            + (0..<25).map { "| \($0) | LongUnbreakableCell | several words that wrap into lines | more wrapping text here | last |\n" }.joined()
            + "\nAfter wide table.\n\n" + String(repeating: "Following text.\n\n", count: 30)
        try withEditor(source, width: 400, fontSize: 20) { textView in
            let lastRow = (source as NSString).range(of: "| 24 | LongUnbreakableCell").location
            let after = (source as NSString).range(of: "After wide table.").location
            textView.setSelectedRange(NSRange(location: lastRow, length: 0))
            try position(after, in: textView)
            let scroll = try XCTUnwrap(textView.enclosingScrollView)
            let visibleY = try caretY(after, in: textView) - scroll.contentView.bounds.minY
            textView.setSelectedRange(NSRange(location: after, length: 0))
            settle()
            XCTAssertEqual(try caretY(after, in: textView) - scroll.contentView.bounds.minY, visibleY, accuracy: 1)
            XCTAssertEqual(textView.string, source)
        }
    }

    private func sample() -> String {
        "Start\n\n| Row | Description |\n| --- | --- |\n"
            + (0..<80).map { "| \($0) | Value for row \($0) |" }.joined(separator: "\n")
            + "\n\nAfter table anchor.\n\n"
            + (0..<40).map { "Following paragraph \($0): ordinary text.\n\n" }.joined()
    }

    private func caretY(_ offset: Int, in textView: NSTextView) throws -> CGFloat {
        let layout = try XCTUnwrap(textView.textLayoutManager)
        let location = try XCTUnwrap(layout.textContentManager?.location(layout.documentRange.location, offsetBy: offset))
        var y: CGFloat?
        layout.enumerateTextSegments(in: NSTextRange(location: location), type: .standard, options: []) { _, rect, _, _ in
            y = rect.minY
            return false
        }
        return try XCTUnwrap(y)
    }

    private func position(_ offset: Int, in textView: NSTextView) throws {
        let scrollView = try XCTUnwrap(textView.enclosingScrollView)
        let layout = try XCTUnwrap(textView.textLayoutManager)
        layout.ensureLayout(for: layout.documentRange)
        let y = try caretY(offset, in: textView)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y - scrollView.contentView.bounds.height / 3))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        settle()
    }

    private func settle() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }

    private func withEditor(_ source: String, width: CGFloat = 600, fontSize: CGFloat = 13, body: (NSTextView) throws -> Void) throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let documentID = UUID()
        let hostingView = NSHostingView(rootView: LiveMarkdownEditor(
            text: .constant(source), documentID: documentID, retainedDocumentIDs: [documentID], fontSize: fontSize
        ))
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        defer { window.contentView = nil; window.close() }
        settle()
        try body(XCTUnwrap(hostingView.textViews.first))
    }
}
