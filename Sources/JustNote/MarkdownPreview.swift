import AppKit
import SwiftUI

struct MarkdownPreview: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        let options = AttributedString.MarkdownParsingOptions(allowsExtendedAttributes: true)
        if let attributed = try? NSAttributedString(
            markdown: Data(text.utf8),
            options: options,
            baseURL: nil
        ) {
            textView.textStorage?.setAttributedString(attributed)
        } else {
            textView.string = text
        }

        scrollView.documentView = textView
        configure(textView: textView, in: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        let options = AttributedString.MarkdownParsingOptions(allowsExtendedAttributes: true)
        if let attributed = try? NSAttributedString(
            markdown: Data(text.utf8),
            options: options,
            baseURL: nil
        ) {
            if textView.textStorage?.string != attributed.string {
                textView.textStorage?.setAttributedString(attributed)
            }
        } else if textView.string != text {
            textView.string = text
        }

        configure(textView: textView, in: scrollView)
    }

    private func configure(textView: NSTextView, in scrollView: NSScrollView) {
        guard let textContainer = textView.textContainer else { return }
        textView.isHorizontallyResizable = false
        scrollView.hasHorizontalScroller = false

        textView.minSize = NSSize(width: 0, height: 0)
        textView.autoresizingMask = [.width]
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        var frame = textView.frame
        frame.size.width = scrollView.contentSize.width
        textView.frame = frame
    }
}
