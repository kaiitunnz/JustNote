import AppKit
import MarkdownEngine
import MarkdownEngineCodeBlocks
import SwiftUI

struct LiveMarkdownEditor: View {
    @Binding var text: String
    let documentID: UUID
    let retainedDocumentIDs: Set<UUID>
    let fontSize: CGFloat
    var onInteract: (() -> Void)?
    var onRegister: ((NSTextView) -> Void)?
    var isCursorExcluded: ((CGPoint) -> Bool)?
    var isInteractionExcluded: ((CGPoint) -> Bool)?
    @State private var codeBlocks: [CodeBlockSelection] = []
    @State private var copiedCodeBlockID: Int?
    @State private var hoveredCodeBlockID: Int?

    // App-lifetime instance: the bridge spins up a JavaScriptCore context and an
    // appearance observer at init, and caches highlights internally. `configuration`
    // is recomputed on every SwiftUI update, so it must hand back this one instance
    // rather than construct a fresh highlighter each render.
    private static let syntaxHighlighter = CodeBlockSyntaxHighlighter()

    var body: some View {
        ZStack(alignment: .topLeading) {
            NativeTextViewWrapper(
                text: $text,
                configuration: configuration,
                fontName: NSFont.systemFont(ofSize: fontSize).fontName,
                fontSize: fontSize,
                documentId: documentID.uuidString,
                onBuildContextMenu: { menu, _ in
                    EditorContextMenuBuilder.addFormattingItems(to: menu, mode: .markdown)
                    EditorContextMenuBuilder.addFontItems(to: menu)
                    return menu
                },
                onCodeBlockSelectionChange: { codeBlocks = $0 },
                retainedScrollDocumentIds: Set(retainedDocumentIDs.map(\.uuidString)),
                isCursorExcluded: isCursorExcluded
            )
            .background(MarkdownInteractionMonitor(documentText: text, onInteract: onInteract, isExcluded: isInteractionExcluded))
            .background(MarkdownSemanticColorizer(documentText: text))

            ForEach(codeBlocks) { selection in
                CodeBlockCopyButton(
                    selection: selection,
                    copied: copiedCodeBlockID == selection.id,
                    visible: hoveredCodeBlockID == selection.id || copiedCodeBlockID == selection.id
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(selection.code, forType: .string)
                    copiedCodeBlockID = selection.id
                    if let app = NSApp {
                        NSAccessibility.post(
                            element: app,
                            notification: .announcementRequested,
                            userInfo: [.announcement: "Copied \(selection.language ?? "code")"]
                        )
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        guard copiedCodeBlockID == selection.id else { return }
                        copiedCodeBlockID = nil
                    }
                }
            }
        }
        .background(MarkdownCodeBlockHoverMonitor(codeBlocks: codeBlocks, hoveredCodeBlockID: $hoveredCodeBlockID))
        .background(EditorTextViewRegistration(documentText: text, onRegister: onRegister))
    }

    private var configuration: MarkdownEditorConfiguration {
        var configuration = MarkdownEditorConfiguration.default
        var services = configuration.services
        services.bus = MarkdownEditorBus(
            applyBoldRequest: EditorFormattingAction.bold.notificationName,
            applyItalicRequest: EditorFormattingAction.italic.notificationName,
            applyHeadingRequest: EditorFormattingAction.heading.notificationName,
            applyStrikethroughRequest: EditorFormattingAction.strikethrough.notificationName,
            applyInlineCodeRequest: EditorFormattingAction.inlineCode.notificationName,
            applyBlockquoteRequest: EditorFormattingAction.blockquote.notificationName,
            applyUnorderedListRequest: EditorFormattingAction.unorderedList.notificationName,
            applyOrderedListRequest: EditorFormattingAction.orderedList.notificationName,
            applyLinkRequest: EditorFormattingAction.link.notificationName,
            applyCodeBlockRequest: EditorFormattingAction.codeBlock.notificationName,
            applyHorizontalRuleRequest: EditorFormattingAction.horizontalRule.notificationName
        )
        services.syntaxHighlighter = Self.syntaxHighlighter
        configuration.services = services
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
        configuration.overscroll = EditorBottomSpace.policy
        return configuration
    }
}

/// Wraps `HighlighterSwiftBridge` to only highlight fenced blocks that name a
/// language. Given no language the bridge auto-detects one, which colors the
/// plain prose in a bare ``` fence as if it were source — so gate that off and
/// let such blocks render as plain monospace on the code background.
final class CodeBlockSyntaxHighlighter: SyntaxHighlighter, @unchecked Sendable {
    private let base = HighlighterSwiftBridge()

