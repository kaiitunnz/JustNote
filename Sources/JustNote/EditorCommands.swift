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
}

enum EditorFontAction: String, CaseIterable {
    case increase
    case decrease
    case reset

    var title: String {
        switch self {
        case .increase: "Increase Font Size"
        case .decrease: "Decrease Font Size"
        case .reset: "Reset Font Size"
        }
    }

    var imageName: String {
        switch self {
        case .increase: "textformat.size.larger"
        case .decrease: "textformat.size.smaller"
        case .reset: "textformat.size"
        }
    }

    var keyEquivalent: (String, EventModifiers) {
        switch self {
        case .increase: ("+", .command)
        case .decrease: ("-", .command)
        case .reset: ("0", .command)
        }
    }
}

/// Editor font size, persisted under `key` and observed by `MenuView`'s `@AppStorage`.
/// The stepping/clamping logic is pure so it can be unit-tested without a running app.
enum EditorFontSize {
    static let key = "editorFontSize"
    static let defaultSize: CGFloat = 13
    static let minSize: CGFloat = 9
    static let maxSize: CGFloat = 32
    static let step: CGFloat = 1

    static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, minSize), maxSize)
    }

    static func increased(from value: CGFloat) -> CGFloat {
        clamp(value + step)
    }

    static func decreased(from value: CGFloat) -> CGFloat {
        clamp(value - step)
    }

    static func current(defaults: UserDefaults) -> CGFloat {
        clamp((defaults.object(forKey: key) as? Double).map { CGFloat($0) } ?? defaultSize)
    }
}

/// Single funnel for the menu bar, context menu, and keyboard shortcuts to mutate the font size.
/// Writes the persisted value directly; `MenuView`'s `@AppStorage` picks the change up and reflows
/// both editors.
@MainActor
final class EditorFontController {
    static let shared = EditorFontController()

    private let defaults = UserDefaults.standard

    func perform(_ action: EditorFontAction) {
        let current = EditorFontSize.current(defaults: defaults)
        let next: CGFloat
        switch action {
        case .increase: next = EditorFontSize.increased(from: current)
        case .decrease: next = EditorFontSize.decreased(from: current)
        case .reset: next = EditorFontSize.defaultSize
        }
        defaults.set(Double(next), forKey: EditorFontSize.key)
    }
}

extension EventModifiers {
    var appKitFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.option) { flags.insert(.option) }
        if contains(.control) { flags.insert(.control) }
        return flags
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
                if let textView = rootView.textViews.first(where: { Self.normalized($0.string) == normalizedText }) {
                    EditorCommandRouter.shared.register(textView)
                }
            }
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
            if let (_, modifiers) = action.keyEquivalent {
                item.keyEquivalentModifierMask = modifiers.appKitFlags
            }
            menu.addItem(item)
        }
    }

    private static func removeFormattingItems(from menu: NSMenu) {
        menu.items
            .filter { $0.identifier?.rawValue == "JustNote.editor-formatting" }
            .forEach(menu.removeItem)
    }

    static func addFontItems(to menu: NSMenu) {
        removeFontItems(from: menu)
        menu.addItem(fontSeparator())
        for action in EditorFontAction.allCases {
            let (key, modifiers) = action.keyEquivalent
            let item = NSMenuItem(
                title: action.title,
                action: #selector(EditorFontMenuActionTarget.performFontAction(_:)),
                keyEquivalent: key
            )
            item.identifier = fontItemIdentifier
            item.target = fontTarget
            item.representedObject = action.rawValue
            item.keyEquivalentModifierMask = modifiers.appKitFlags
            menu.addItem(item)
        }
    }

    private static func removeFontItems(from menu: NSMenu) {
        menu.items
            .filter { $0.identifier == fontItemIdentifier || $0.identifier == fontSeparatorIdentifier }
            .forEach(menu.removeItem)
    }

    private static func fontSeparator() -> NSMenuItem {
        let separator = NSMenuItem.separator()
        separator.identifier = fontSeparatorIdentifier
        return separator
    }

    private static let fontTarget = EditorFontMenuActionTarget()
    private static let fontItemIdentifier = NSUserInterfaceItemIdentifier("JustNote.editor-font")
    private static let fontSeparatorIdentifier = NSUserInterfaceItemIdentifier("JustNote.editor-font-separator")
}

@MainActor
final class EditorFontMenuActionTarget: NSObject {
    @objc func performFontAction(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let action = EditorFontAction(rawValue: rawValue)
        else { return }
        EditorFontController.shared.perform(action)
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
        // Caret lands between the parentheses: "[" + selected + "]" + "(" = range.length + 3.
        let urlLocation = range.location + range.length + 3
        replace(textView, range: range, value: value, selection: NSRange(location: urlLocation, length: 0))
    }

    private static func prefixLine(_ textView: NSTextView, prefix: String) {
        let range = (textView.string as NSString).lineRange(for: textView.selectedRange())
        let line = (textView.string as NSString).substring(with: range)
        let content = line.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
        let contentLength = (content as NSString).length - (content.hasSuffix("\n") ? 1 : 0)
        let selection = NSRange(location: range.location + (prefix as NSString).length, length: max(contentLength, 0))
        replace(textView, range: range, value: prefix + content, selection: selection)
    }

    private static func toggleLinePrefix(_ textView: NSTextView, prefix: String) {
        let range = (textView.string as NSString).lineRange(for: textView.selectedRange())
        let line = (textView.string as NSString).substring(with: range)
        let hasPrefix = line.hasPrefix(prefix)
        let value = hasPrefix ? String(line.dropFirst(prefix.count)) : prefix + line
        let offset = hasPrefix ? 0 : (prefix as NSString).length
        let contentLength = (value as NSString).length - offset - (value.hasSuffix("\n") ? 1 : 0)
        let selection = NSRange(location: range.location + offset, length: max(contentLength, 0))
        replace(textView, range: range, value: value, selection: selection)
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
