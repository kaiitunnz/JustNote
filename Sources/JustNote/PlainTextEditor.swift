import AppKit
import SwiftUI

struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    let wrapsLines: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true

        scrollView.documentView = textView
        configure(textView: textView, in: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
        configure(textView: textView, in: scrollView)
    }

    private func configure(textView: NSTextView, in scrollView: NSScrollView) {
        guard let textContainer = textView.textContainer else { return }
        textView.isHorizontallyResizable = !wrapsLines
        scrollView.hasHorizontalScroller = !wrapsLines

        if wrapsLines {
            textView.minSize = NSSize(width: 0, height: 0)
            textView.autoresizingMask = [.width]
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            var frame = textView.frame
            frame.size.width = scrollView.contentSize.width
            textView.frame = frame
        } else {
            textView.minSize = NSSize(width: scrollView.contentSize.width, height: 0)
            textView.autoresizingMask = []
            textContainer.widthTracksTextView = false
            textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            var frame = textView.frame
            frame.size.width = max(frame.size.width, scrollView.contentSize.width)
            textView.frame = frame
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
