import AppKit
import MarkdownEngine
import SwiftUI

struct LiveMarkdownEditor: View {
    @Binding var text: String
    let documentID: UUID
    var onInteract: (() -> Void)?

    var body: some View {
        NativeTextViewWrapper(
            text: $text,
            configuration: configuration,
            fontName: NSFont.systemFont(ofSize: 13).fontName,
            fontSize: 13,
            documentId: documentID.uuidString
        )
        .background(MarkdownInteractionMonitor(onInteract: onInteract))
    }

    private var configuration: MarkdownEditorConfiguration {
        var configuration = MarkdownEditorConfiguration.default
        configuration.theme.link = NSColor(Theme.accent)
        configuration.theme.incompleteLink = NSColor(Theme.accent).withAlphaComponent(0.7)
        configuration.theme.headingMarker = .secondaryLabelColor
        configuration.headings = HeadingStyle(
            fontMultipliers: [1.55, 1.32, 1.18, 1.08, 1, 1],
            topSpacingEm: [0.25, 0.22, 0.20, 0.16, 0.14, 0.12]
        )
        configuration.paragraph = ParagraphStyle(spacingFactor: 0.16, lineHeightExtraSpacing: 1)
        configuration.textInsets = TextInsets(horizontal: 10, vertical: 10)
        configuration.overscroll = OverscrollPolicy(percent: 0, maxPoints: 0, minPoints: 0)
        return configuration
    }
}

private struct MarkdownInteractionMonitor: NSViewRepresentable {
    var onInteract: (() -> Void)?

    func makeNSView(context: Context) -> MarkdownInteractionMonitorView {
        MarkdownInteractionMonitorView(onInteract: onInteract)
    }

    func updateNSView(_ view: MarkdownInteractionMonitorView, context: Context) {
        view.onInteract = onInteract
    }

    static func dismantleNSView(_ view: MarkdownInteractionMonitorView, coordinator: ()) {
        view.stopMonitoring()
    }
}

private final class MarkdownInteractionMonitorView: NSView {
    var onInteract: (() -> Void)?
    private var eventMonitor: Any?

    init(onInteract: (() -> Void)?) {
        self.onInteract = onInteract
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    deinit {
        stopMonitoring()
    }

    func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func startMonitoring() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self, self.containsMarkdownEditor(event) else { return event }
            self.onInteract?()
            return event
        }
    }

    private func containsMarkdownEditor(_ event: NSEvent) -> Bool {
        guard
            let rootView = window?.contentView,
            let textView = rootView.firstTextView,
            let scrollView = textView.enclosingScrollView
        else { return false }
        let location = scrollView.convert(event.locationInWindow, from: nil)
        return scrollView.bounds.contains(location)
    }
}

private extension NSView {
    var firstTextView: NSTextView? {
        if let textView = self as? NSTextView { return textView }
        for subview in subviews {
            if let textView = subview.firstTextView { return textView }
        }
        return nil
    }
}
