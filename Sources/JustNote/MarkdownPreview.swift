import AppKit
import SwiftUI

struct MarkdownPreview: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        textView.textStorage?.setAttributedString(MarkdownRenderer.render(text))

        scrollView.documentView = textView
        configure(textView: textView, in: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if context.coordinator.sourceText != text {
            textView.textStorage?.setAttributedString(MarkdownRenderer.render(text))
            context.coordinator.sourceText = text
        }

        configure(textView: textView, in: scrollView)
    }

    private func configure(textView: NSTextView, in scrollView: NSScrollView) {
        guard let textContainer = textView.textContainer else { return }
        textView.isHorizontallyResizable = false
        scrollView.hasHorizontalScroller = false

        textView.minSize = NSSize(width: 0, height: 0)
        textView.autoresizingMask = [.width]
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        var frame = textView.frame
        frame.size.width = scrollView.contentSize.width
        textView.frame = frame
    }

    final class Coordinator {
        var sourceText: String

        init(text: String) {
            self.sourceText = text
        }
    }
}

enum MarkdownRenderer {
    private static let baseSize: CGFloat = 13

    static func render(_ text: String) -> NSAttributedString {
        var options = AttributedString.MarkdownParsingOptions(allowsExtendedAttributes: true)
        options.interpretedSyntax = .full
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return NSAttributedString(string: text, attributes: [
                .font: font(size: baseSize, bold: false, italic: false),
                .foregroundColor: NSColor.labelColor
            ])
        }

        let result = NSMutableAttributedString()
        var currentBlockID: Int?
        var currentListItemID: Int?
        var previousWasListItem = false

        for run in parsed.runs {
            let intent = run.presentationIntent
            let block = Block(intent)
            let blockID = intent?.components.first?.identity

            if blockID != currentBlockID {
                if result.length > 0 {
                    let separator = (previousWasListItem && block.isListItem) ? "\n" : "\n\n"
                    result.append(NSAttributedString(string: separator, attributes: baseAttributes))
                }
                currentBlockID = blockID
                previousWasListItem = block.isListItem

                let startsNewItem = block.isListItem && block.listItemID != currentListItemID
                currentListItemID = block.isListItem ? block.listItemID : nil

                appendPrefix(for: block, startsNewItem: startsNewItem, to: result)
            }

            if block.isThematicBreak { continue }

            result.append(styledRun(run, in: parsed, block: block))
        }

        return result
    }

    private static func appendPrefix(for block: Block, startsNewItem: Bool, to result: NSMutableAttributedString) {
        if block.isThematicBreak {
            result.append(NSAttributedString(string: String(repeating: "─", count: 24), attributes: [
                .font: font(size: baseSize, bold: false, italic: false),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]))
        } else if block.isListItem {
            let indent = String(repeating: "    ", count: max(block.indentationLevel - 1, 0))
            let marker = block.orderedList ? "\(block.ordinal). " : "• "
            // Continuation blocks of the same item align under the text instead of repeating the marker.
            let prefix = startsNewItem ? marker : String(repeating: " ", count: marker.count)
            result.append(NSAttributedString(string: indent + prefix, attributes: [
                .font: font(size: baseSize, bold: false, italic: false),
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
        } else if block.isBlockQuote {
            result.append(NSAttributedString(string: "│ ", attributes: [
                .font: font(size: baseSize, bold: false, italic: false),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]))
        }
    }

    private static func styledRun(_ run: AttributedString.Runs.Run, in parsed: AttributedString, block: Block) -> NSAttributedString {
        let inline = run.inlinePresentationIntent ?? []
        let size = block.headerLevel.map(headerSize) ?? baseSize
        let bold = block.headerLevel != nil || inline.contains(.stronglyEmphasized)
        let italic = inline.contains(.emphasized)

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(size: size, bold: bold, italic: italic),
            .foregroundColor: block.isBlockQuote ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        if inline.contains(.strikethrough) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }

        let substring = String(parsed[run.range].characters)
        let piece = inline.contains(.lineBreak) ? "\n" : substring
        return NSAttributedString(string: piece, attributes: attributes)
    }

    private static var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font(size: baseSize, bold: false, italic: false),
            .foregroundColor: NSColor.labelColor
        ]
    }

    private static func headerSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 22
        case 2: return 19
        case 3: return 17
        case 4: return 15
        default: return 14
        }
    }

    private static func font(size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        let base = NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
        guard italic else { return base }
        return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
    }

    private struct Block {
        var headerLevel: Int?
        var isListItem = false
        var listItemID: Int?
        var orderedList = false
        var ordinal = 0
        var isBlockQuote = false
        var isThematicBreak = false
        var indentationLevel = 0

        init(_ intent: PresentationIntent?) {
            guard let intent else { return }
            indentationLevel = intent.indentationLevel
            var listResolved = false
            for component in intent.components {
                switch component.kind {
                case .header(let level):
                    if headerLevel == nil { headerLevel = level }
                case .listItem(let ordinal):
                    if !isListItem {
                        isListItem = true
                        listItemID = component.identity
                        self.ordinal = ordinal
                    }
                case .orderedList:
                    if !listResolved { orderedList = true; listResolved = true }
                case .unorderedList:
                    if !listResolved { orderedList = false; listResolved = true }
                case .blockQuote:
                    isBlockQuote = true
                case .thematicBreak:
                    isThematicBreak = true
                default:
                    break
                }
            }
        }
    }
}
