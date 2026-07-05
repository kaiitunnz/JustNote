import AppKit
import SwiftUI

struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    let wrapsLines: Bool
    var onInteract: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = EndAnchoredTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.onInteract = onInteract
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
        guard let textView = scrollView.documentView as? EndAnchoredTextView else { return }
        textView.onInteract = onInteract
        context.coordinator.text = $text
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
        configure(textView: textView, in: scrollView)

        if context.coordinator.previousWrapsLines != wrapsLines {
            context.coordinator.previousWrapsLines = wrapsLines
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            textView.sizeToFit()
            scrollView.contentView.scroll(to: .zero)
        }
    }

    private func configure(textView: NSTextView, in scrollView: NSScrollView) {
        guard let textContainer = textView.textContainer else { return }
        textView.isHorizontallyResizable = !wrapsLines
        scrollView.hasHorizontalScroller = !wrapsLines

        let visibleHeight = scrollView.contentSize.height

        if wrapsLines {
            textView.minSize = NSSize(width: 0, height: visibleHeight)
            textView.autoresizingMask = [.width]
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            var frame = textView.frame
            frame.size.width = scrollView.contentSize.width
            textView.frame = frame
        } else {
            textView.minSize = NSSize(width: scrollView.contentSize.width, height: visibleHeight)
            textView.autoresizingMask = []
            textContainer.widthTracksTextView = false
            textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            var frame = textView.frame
            frame.size.width = max(frame.size.width, scrollView.contentSize.width)
            textView.frame = frame
        }

        // Fill the visible height so a click in the empty area below the text still lands in the
        // text view — placing the insertion point at the end — instead of hitting dead space.
        if textView.frame.height < visibleHeight {
            textView.frame.size.height = visibleHeight
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var previousWrapsLines: Bool?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

// Clicking the empty area below the text jumps straight to the end of the text, without the
// intermediate caret placement NSTextView would otherwise show there (which reads as a flicker).
final class EndAnchoredTextView: NSTextView {
    var onInteract: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onInteract?()
        guard let layoutManager, let textContainer else {
            super.mouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let contentBottom = layoutManager.usedRect(for: textContainer).maxY + textContainerInset.height
        if point.y > contentBottom {
            window?.makeFirstResponder(self)
            setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
            return
        }
        super.mouseDown(with: event)
    }
}
