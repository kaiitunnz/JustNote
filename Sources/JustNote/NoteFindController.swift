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
    private var previousValidator: ((NSTextLayoutManager, NSTextLayoutFragment) -> Void)?
    private var revision = 0

    deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
    }

    var status: String {
        query.isEmpty ? "" : matches.isEmpty ? "No matches" : "\(currentIndex + 1) of \(matches.count)"
    }

    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 3, flags == .command || flags == .control {
            guard noteID != nil else { return false }
            open()
            return true
        }
        if event.keyCode == 5, flags == .command || flags == [.command, .shift] {
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
        if let layout = view.textLayoutManager {
            previousValidator = layout.renderingAttributesValidator
            layout.renderingAttributesValidator = { [weak self] layout, fragment in
                self?.previousValidator?(layout, fragment)
                self?.applyHighlights(in: fragment.rangeInElement)
            }
        }
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
        focusRequest += 1
        refresh(reveal: true)
    }

    func close(refocus: Bool = true) {
        revision += 1
        clearHighlights()
        query = ""
        matches = []
        currentIndex = 0
        isVisible = false
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
        clearHighlights()
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
        changeObserver = nil
        textView?.textLayoutManager?.renderingAttributesValidator = previousValidator
        previousValidator = nil
        textView = nil
        matches = []
        currentIndex = 0
    }

    private func scheduleRefresh() {
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
        if reveal { revealCurrentMatch() } else { applyHighlights() }
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
        let bounds = scroll.documentView?.bounds ?? view.bounds
        origin.x = min(max(bounds.minX, origin.x), max(bounds.minX, bounds.maxX - clip.bounds.width))
        origin.y = min(max(bounds.minY, origin.y), max(bounds.minY, bounds.maxY - clip.bounds.height))
        clip.scroll(to: origin)
        scroll.reflectScrolledClipView(clip)
    }

    private func textRange(_ range: NSRange, in layout: NSTextLayoutManager) -> NSTextRange? {
        guard let content = layout.textContentManager,
              let start = content.location(layout.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length) else { return nil }
        return NSTextRange(location: start, end: end)
    }

    private func clearHighlights() {
        guard let view = textView else { return }
        if let layout = view.textLayoutManager {
            layout.removeRenderingAttribute(.backgroundColor, for: layout.documentRange)
        } else {
            view.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: (view.string as NSString).length))
        }
        view.needsDisplay = true
    }

    private func applyHighlights(in fragment: NSTextRange? = nil) {
        guard isVisible, let view = textView else { return }
        for (index, range) in matches.enumerated() {
            guard NSMaxRange(range) <= (view.string as NSString).length else { continue }
            let color = index == currentIndex ? NSColor.systemOrange.withAlphaComponent(0.65) : NSColor.systemYellow.withAlphaComponent(0.4)
            if let layout = view.textLayoutManager, let textRange = textRange(range, in: layout) {
                let target = fragment.flatMap { textRange.intersection($0) } ?? (fragment == nil ? textRange : nil)
                if let target { layout.addRenderingAttribute(.backgroundColor, value: color, for: target) }
            } else {
                view.layoutManager?.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
            }
        }
        if fragment == nil { view.needsDisplay = true }
    }
}
