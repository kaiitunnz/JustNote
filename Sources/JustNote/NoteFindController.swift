import AppKit
import Combine

enum NoteFindMatcher {
    static func ranges(of query: String, in text: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let text = text as NSString
        var result: [NSRange] = []
        var start = 0
        while start < text.length {
            let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive],
                                   range: NSRange(location: start, length: text.length - start))
            guard range.location != NSNotFound, range.length > 0 else { break }
            result.append(range)
            start = NSMaxRange(range)
        }
        return result
    }
}

@MainActor
final class NoteFindController: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var query = ""
    @Published private(set) var matches: [NSRange] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var focusRequest = 0
    private(set) weak var textView: NSTextView?
    private var noteID: UUID?
    private var mode: EditorMode = .markdown
    private var changeObserver: NSObjectProtocol?
    private var highlightsView: NoteFindHighlightsView?
    private var revision = 0
    private var hasHighlights = false
    var overlaySize: CGSize = .zero
    private var originalTopInset: CGFloat?
    private weak var searchField: NSTextField?
    private weak var overlayView: NSView?

    deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
    }

    var status: String {
        query.isEmpty ? "" : matches.isEmpty ? "No matches" : "\(currentIndex + 1) of \(matches.count)"
    }

    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let character = event.charactersIgnoringModifiers?.lowercased()
        if character == "f", flags == .command || flags == .control {
            guard noteID != nil else { return false }
            open()
            return true
        }
        if character == "g", flags == .command || flags == [.command, .shift] {
            guard noteID != nil else { return false }
            move(backward: flags.contains(.shift))
            return true
        }
        if event.keyCode == 53, isVisible {
            close()
            return true
        }
        return false
    }

    func setScope(noteID: UUID?, mode: EditorMode) {
        guard self.noteID != noteID || self.mode != mode else { return }
        detach()
        self.noteID = noteID
        self.mode = mode
        if noteID == nil { close(refocus: false) }
    }

    func bind(_ view: NSTextView, noteID: UUID, mode: EditorMode) {
        guard self.noteID == noteID, self.mode == mode, !view.isFieldEditor else { return }
        guard textView !== view else { return }
        detach()
        textView = view
        changeObserver = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification, object: view, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        refresh(reveal: isVisible)
    }

    func open() {
        guard noteID != nil else { return }
        isVisible = true
        refresh(reveal: true)
        if let searchField, let window = searchField.window, window.makeFirstResponder(searchField) {
            searchField.stringValue = query
            searchField.selectText(nil)
        } else {
            focusRequest += 1
        }
    }

    func registerSearchField(_ field: NSTextField) { searchField = field }

    func registerOverlay(_ view: NSView) { overlayView = view }

    func containsOverlay(_ windowPoint: CGPoint) -> Bool {
        guard isVisible, let overlayView, overlayView.window != nil else { return false }
        return overlayView.bounds.contains(overlayView.convert(windowPoint, from: nil))
    }

    func excludesEditorCursor(at windowPoint: CGPoint) -> Bool {
        guard containsOverlay(windowPoint) else { return false }
        guard let searchField else { return true }
        return !searchField.bounds.contains(searchField.convert(windowPoint, from: nil))
    }

    func close(refocus: Bool = true) {
        revision += 1
        clearHighlights()
        query = ""
        matches = []
        currentIndex = 0
        isVisible = false
        restoreTopInset()
        if refocus, let textView { textView.window?.makeFirstResponder(textView) }
    }

    func setQuery(_ value: String) {
        guard query != value else { return }
        query = value
        currentIndex = 0
        refresh(reveal: true)
    }

    func move(backward: Bool = false) {
        guard isVisible else { open(); return }
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex + (backward ? matches.count - 1 : 1)) % matches.count
        revealCurrentMatch()
    }

    func detach() {
        revision += 1
        matches = []
        clearHighlights()
        restoreTopInset()
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
        changeObserver = nil
        highlightsView?.removeFromSuperview()
        highlightsView = nil
        textView = nil
        matches = []
        currentIndex = 0
    }

    private func scheduleRefresh() {
        guard isVisible, !query.isEmpty else { return }
        revision += 1
        let expected = revision
        DispatchQueue.main.async { [weak self] in
            guard let self, self.revision == expected else { return }
            self.refresh(reveal: false)
        }
    }

    private func refresh(reveal: Bool) {
        revision += 1
        clearHighlights()
        matches = isVisible ? NoteFindMatcher.ranges(of: query, in: textView?.string ?? "") : []
        currentIndex = min(currentIndex, max(0, matches.count - 1))
        if reveal, !matches.isEmpty { revealCurrentMatch() } else { applyHighlights() }
    }

    private func revealCurrentMatch() {
        guard let view = textView, matches.indices.contains(currentIndex) else { return }
        let range = matches[currentIndex]
        guard NSMaxRange(range) <= (view.string as NSString).length else { return }
        // Activating the paragraph first exposes a rendered table even when its matched text is a link.
        if mode == .markdown {
            let paragraph = (view.string as NSString).paragraphRange(for: NSRange(location: range.location, length: 0))
            view.setSelectedRange(NSRange(location: paragraph.location, length: 0))
        }
        view.setSelectedRange(range)
        applyHighlights()
        reveal(range, in: view)
        let expected = revision
        DispatchQueue.main.async { [weak self, weak view] in
            guard let self, let view, self.revision == expected, self.textView === view,
                  self.isVisible, self.matches.indices.contains(self.currentIndex),
                  self.matches[self.currentIndex] == range else { return }
            self.applyHighlights()
            self.reveal(range, in: view)
        }
    }

    private func reveal(_ range: NSRange, in view: NSTextView) {
        guard let scroll = view.enclosingScrollView else { return }
        var rect: NSRect?
        if let layout = view.textLayoutManager, let textRange = textRange(range, in: layout) {
            layout.ensureLayout(for: textRange)
            layout.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
                rect = frame
                return false
            }
        } else if let layout = view.layoutManager, let container = view.textContainer {
            layout.ensureLayout(for: container)
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        }
        guard var rect else { return }
        rect.origin.x += view.textContainerOrigin.x
        rect.origin.y += view.textContainerOrigin.y
        rect = scroll.documentView?.convert(rect, from: view) ?? rect
        let clip = scroll.contentView
        var origin = clip.bounds.origin
        let margin: CGFloat = 12
        if rect.minY < clip.bounds.minY + margin { origin.y = rect.minY - margin }
        else if rect.maxY > clip.bounds.maxY - margin { origin.y = rect.maxY - clip.bounds.height + margin }
        if rect.minX < clip.bounds.minX + margin { origin.x = rect.minX - margin }
        else if rect.maxX > clip.bounds.maxX - margin { origin.x = rect.maxX - clip.bounds.width + margin }
        let overlayBottom = overlaySize.height + 16
        if overlaySize.width > 0, rect.maxX > origin.x + clip.bounds.width - overlaySize.width - 16,
           rect.minY < origin.y + overlayBottom {
            if originalTopInset == nil { originalTopInset = scroll.contentInsets.top }
            var insets = scroll.contentInsets
            insets.top = max(insets.top, overlayBottom)
            scroll.contentInsets = insets
            origin.y = rect.minY - overlayBottom
        }
        let bounds = scroll.documentView?.bounds ?? view.bounds
        origin.x = min(max(bounds.minX, origin.x), max(bounds.minX, bounds.maxX - clip.bounds.width))
        origin.y = min(max(bounds.minY - scroll.contentInsets.top, origin.y), max(bounds.minY, bounds.maxY - clip.bounds.height))
        clip.scroll(to: origin)
        scroll.reflectScrolledClipView(clip)
    }

    private func restoreTopInset() {
        guard let originalTopInset else { return }
        self.originalTopInset = nil
        guard let scroll = textView?.enclosingScrollView else { return }
        let origin = scroll.contentView.bounds.origin
        var insets = scroll.contentInsets
        insets.top = originalTopInset
        scroll.contentInsets = insets
        scroll.contentView.scroll(to: NSPoint(x: origin.x, y: max(-originalTopInset, origin.y)))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func textRange(_ range: NSRange, in layout: NSTextLayoutManager) -> NSTextRange? {
        guard let content = layout.textContentManager,
              let start = content.location(layout.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length) else { return nil }
        return NSTextRange(location: start, end: end)
    }

    private func clearHighlights() {
        highlightsView?.update(matches: [], currentIndex: 0)
        guard hasHighlights else { return }
        hasHighlights = false
        guard let view = textView, view.textLayoutManager == nil else { return }
        view.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: (view.string as NSString).length))
    }

    private func applyHighlights() {
        guard isVisible, let view = textView else { return }
        if view.textLayoutManager != nil {
            if highlightsView == nil { highlightsView = NoteFindHighlightsView(textView: view) }
            highlightsView?.update(matches: matches, currentIndex: currentIndex)
        } else {
            hasHighlights = !matches.isEmpty
            for (index, range) in matches.enumerated() {
                guard NSMaxRange(range) <= (view.string as NSString).length else { continue }
                let color = index == currentIndex ? NSColor.systemOrange.withAlphaComponent(0.65) : NSColor.systemYellow.withAlphaComponent(0.4)
                view.layoutManager?.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
            }
        }
    }
}
