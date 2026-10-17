import AppKit

final class MarkdownSemanticStyler {
    private weak var storage: NSTextStorage?
    private var observer: NSObjectProtocol?
    private var isApplying = false

    init(storage: NSTextStorage) {
        self.storage = storage
        // Finish the palette in the engine's transaction, before TextKit lays out
        // its base-color reset. A deferred text/selection observer exposes that reset.
        observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.willProcessEditingNotification,
            object: storage,
            queue: nil
        ) { [weak self] _ in
            guard let self, let storage = self.storage else { return }
            self.apply(in: storage.editedRange)
        }
        apply(in: NSRange(location: 0, length: storage.length))
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func apply(in editedRange: NSRange) {
        guard !isApplying, let storage, storage.length > 0, editedRange.location != NSNotFound else { return }
        isApplying = true
        defer { isApplying = false }
        let text = storage.string as NSString
        let location = min(editedRange.location, text.length)
        let clipped = NSRange(location: location, length: min(editedRange.length, text.length - location))
        let range = text.paragraphRange(for: clipped)

        storage.beginEditing()
        defer { storage.endEditing() }
        colorHeadings(in: text, range: range, storage: storage)
        colorBlockquotes(in: storage, range: range)
        colorMatches(Self.strongExpression, color: MarkdownPalette.pink, text: text, storage: storage, range: range, requiredTraits: .bold)
        colorMatches(Self.emphasisExpression, color: MarkdownPalette.pink, text: text, storage: storage, range: range, requiredTraits: .italic)
        colorMatches(Self.underscoreEmphasisExpression, color: MarkdownPalette.pink, text: text, storage: storage, range: range, requiredTraits: .italic)
        colorMatches(Self.inlineCodeExpression, color: MarkdownPalette.purple, text: text, storage: storage, range: range, requiresMonospace: true, clearsBackground: true)
    }

    private func colorHeadings(in text: NSString, range: NSRange, storage: NSTextStorage) {
        var location = range.location
        while location < NSMaxRange(range) {
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

    private func colorBlockquotes(in storage: NSTextStorage, range: NSRange) {
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
        range: NSRange,
        requiredTraits: NSFontDescriptor.SymbolicTraits? = nil,
        requiresMonospace: Bool = false,
        clearsBackground: Bool = false
    ) {
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
            // The engine fills inline `code` with the fenced-block background
            // (a single shared color, no separate knob); that opaque box reads
            // badly on inline spans, so strip it here. The hidden-marker guard
            // above keeps this off fenced-block content, whose full-width fill
            // depends on that background attribute staying put.
            if clearsBackground {
                clearBackground(in: contentRange, storage: storage)
            }
        }
    }

    private func clearBackground(in range: NSRange, storage: NSTextStorage) {
        // Even removing a nonexistent attribute invalidates TextKit layout.
        var spans: [NSRange] = []
        storage.enumerateAttribute(.backgroundColor, in: range, options: []) { value, spanRange, _ in
            if value != nil { spans.append(spanRange) }
        }
        for span in spans {
            storage.removeAttribute(.backgroundColor, range: span)
        }
    }

    private func applyForegroundColor(_ color: NSColor, to range: NSRange, storage: NSTextStorage) {
        // Avoid no-op layout invalidation. Collect before writing so attribute
        // mutations cannot change the runs being enumerated.
        var pending: [NSRange] = []
        storage.enumerateAttribute(.font, in: range, options: []) { value, fontRange, _ in
            guard let font = value as? NSFont, font.pointSize > 1 else { return }
            var location = fontRange.location
            let end = NSMaxRange(fontRange)
            while location < end {
                var effective = NSRange(location: 0, length: 0)
                let current = storage.attribute(.foregroundColor, at: location, longestEffectiveRange: &effective, in: fontRange) as? NSColor
                if current !== color { pending.append(effective) }
                location = NSMaxRange(effective)
            }
        }
        for span in pending {
            storage.addAttribute(.foregroundColor, value: color, range: span)
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
