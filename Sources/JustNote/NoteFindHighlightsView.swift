import AppKit

final class NoteFindHighlightsView: NSView {
    struct Mark {
        let range: NSRange
        let rect: NSRect
        let isCurrent: Bool
    }

    private weak var textView: NSTextView?
    private var matches: [NSRange] = []
    private var currentIndex = 0
    private var observers: [NSObjectProtocol] = []

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: textView.bounds)
        autoresizingMask = [.width, .height]
        isHidden = true
        textView.addSubview(self)
        if let clip = textView.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            observe(NSView.boundsDidChangeNotification, object: clip)
        }
        observe(NSTextView.didChangeSelectionNotification, object: textView)
    }

    required init?(coder: NSCoder) { nil }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func update(matches: [NSRange], currentIndex: Int) {
        self.matches = matches
        self.currentIndex = currentIndex
        isHidden = matches.isEmpty
        refresh()
    }

    private func observe(_ name: Notification.Name, object: AnyObject) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            guard self?.isHidden == false else { return }
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        })
    }

    private func refresh() {
        guard !isHidden, let textView else { return }
        frame = textView.bounds
        textView.addSubview(self, positioned: .above, relativeTo: nil)
        needsDisplay = true
    }

    func visibleMarks() -> [Mark] {
        guard !isHidden, let textView, let layout = textView.textLayoutManager,
              let content = layout.textContentManager else { return [] }
        let length = (textView.string as NSString).length
        let viewport = layout.textViewportLayoutController.viewportRange
        let visibleStart = viewport.map { content.offset(from: layout.documentRange.location, to: $0.location) } ?? 0
        let visibleEnd = viewport.map { content.offset(from: layout.documentRange.location, to: $0.endLocation) } ?? length
        var marks: [Mark] = []
        for (index, range) in matches.enumerated() {
            if range.location > visibleEnd { break }
            guard NSMaxRange(range) >= visibleStart, NSMaxRange(range) <= length,
                  let start = content.location(layout.documentRange.location, offsetBy: range.location),
                  let end = content.location(start, offsetBy: range.length),
                  let textRange = NSTextRange(location: start, end: end) else { continue }
            layout.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, rect, _, _ in
                let rect = rect.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
                if rect.width > 1, rect.height > 2, rect.intersects(textView.visibleRect) {
                    marks.append(Mark(range: range, rect: self.convert(rect, from: textView), isCurrent: index == self.currentIndex))
                }
                return true
            }
        }
        return marks
    }

    override func draw(_ dirtyRect: NSRect) {
        for mark in visibleMarks() where mark.rect.intersects(dirtyRect) {
            let color = mark.isCurrent ? NSColor.systemOrange : NSColor.systemYellow
            color.withAlphaComponent(mark.isCurrent ? 0.38 : 0.25).setFill()
            NSBezierPath(roundedRect: mark.rect, xRadius: 2, yRadius: 2).fill()
        }
    }
}
