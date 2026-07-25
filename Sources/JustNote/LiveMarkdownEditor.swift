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
        .background(MarkdownHeadingColorizer())
    }

    private var configuration: MarkdownEditorConfiguration {
        var configuration = MarkdownEditorConfiguration.default
        configuration.theme.headingMarker = MarkdownPalette.accent
        configuration.theme.link = MarkdownPalette.accent
        configuration.theme.incompleteLink = MarkdownPalette.incompleteLink
        configuration.theme.findMatchHighlight = MarkdownPalette.findMatch
        configuration.theme.findCurrentMatchHighlight = MarkdownPalette.currentFindMatch
        configuration.theme.strikethroughColor = .secondaryLabelColor
        configuration.theme.highlightColor = MarkdownPalette.highlight
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

private enum MarkdownPalette {
    static let accent = color(light: 0x3D6FB8, dark: 0x7AA8F8)
    static let incompleteLink = color(light: 0xA65E1C, dark: 0xF0A15E)
    static let findMatch = color(light: 0xD8E7FF, dark: 0x334A72)
    static let currentFindMatch = color(light: 0xA9CCFF, dark: 0x456AA0)
    static let highlight = color(light: 0xFFF0B3, dark: 0x66531C)

    private static func color(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? nsColor(dark)
                : nsColor(light)
        }
    }

    private static func nsColor(_ hex: Int) -> NSColor {
        NSColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

private struct MarkdownHeadingColorizer: NSViewRepresentable {
    func makeNSView(context: Context) -> MarkdownHeadingColorizerView {
        MarkdownHeadingColorizerView()
    }

    func updateNSView(_ view: MarkdownHeadingColorizerView, context: Context) {}

    static func dismantleNSView(_ view: MarkdownHeadingColorizerView, coordinator: ()) {
        view.stopObserving()
    }
}

private final class MarkdownHeadingColorizerView: NSView {
    private weak var textView: NSTextView?
    private var observers: [NSObjectProtocol] = []
    private var updateScheduled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopObserving()
        } else {
            startObserving()
        }
    }

    deinit {
        stopObserving()
    }

    func stopObserving() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        textView = nil
        updateScheduled = false
    }

    private func startObserving() {
        guard observers.isEmpty else { return }
        guard let textView = window?.contentView?.firstTextView else {
            DispatchQueue.main.async { [weak self] in
                self?.startObserving()
            }
            return
        }
        self.textView = textView
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSText.didChangeNotification, object: textView, queue: .main) { [weak self] _ in
                self?.scheduleUpdate()
            },
            center.addObserver(forName: NSTextView.didChangeSelectionNotification, object: textView, queue: .main) { [weak self] _ in
                self?.scheduleUpdate()
            }
        ]
        scheduleUpdate()
    }

    private func scheduleUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            self.colorHeadings()
        }
    }

    private func colorHeadings() {
        guard let textView, let storage = textView.textStorage else { return }
        let text = textView.string as NSString
        var location = 0

        while location < text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let contentEnd = lineRange.location + lineRange.length - (text.substring(with: lineRange).hasSuffix("\n") ? 1 : 0)
            var markerEnd = lineRange.location

            while markerEnd < contentEnd, text.character(at: markerEnd) == 0x23 {
                markerEnd += 1
            }

            let markerCount = markerEnd - lineRange.location
            if (1...6).contains(markerCount), markerEnd < contentEnd, text.character(at: markerEnd) == 0x20 {
                let headingRange = NSRange(location: markerEnd + 1, length: contentEnd - markerEnd - 1)
                storage.addAttribute(.foregroundColor, value: MarkdownPalette.accent, range: headingRange)
            }

            location = lineRange.location + lineRange.length
        }
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
