import AppKit
import MarkdownEngine

enum EditorBottomSpace {
    static let policy = OverscrollPolicy(percent: 0.5, maxPoints: .greatestFiniteMagnitude, minPoints: 0)

    static func documentHeight(contentHeight: CGFloat, viewportHeight: CGFloat, lineHeight: CGFloat) -> CGFloat {
        let start = viewportHeight * policy.activationStartFraction
        let range = max(viewportHeight * policy.activationRangeFraction, 1)
        let progress = min(max((contentHeight - start) / range, 0), 1)
        let slack = max(0, floor(viewportHeight * policy.percent - lineHeight))
        // Match the engine's gradual activation for notes shorter than the viewport.
        let unlock = max(viewportHeight - contentHeight, 0)
        let bottomSpace = floor((unlock + slack) * progress)
        return max(viewportHeight, ceil(contentHeight + bottomSpace))
    }
}
