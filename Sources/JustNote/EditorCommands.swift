import AppKit
import SwiftUI

enum EditorMode: String {
    case plainText
    case markdown
}

enum EditorModePreference {
    static let key = "editorMode"
    static let legacyPreviewKey = "previewMode"

    static func initialValue(defaults: UserDefaults) -> String {
        if let stored = defaults.string(forKey: key), EditorMode(rawValue: stored) != nil {
            defaults.removeObject(forKey: legacyPreviewKey)
            return stored
        }

        let mode: EditorMode
        if let legacyPreview = defaults.object(forKey: legacyPreviewKey) as? Bool {
            mode = legacyPreview ? .markdown : .plainText
        } else {
            mode = .markdown
        }
        defaults.set(mode.rawValue, forKey: key)
        defaults.removeObject(forKey: legacyPreviewKey)
        return mode.rawValue
    }
}

enum EditorFormattingAction: String, CaseIterable {
    case heading
    case unorderedList
    case orderedList
    case bold
    case italic
    case strikethrough
    case inlineCode
    case blockquote
    case link
    case codeBlock
    case horizontalRule

    var title: String {
        switch self {
        case .heading: "Heading"
        case .unorderedList: "Bulleted List"
        case .orderedList: "Numbered List"
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .inlineCode: "Inline Code"
        case .blockquote: "Block Quote"
        case .link: "Link"
        case .codeBlock: "Code Block"
        case .horizontalRule: "Horizontal Rule"
        }
    }

    var imageName: String {
        switch self {
        case .heading: "textformat.size"
        case .unorderedList: "list.bullet"
        case .orderedList: "list.number"
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .inlineCode: "chevron.left.forwardslash.chevron.right"
        case .blockquote: "text.quote"
        case .link: "link"
        case .codeBlock: "curlybraces.square"
        case .horizontalRule: "minus"
        }
    }

    var keyEquivalent: (String, EventModifiers)? {
        switch self {
        case .bold: ("b", .command)
        case .italic: ("i", .command)
        case .strikethrough: ("x", [.command, .shift])
        case .unorderedList: ("8", [.command, .shift])
        case .orderedList: ("7", [.command, .shift])
        default: nil
        }
    }

    var appKitModifierFlags: NSEvent.ModifierFlags {
        switch self {
        case .bold, .italic: .command
        case .strikethrough, .unorderedList, .orderedList: [.command, .shift]
        default: []
        }
    }
}

@MainActor
final class EditorCommandRouter {
    static let shared = EditorCommandRouter()

    private weak var lastEditor: NSTextView?
    private(set) var mode: EditorMode = .markdown

    func setMode(_ mode: EditorMode) {
        self.mode = mode
    }

    func register(_ textView: NSTextView) {
        lastEditor = textView
    }

    func editor(requiresFocus: Bool = false) -> NSTextView? {
        if let firstResponder = NSApp.keyWindow?.firstResponder as? NSTextView, firstResponder.isEditable {
            lastEditor = firstResponder
            return firstResponder
        }
        guard !requiresFocus,
              let keyWindow = NSApp.keyWindow,
              let lastEditor,
              lastEditor.window === keyWindow,
              lastEditor.isEditable
        else { return nil }
        return lastEditor
    }

    func perform(_ action: EditorFormattingAction, mode: EditorMode, requiresEditorFocus: Bool = false) {
        guard let textView = editor(requiresFocus: requiresEditorFocus) else { return }
        textView.window?.makeFirstResponder(textView)
        if mode == .markdown {
            let userInfo: [AnyHashable: Any]? = action == .heading ? ["level": 1] : nil
            NotificationCenter.default.post(name: action.notificationName, object: nil, userInfo: userInfo)
        } else {
            PlainTextFormatting.apply(action, to: textView)
        }
    }

}

struct EditorTextViewRegistration: NSViewRepresentable {
    let documentText: String

    func makeNSView(context: Context) -> RegistrationView {
        RegistrationView(documentText: documentText)
    }

    func updateNSView(_ view: RegistrationView, context: Context) {
        view.documentText = documentText
        view.registerEditor()
    }

    final class RegistrationView: NSView {
        var documentText: String

        init(documentText: String) {
            self.documentText = documentText
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            registerEditor()
        }

        func registerEditor() {
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let rootView = self.window?.contentView else { return }
                let normalizedText = Self.normalized(self.documentText)
                if let textView = Self.textViews(in: rootView).first(where: { Self.normalized($0.string) == normalizedText }) {
                    EditorCommandRouter.shared.register(textView)
                }
            }
        }

        private static func textViews(in view: NSView) -> [NSTextView] {
            let own = (view as? NSTextView).map { [$0] } ?? []
            return own + view.subviews.flatMap(textViews(in:))
        }

        private static func normalized(_ text: String) -> String {
            text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        }
    }
}

extension EditorFormattingAction {
    var notificationName: Notification.Name {
        Notification.Name("JustNote.editor.\(rawValue)")
    }
}

@MainActor
enum EditorContextMenuBuilder {
    private static let markdownTarget = EditorMenuActionTarget(mode: .markdown)
    private static let plainTextTarget = EditorMenuActionTarget(mode: .plainText)

