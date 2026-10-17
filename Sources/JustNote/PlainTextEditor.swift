import AppKit
import SwiftUI

struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    let wrapsLines: Bool
    let fontSize: CGFloat
    var onInteract: (() -> Void)?
    var onRegister: ((NSTextView) -> Void)?

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
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
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
        EditorCommandRouter.shared.register(textView)

        scrollView.documentView = textView
        configure(textView: textView, in: scrollView)
        DispatchQueue.main.async { onRegister?(textView) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EndAnchoredTextView else { return }
        EditorCommandRouter.shared.register(textView)
        textView.onInteract = onInteract
        context.coordinator.text = $text
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
        if textView.font?.pointSize != fontSize {
            textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            textView.sizeToFit()
        }
        configure(textView: textView, in: scrollView)

        if context.coordinator.previousWrapsLines != wrapsLines {
            context.coordinator.previousWrapsLines = wrapsLines
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            textView.sizeToFit()
            scrollView.contentView.scroll(to: .zero)
        }
        DispatchQueue.main.async { onRegister?(textView) }
    }

    private func configure(textView: EndAnchoredTextView, in scrollView: NSScrollView) {
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

        textView.refreshDocumentExtent()
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        (scrollView.documentView as? EndAnchoredTextView)?.stopObservingViewport()
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
    private var isUpdatingExtent = false
    private var viewportObserver: NSObjectProtocol?

    deinit { stopObservingViewport() }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        stopObservingViewport()
        guard let clip = enclosingScrollView?.contentView else { return }
        clip.postsFrameChangedNotifications = true
        viewportObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: clip, queue: nil
        ) { [weak self] _ in
            self?.refreshDocumentExtent()
        }
        refreshDocumentExtent()
    }

    func stopObservingViewport() {
        if let viewportObserver { NotificationCenter.default.removeObserver(viewportObserver) }
        viewportObserver = nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        // TextKit proposes intermediate heights while ensureLayout is still measuring.
        guard !isUpdatingExtent else { return }
        guard enclosingScrollView != nil else {
            super.setFrameSize(newSize)
            return
        }
        let origin = enclosingScrollView?.contentView.bounds.origin
        // Apply a changed wrap width before measuring, retaining height until the padded extent is ready.
        isUpdatingExtent = true
        super.setFrameSize(NSSize(width: newSize.width, height: frame.height))
        isUpdatingExtent = false
        refreshDocumentExtent(preserving: origin)
    }

    override func sizeToFit() {
        refreshDocumentExtent()
    }

    override func didChangeText() {
        super.didChangeText()
        refreshDocumentExtent()
    }

    func refreshDocumentExtent(preserving scrollOrigin: NSPoint? = nil) {
        guard !isUpdatingExtent, let scroll = enclosingScrollView,
              let layoutManager, let textContainer else { return }
        isUpdatingExtent = true
        defer { isUpdatingExtent = false }
        let savedOrigin = scrollOrigin ?? scroll.contentView.bounds.origin
        let viewport = scroll.contentSize
        minSize = NSSize(width: textContainer.widthTracksTextView ? 0 : viewport.width, height: viewport.height)
        if textContainer.widthTracksTextView, abs(frame.width - viewport.width) > 0.5 {
            super.setFrameSize(NSSize(width: viewport.width, height: frame.height))
        }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let extra = layoutManager.extraLineFragmentRect
        let lineHeight = layoutManager.defaultLineHeight(for: font ?? NSFont.systemFont(ofSize: 13))
        let contentHeight = ceil(max(used.maxY, extra.maxY, lineHeight) + textContainerInset.height * 2)
        let height = EditorBottomSpace.documentHeight(
            contentHeight: contentHeight, viewportHeight: viewport.height, lineHeight: lineHeight
        )
        let width = textContainer.widthTracksTextView ? viewport.width
            : max(viewport.width, ceil(used.maxX + textContainerInset.width * 2))
        let size = NSSize(width: width, height: height)
        if abs(size.width - frame.width) > 0.5 || abs(size.height - frame.height) > 0.5 {
            super.setFrameSize(size)
        }
        if frame.origin != .zero { super.setFrameOrigin(.zero) }
        let clip = scroll.contentView
        let origin = NSPoint(x: max(0, min(savedOrigin.x, frame.width - clip.bounds.width)),
                             y: max(0, min(savedOrigin.y, frame.height - clip.bounds.height)))
        if origin != clip.bounds.origin {
            clip.scroll(to: origin)
            scroll.reflectScrolledClipView(clip)
        }
    }

    override func mouseDown(with event: NSEvent) {
        EditorCommandRouter.shared.register(self)
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

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu(title: "Contextual Menu")
        EditorContextMenuBuilder.addFormattingItems(to: menu, mode: .plainText)
        EditorContextMenuBuilder.addFontItems(to: menu)
        return menu
    }
}