    var appearanceDidChangeNotification: Notification.Name? { base.appearanceDidChangeNotification }

    func codeFont(size: CGFloat) -> NSFont { base.codeFont(size: size) }

    func backgroundColor() -> NSColor { base.backgroundColor() }

    func highlight(code: String, language: String?) -> NSAttributedString? {
        guard let language, !language.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return base.highlight(code: code, language: language)
    }
}

private struct MarkdownCodeBlockHoverMonitor: NSViewRepresentable {
    let codeBlocks: [CodeBlockSelection]
    @Binding var hoveredCodeBlockID: Int?

    func makeNSView(context: Context) -> MarkdownCodeBlockHoverMonitorView {
        MarkdownCodeBlockHoverMonitorView { hoveredCodeBlockID = $0 }
    }

    func updateNSView(_ view: MarkdownCodeBlockHoverMonitorView, context: Context) {
        view.codeBlocks = codeBlocks
        view.onHover = { hoveredCodeBlockID = $0 }
        DispatchQueue.main.async {
            view.refreshHover()
        }
    }

    static func dismantleNSView(_ view: MarkdownCodeBlockHoverMonitorView, coordinator: ()) {
        view.stopMonitoring()
    }
}

private final class MarkdownCodeBlockHoverMonitorView: NSView {
    var codeBlocks: [CodeBlockSelection] = []
    var onHover: (Int?) -> Void
    private var eventMonitor: Any?
    private var hoveredCodeBlockID: Int?
    private var originalAcceptsMouseMovedEvents: Bool?
    private weak var monitoredWindow: NSWindow?

    init(onHover: @escaping (Int?) -> Void) {
        self.onHover = onHover
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
        if let originalAcceptsMouseMovedEvents {
            monitoredWindow?.acceptsMouseMovedEvents = originalAcceptsMouseMovedEvents
        }
        originalAcceptsMouseMovedEvents = nil
        monitoredWindow = nil
        setHoveredCodeBlock(nil)
    }

    private func startMonitoring() {
        guard eventMonitor == nil, let window else { return }
        originalAcceptsMouseMovedEvents = window.acceptsMouseMovedEvents
        monitoredWindow = window
        window.acceptsMouseMovedEvents = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.updateHover(for: event)
            return event
        }
    }

    func refreshHover() {
        guard let window else {
            setHoveredCodeBlock(nil)
            return
        }
        updateHover(at: window.convertPoint(fromScreen: NSEvent.mouseLocation))
    }

    private func updateHover(for event: NSEvent) {
        guard let window, event.window === window else { return }
        updateHover(at: event.locationInWindow)
    }

    private func updateHover(at locationInWindow: CGPoint) {
        let appKitLocation = convert(locationInWindow, from: nil)
        guard bounds.contains(appKitLocation) else {
            setHoveredCodeBlock(nil)
            return
        }
        let location = CGPoint(x: appKitLocation.x, y: bounds.height - appKitLocation.y)
        setHoveredCodeBlock(codeBlocks.first(where: { $0.rect.contains(location) })?.id)
    }

    private func setHoveredCodeBlock(_ id: Int?) {
        guard hoveredCodeBlockID != id else { return }
        hoveredCodeBlockID = id
        onHover(id)
    }
}

private struct CodeBlockCopyButton: View {
    let selection: CodeBlockSelection
    let copied: Bool
    let visible: Bool
    let onCopy: () -> Void

    var body: some View {
        Button(action: onCopy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(copied ? Color(nsColor: MarkdownPalette.blue) : Color.primary.opacity(0.72))
                .frame(width: 26, height: 26)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.white.opacity(0.12))
                }
                .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .help(copied ? "Copied" : "Copy \(selection.language ?? "code")")
        .accessibilityHidden(false)
        .accessibilityLabel("Copy \(selection.language ?? "code")")
        .accessibilityValue(copied ? "Copied" : "")
        .position(x: selection.rect.maxX - 21, y: selection.rect.minY + 21)
    }
}