    static func addFormattingItems(to menu: NSMenu, mode: EditorMode) {
        removeFormattingItems(from: menu)
        menu.addItem(.separator())
        for action in EditorFormattingAction.allCases {
            let item = NSMenuItem(
                title: action.title,
                action: #selector(EditorMenuActionTarget.performFormatting(_:)),
                keyEquivalent: action.keyEquivalent?.0 ?? ""
            )
            item.identifier = NSUserInterfaceItemIdentifier("JustNote.editor-formatting")
            item.target = mode == .markdown ? markdownTarget : plainTextTarget
            item.representedObject = action.rawValue
            if action.keyEquivalent != nil {
                item.keyEquivalentModifierMask = action.appKitModifierFlags
            }
            menu.addItem(item)
        }
    }

    private static func removeFormattingItems(from menu: NSMenu) {
        menu.items
            .filter { $0.identifier?.rawValue == "JustNote.editor-formatting" }
            .forEach(menu.removeItem)
    }
}

@MainActor
final class EditorMenuActionTarget: NSObject {
    private let mode: EditorMode

    init(mode: EditorMode) {
        self.mode = mode
    }

    @objc func performFormatting(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let action = EditorFormattingAction(rawValue: rawValue)
        else { return }
        EditorCommandRouter.shared.perform(action, mode: mode)
    }
}

private enum PlainTextFormatting {
    static func apply(_ action: EditorFormattingAction, to textView: NSTextView) {
        switch action {
        case .bold: wrap(textView, marker: "**")
        case .italic: wrap(textView, marker: "*")
        case .strikethrough: wrap(textView, marker: "~~")
        case .inlineCode: wrap(textView, marker: "`")
        case .heading: prefixLine(textView, prefix: "# ")
        case .unorderedList: toggleLinePrefix(textView, prefix: "- ")
        case .orderedList: toggleLinePrefix(textView, prefix: "1. ")
        case .blockquote: toggleLinePrefix(textView, prefix: "> ")
        case .link: wrapLink(textView)
        case .codeBlock: insert(textView, value: "```\n\n```\n", selectionOffset: 4)
        case .horizontalRule: insert(textView, value: "---\n", selectionOffset: 4)
        }
    }

    private static func wrap(_ textView: NSTextView, marker: String) {
        let range = textView.selectedRange()
        let nsText = textView.string as NSString
        if range.length > 0 {
            let selected = nsText.substring(with: range)
            let opening = range.location >= marker.count && nsText.substring(with: NSRange(location: range.location - marker.count, length: marker.count)) == marker
            let closingLocation = NSMaxRange(range)
            let closing = NSMaxRange(range) + marker.count <= nsText.length && nsText.substring(with: NSRange(location: closingLocation, length: marker.count)) == marker
            if opening && closing {
                replace(textView, range: NSRange(location: range.location - marker.count, length: range.length + marker.count * 2), value: selected, selection: NSRange(location: range.location - marker.count, length: range.length))
            } else {
                replace(textView, range: range, value: marker + selected + marker, selection: NSRange(location: range.location + marker.count, length: range.length))
            }
            return
        }

        if let word = wordRange(at: range.location, in: nsText) {
            let wordText = nsText.substring(with: word)
            replace(textView, range: word, value: marker + wordText + marker, selection: NSRange(location: range.location + marker.count, length: 0))
        } else {
            insert(textView, value: marker + marker, selectionOffset: marker.count)
        }
    }

    private static func wrapLink(_ textView: NSTextView) {
        let range = textView.selectedRange()
        let nsText = textView.string as NSString
        let selected = range.length > 0 ? nsText.substring(with: range) : ""
        let value = "[\(selected)]()"
        let urlLocation = range.location + selected.count + 2
        replace(textView, range: range, value: value, selection: NSRange(location: urlLocation, length: 0))
    }

    private static func prefixLine(_ textView: NSTextView, prefix: String) {
        let range = (textView.string as NSString).lineRange(for: textView.selectedRange())
        let line = (textView.string as NSString).substring(with: range)
        let content = line.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
        replace(textView, range: range, value: prefix + content, selection: NSRange(location: range.location + prefix.count, length: max(content.count - (content.hasSuffix("\n") ? 1 : 0), 0)))
    }

    private static func toggleLinePrefix(_ textView: NSTextView, prefix: String) {
        let range = (textView.string as NSString).lineRange(for: textView.selectedRange())
        let line = (textView.string as NSString).substring(with: range)
        let value = line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : prefix + line
        let offset = line.hasPrefix(prefix) ? 0 : prefix.count
        replace(textView, range: range, value: value, selection: NSRange(location: range.location + offset, length: max(value.count - offset - (value.hasSuffix("\n") ? 1 : 0), 0)))
    }

    private static func wordRange(at location: Int, in text: NSString) -> NSRange? {
        guard location >= 0, location <= text.length else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        var start = location
        while start > 0, let scalar = Unicode.Scalar(text.character(at: start - 1)), allowed.contains(scalar) { start -= 1 }
        var end = location
        while end < text.length, let scalar = Unicode.Scalar(text.character(at: end)), allowed.contains(scalar) { end += 1 }
        return end > start ? NSRange(location: start, length: end - start) : nil
    }

    private static func insert(_ textView: NSTextView, value: String, selectionOffset: Int) {
        let range = textView.selectedRange()
        replace(textView, range: range, value: value, selection: NSRange(location: range.location + selectionOffset, length: 0))
    }

    private static func replace(_ textView: NSTextView, range: NSRange, value: String, selection: NSRange) {
        guard textView.shouldChangeText(in: range, replacementString: value) else { return }
        textView.replaceCharacters(in: range, with: value)
        textView.didChangeText()
        textView.setSelectedRange(selection)
    }
}
