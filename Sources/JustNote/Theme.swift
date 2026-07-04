import SwiftUI

enum Theme {
    static let accent = Color(red: 0.52, green: 0.68, blue: 0.94)
    static let ink = Color(red: 0.88, green: 0.92, blue: 0.96)
    static let pinned = Color(red: 0.95, green: 0.72, blue: 0.35)
    static let error = Color.red

    static let panelWidth: CGFloat = 660
    static let panelHeight: CGFloat = 480
    static let sidebarWidth: CGFloat = 218
    static let minSidebarWidth: CGFloat = 170
    static let maxSidebarWidth: CGFloat = 340
    static let corner: CGFloat = 14
    static let innerCorner: CGFloat = 10

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
