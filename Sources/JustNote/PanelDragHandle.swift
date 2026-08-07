import AppKit

/// A transparent title strip that owns panel movement instead of delegating the drag to the
/// WindowServer. Native titled-window drags bypass frame setters, which makes live magnetic snapping
/// fight the server. Keeping the gesture in an ordinary view lets PanelController move the panel
/// synchronously and apply hysteretic snapping without flicker.
@MainActor
final class PanelDragHandle: NSView {
    var onDragBegan: (() -> Void)?
    var onDrag: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private weak var underlyingView: NSView?
    private var isDragging = false

    private let accessibilityInteractiveRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXComboBox", "AXLink", "AXPopUpButton", "AXRadioButton",
        "AXSearchField", "AXSlider", "AXTextArea", "AXTextField",
    ]

    func passThroughEvents(to view: NSView) {
        underlyingView = view
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let underlyingView else { return self }

        let underlyingPoint = underlyingView.convert(point, from: self)
        guard let target = underlyingView.hitTest(underlyingPoint) else { return self }

        // The handle is layered above SwiftUI so it can own blank titlebar pixels. Walk up the
        // underlying hit-test result and yield to controls/text views so header buttons remain
        // clickable even though they sit inside the titlebar-height overlay.
        var view: NSView? = target
        while let candidate = view, candidate !== underlyingView {
            if candidate is NSControl || candidate is NSTextView || isInteractiveAccessibilityElement(candidate) {
                return nil
            }
            view = candidate.superview
        }
        return self
    }

    private func isInteractiveAccessibilityElement(_ view: NSView) -> Bool {
        guard let role = view.accessibilityRole()?.rawValue else { return false }
        return accessibilityInteractiveRoles.contains(role)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        onDragBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        onDrag?()
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        onDragEnded?()
    }

}