enum MarkdownPalette {
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
    private var styler: MarkdownSemanticStyler?
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
            bindWhenReady()
        }
    }

    func stopObserving() {
        styler = nil
        textView = nil
    }

    func updateDocumentText(_ documentText: String) {
        self.documentText = documentText
        bindWhenReady()
    }

    private func bindWhenReady() {
        guard window != nil else { return }
        if bindTextView() { return }
        // The engine's hosting sibling may not have entered the window yet.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            _ = self.bindTextView()
        }
    }

    @discardableResult
    private func bindTextView() -> Bool {
        guard let textView = matchingTextView(), let storage = textView.textStorage else { return false }
        guard self.textView !== textView || styler == nil else { return true }
        styler = nil
        self.textView = textView
        styler = MarkdownSemanticStyler(storage: storage)
        return true
    }

    private func matchingTextView() -> NSTextView? {
        guard let root = window?.contentView else { return nil }
        return MarkdownEditorDiscovery.editor(in: root, documentText: documentText)
    }
}

enum MarkdownParagraphGapHitTest {
    static func contains(_ point: CGPoint, textView: NSTextView) -> Bool {
        guard let textLayoutManager = textView.textLayoutManager else { return false }
        let containerPoint = CGPoint(
            x: point.x - textView.textContainerOrigin.x,
            y: point.y - textView.textContainerOrigin.y
        )
        guard
            let fragment = textLayoutManager.textLayoutFragment(for: containerPoint),
            let lastLine = fragment.textLineFragments.last
        else { return false }
        let lastLineMaxY = fragment.layoutFragmentFrame.minY + lastLine.typographicBounds.maxY
        return contains(
            y: containerPoint.y,
            lastLineMaxY: lastLineMaxY,
            fragmentMaxY: fragment.layoutFragmentFrame.maxY
        )
    }

    static func contains(y: CGFloat, lastLineMaxY: CGFloat, fragmentMaxY: CGFloat) -> Bool {
        y > lastLineMaxY && y <= fragmentMaxY
    }
}

private struct MarkdownInteractionMonitor: NSViewRepresentable {
    let documentText: String
    var onInteract: (() -> Void)?
    var isExcluded: ((CGPoint) -> Bool)?

    func makeNSView(context: Context) -> MarkdownInteractionMonitorView {
        MarkdownInteractionMonitorView(documentText: documentText, onInteract: onInteract, isExcluded: isExcluded)
    }

    func updateNSView(_ view: MarkdownInteractionMonitorView, context: Context) {
        view.documentText = documentText
        view.onInteract = onInteract
        view.isExcluded = isExcluded
    }

    static func dismantleNSView(_ view: MarkdownInteractionMonitorView, coordinator: ()) {
        view.stopMonitoring()
    }
}

private final class MarkdownInteractionMonitorView: NSView {
    var documentText: String
    var onInteract: (() -> Void)?
    var isExcluded: ((CGPoint) -> Bool)?
    private var eventMonitor: Any?

    init(documentText: String, onInteract: (() -> Void)?, isExcluded: ((CGPoint) -> Bool)?) {
        self.documentText = documentText
        self.onInteract = onInteract
        self.isExcluded = isExcluded
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
            guard let self, let textView = self.markdownTextView(containing: event) else { return event }
            self.onInteract?()
            return self.placeCaretInParagraphGap(for: event, textView: textView) ? nil : event
        }
    }

    private func markdownTextView(containing event: NSEvent) -> NSTextView? {
        guard
            event.window === window,
            isExcluded?(event.locationInWindow) != true,
            let rootView = window?.contentView,
            let textView = MarkdownEditorDiscovery.editor(in: rootView, documentText: documentText),
            let scrollView = textView.enclosingScrollView
        else { return nil }
        let location = scrollView.convert(event.locationInWindow, from: nil)
        return scrollView.bounds.contains(location) ? textView : nil
    }

    private func placeCaretInParagraphGap(for event: NSEvent, textView: NSTextView) -> Bool {
        guard
            event.clickCount == 1,
            event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
            !textView.hasMarkedText()
        else { return false }
        let point = textView.convert(event.locationInWindow, from: nil)
        guard MarkdownParagraphGapHitTest.contains(point, textView: textView) else { return false }

        let insertionIndex = textView.characterIndexForInsertion(at: point)
        guard insertionIndex != NSNotFound else { return false }
        let documentLength = (textView.string as NSString).length
        window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: min(max(insertionIndex, 0), documentLength), length: 0))
        return true
    }

}

extension NSView {
    var textViews: [NSTextView] {
        let ownTextView = (self as? NSTextView).map { [$0] } ?? []
        return ownTextView + subviews.flatMap(\.textViews)
    }
}
