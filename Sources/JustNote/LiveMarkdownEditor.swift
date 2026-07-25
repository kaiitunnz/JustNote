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
        .background(MarkdownSemanticColorizer(documentText: text))
    }

    private var configuration: MarkdownEditorConfiguration {
        var configuration = MarkdownEditorConfiguration.default
        configuration.theme.headingMarker = MarkdownPalette.blue
        configuration.theme.link = MarkdownPalette.blue
        configuration.theme.incompleteLink = MarkdownPalette.orange
        configuration.theme.findMatchHighlight = MarkdownPalette.searchMatch
        configuration.theme.findCurrentMatchHighlight = MarkdownPalette.currentSearchMatch
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
    static let blue = color(light: 0x086DDD, dark: 0x2E80F2)
    static let pink = color(light: 0xC32B74, dark: 0xFF82B2)
    static let teal = color(light: 0x177E89, dark: 0x3EB4BF)
    static let yellow = color(light: 0x9A6A21, dark: 0xE5B567)
    static let orange = color(light: 0xC45D22, dark: 0xE87D3E)
    static let red = color(light: 0xC33131, dark: 0xE83E3E)
    static let purple = color(light: 0x7252A0, dark: 0x9E86C8)
    static let searchMatch = color(light: 0xFFE4A3, dark: 0x5F4D22)
    static let currentSearchMatch = color(light: 0xFFC857, dark: 0x8B6A23)
    static let highlight = color(light: 0xFFF0C2, dark: 0x584618)

    static func headingColor(for level: Int) -> NSColor {
        switch level {
        case 1, 2: .labelColor
        case 3: blue
        case 4: yellow
        case 5: red
        default: .secondaryLabelColor
        }
    }

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

private struct MarkdownSemanticColorizer: NSViewRepresentable {
    let documentText: String

    func makeNSView(context: Context) -> MarkdownSemanticColorizerView {
        MarkdownSemanticColorizerView(documentText: documentText)
    }

    func updateNSView(_ view: MarkdownSemanticColorizerView, context: Context) {
        view.updateDocumentText(documentText)
    }

    static func dismantleNSView(_ view: MarkdownSemanticColorizerView, coordinator: ()) {
        view.stopObserving()
    }
}

private final class MarkdownSemanticColorizerView: NSView {
    private weak var textView: NSTextView?
    private var observers: [NSObjectProtocol] = []
    private var updateScheduled = false
    private var documentText: String

    init(documentText: String) {
        self.documentText = documentText
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

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

    func updateDocumentText(_ documentText: String) {
        self.documentText = documentText
        guard window != nil else { return }
        rebindTextView()
        scheduleUpdate()
    }

    private func startObserving() {
        guard observers.isEmpty else { return }
        guard rebindTextView() else {
            DispatchQueue.main.async { [weak self] in
                self?.startObserving()
            }
            return
        }
        scheduleUpdate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.scheduleUpdate()
        }
    }

    @discardableResult
    private func rebindTextView() -> Bool {
        guard let textView = matchingTextView() else { return false }
        guard self.textView !== textView || observers.isEmpty else { return true }

        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
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
        return true
    }

    private func matchingTextView() -> NSTextView? {
        let normalizedDocumentText = documentText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let textViews = window?.contentView?.textViews ?? []
        return textViews.first {
            $0.string.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") == normalizedDocumentText
        } ?? (window?.firstResponder as? NSTextView) ?? textViews.first
    }

    private func scheduleUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            self.colorMarkdown()
        }
    }

    private func colorMarkdown() {
        _ = rebindTextView()
        guard let textView, let storage = textView.textStorage else { return }
        let text = textView.string as NSString

        storage.beginEditing()
        defer { storage.endEditing() }

        colorHeadings(in: text, storage: storage)
        colorBlockquotes(in: storage)
        colorMatches(Self.strongExpression, color: MarkdownPalette.pink, text: text, storage: storage, requiredTraits: .bold)
        colorMatches(Self.emphasisExpression, color: MarkdownPalette.pink, text: text, storage: storage, requiredTraits: .italic)
        colorMatches(Self.underscoreEmphasisExpression, color: MarkdownPalette.pink, text: text, storage: storage, requiredTraits: .italic)
        colorMatches(Self.inlineCodeExpression, color: MarkdownPalette.purple, text: text, storage: storage, requiresMonospace: true)
    }

    private func colorHeadings(in text: NSString, storage: NSTextStorage) {
        var location = 0
        while location < text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let contentEnd = lineRange.location + lineRange.length - (text.substring(with: lineRange).hasSuffix("\n") ? 1 : 0)
            var markerStart = lineRange.location
            while markerStart < contentEnd, text.character(at: markerStart) == 0x20 || text.character(at: markerStart) == 0x09 {
                markerStart += 1
            }

            var markerEnd = markerStart
            while markerEnd < contentEnd, text.character(at: markerEnd) == 0x23 { markerEnd += 1 }
            let markerCount = markerEnd - markerStart
            let markerRange = NSRange(location: markerStart, length: markerCount)

            if (1...6).contains(markerCount), isHiddenMarker(markerRange, storage: storage) {
                var contentStart = markerEnd
                while contentStart < contentEnd, text.character(at: contentStart) == 0x20 { contentStart += 1 }
                if contentStart < contentEnd {
                    applyForegroundColor(MarkdownPalette.headingColor(for: markerCount), to: NSRange(location: contentStart, length: contentEnd - contentStart), storage: storage)
                }
            }
            location = lineRange.location + lineRange.length
        }
    }

    private func colorBlockquotes(in storage: NSTextStorage) {
        let range = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(Self.blockquoteLevel, in: range, options: []) { value, range, _ in
            guard value != nil else { return }
            applyForegroundColor(MarkdownPalette.teal, to: range, storage: storage)
        }
    }

    private func colorMatches(
        _ expression: NSRegularExpression,
        color: NSColor,
        text: NSString,
        storage: NSTextStorage,
        requiredTraits: NSFontDescriptor.SymbolicTraits? = nil,
        requiresMonospace: Bool = false
    ) {
        let range = NSRange(location: 0, length: text.length)
        expression.matches(in: text as String, range: range).forEach { match in
            let contentRange = match.range(at: 2)
            let openingMarker = match.range(at: 1)
            let closingMarker = NSRange(location: NSMaxRange(match.range) - openingMarker.length, length: openingMarker.length)
            guard
                contentRange.location != NSNotFound,
                isHiddenMarker(openingMarker, storage: storage),
                isHiddenMarker(closingMarker, storage: storage),
                requiredTraits.map({ rangeHasFontTraits(contentRange, traits: $0, storage: storage) }) ?? true,
                !requiresMonospace || rangeHasMonospacedFont(contentRange, storage: storage)
            else { return }
            applyForegroundColor(color, to: contentRange, storage: storage)
        }
    }

    private func applyForegroundColor(_ color: NSColor, to range: NSRange, storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range, options: []) { value, visibleRange, _ in
            guard let font = value as? NSFont, font.pointSize > 1 else { return }
            storage.addAttribute(.foregroundColor, value: color, range: visibleRange)
        }
    }

    private func isHiddenMarker(_ range: NSRange, storage: NSTextStorage) -> Bool {
        guard range.length > 0 else { return false }
        var isHidden = true
        storage.enumerateAttribute(.font, in: range, options: []) { value, _, stop in
            guard let font = value as? NSFont, font.pointSize <= 1 else {
                isHidden = false
                stop.pointee = true
                return
            }
        }
        return isHidden
    }

    private func rangeHasFontTraits(_ range: NSRange, traits: NSFontDescriptor.SymbolicTraits, storage: NSTextStorage) -> Bool {
        guard range.length > 0 else { return false }
        var hasTraits = true
        var hasVisibleText = false
        storage.enumerateAttribute(.font, in: range, options: []) { value, _, stop in
            guard let font = value as? NSFont else {
                hasTraits = false
                stop.pointee = true
                return
            }
            guard font.pointSize > 1 else { return }
            hasVisibleText = true
            guard font.fontDescriptor.symbolicTraits.contains(traits) else {
                hasTraits = false
                stop.pointee = true
                return
            }
        }
        return hasVisibleText && hasTraits
    }

    private func rangeHasMonospacedFont(_ range: NSRange, storage: NSTextStorage) -> Bool {
        rangeHasFontTraits(range, traits: .monoSpace, storage: storage)
    }

    private static let blockquoteLevel = NSAttributedString.Key("BlockquoteLevel")
    private static let strongExpression = try! NSRegularExpression(pattern: #"(?<!\\)(\*\*|__)(.+?)(?<!\\)\1"#)
    private static let emphasisExpression = try! NSRegularExpression(pattern: #"(?<!\\)(?<!\*)(\*)(?!\*)([^*\n]+?)(?<!\\)\1(?!\*)"#)
    private static let underscoreEmphasisExpression = try! NSRegularExpression(pattern: #"(?<!\\)(?<!_)(_)(?!_)([^_\n]+?)(?<!\\)\1(?!_)"#)
    private static let inlineCodeExpression = try! NSRegularExpression(pattern: #"(?<!\\)(`)([^`\n]+)`"#)
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

    var textViews: [NSTextView] {
        let ownTextView = (self as? NSTextView).map { [$0] } ?? []
        return ownTextView + subviews.flatMap(\.textViews)
    }
}
