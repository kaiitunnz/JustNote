import AppKit
import SwiftUI

struct NoteFindOverlay: ViewModifier {
    @ObservedObject var find: NoteFindController

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            NoteFindBar(find: find)
                .frame(maxWidth: 420)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { find.overlaySize = $0 }
                .padding(8)
                .opacity(find.isVisible ? 1 : 0)
                .allowsHitTesting(find.isVisible)
                .accessibilityHidden(!find.isVisible)
        }
    }
}

struct NoteFindBar: View {
    @ObservedObject var find: NoteFindController

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            NoteFindField(find: find)
                .frame(minWidth: 30)
                .pointerStyle(.horizontalText)
            Text(find.status)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityLabel(find.status)
            Button { find.move(backward: true) } label: { Image(systemName: "chevron.up") }
                .pointerStyle(.default)
                .disabled(find.matches.isEmpty)
                .help("Previous match (⇧⌘G)")
                .accessibilityLabel("Previous match")
            Button { find.move() } label: { Image(systemName: "chevron.down") }
                .pointerStyle(.default)
                .disabled(find.matches.isEmpty)
                .help("Next match (⌘G)")
                .accessibilityLabel("Next match")
            Button { find.close() } label: { Image(systemName: "xmark") }
                .pointerStyle(.default)
                .help("Close Find (Esc)")
                .accessibilityLabel("Close Find")
        }
        .buttonStyle(.borderless)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .background(NoteFindRegion(find: find))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(.separator.opacity(0.6)) }
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }
}

private struct NoteFindRegion: NSViewRepresentable {
    let find: NoteFindController

    func makeNSView(context: Context) -> NoteFindRegionView {
        let view = NoteFindRegionView()
        find.registerOverlay(view)
        return view
    }

    func updateNSView(_ view: NoteFindRegionView, context: Context) { find.registerOverlay(view) }
}

final class NoteFindRegionView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct NoteFindField: NSViewRepresentable {
    @ObservedObject var find: NoteFindController

    func makeCoordinator() -> Coordinator { Coordinator(find: find) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NoteFindTextField()
        field.placeholderString = "Find in note"
        field.setAccessibilityLabel("Find in note")
        field.focusRingType = .none
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 13)
        field.delegate = context.coordinator
        find.registerSearchField(field)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        find.registerSearchField(field)
        if (field.currentEditor() as? NSTextView)?.hasMarkedText() != true,
           field.stringValue != find.query { field.stringValue = find.query }
        guard context.coordinator.focusRequest != find.focusRequest else { return }
        context.coordinator.focusRequest = find.focusRequest
        DispatchQueue.main.async { [weak field, weak find] in
            guard let field, let find, find.isVisible, let window = field.window else { return }
            window.makeFirstResponder(field)
            field.selectText(nil)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let find: NoteFindController
        var focusRequest = -1

        init(find: NoteFindController) { self.find = find }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            // The input method owns the query until it commits its marked text.
            guard (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
            find.setQuery(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            if selector == #selector(NSResponder.insertNewline(_:))
                || selector == #selector(NSResponder.insertLineBreak(_:))
                || selector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                find.move(backward: NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
                return true
            }
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                find.close()
                return true
            }
            return false
        }
    }
}

final class NoteFindTextField: NSTextField {
    private var cursorTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let cursorTrackingArea { removeTrackingArea(cursorTrackingArea) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        cursorTrackingArea = area
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .iBeam)
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.iBeam.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.iBeam.set() }
}
