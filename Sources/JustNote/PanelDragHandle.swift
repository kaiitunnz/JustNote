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
    private var activeHeight: CGFloat = 0

    private let accessibilityInteractiveRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXComboBox", "AXLink", "AXPopUpButton", "AXRadioButton",
        "AXSearchField", "AXSlider", "AXTextArea", "AXTextField",
    ]

    func passThroughEvents(to view: NSView) {
        underlyingView = view
    }

    func setActiveHeight(_ height: CGFloat) {
        activeHeight = max(0, height)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard point.y >= frame.maxY - activeHeight, point.y <= frame.maxY else { return nil }
        guard let underlyingView else { return self }

        // AppKit supplies this hit-test point in the handle's superview coordinate space. Convert
        // through the handle's local space before asking the sibling hosting view for its target.
        let localPoint = superview.map { convert(point, from: $0) } ?? point
        let underlyingPoint = underlyingView.convert(localPoint, from: self)
        guard let target = underlyingView.hitTest(underlyingPoint) else { return self }

        // SwiftUI controls hosted by NSHostingView may not appear in the AppKit hit-test view
        // hierarchy. Ask the accessibility tree as well, since it still identifies the control at
        // the pointer location even when the AppKit target is only the hosting view itself.
        let accessibilityPoint = underlyingView.window?.convertPoint(toScreen: underlyingPoint) ?? underlyingPoint
        if let element = underlyingView.accessibilityHitTest(accessibilityPoint) as? NSAccessibilityElement,
           isInteractiveAccessibilityElement(element) {
            return nil
        }

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

    private func isInteractiveAccessibilityElement(_ element: NSAccessibilityElement) -> Bool {
        guard let role = element.accessibilityRole()?.rawValue else { return false }
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
