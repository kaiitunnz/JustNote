import AppKit
import SwiftUI

extension View {
    @ViewBuilder
    func actionButtonStyle(primary: Bool) -> some View {
        if primary {
            buttonStyle(.glassProminent).tint(Theme.accent)
        } else {
            buttonStyle(.glass).tint(.clear)
        }
    }

    func contentSurface(cornerRadius: CGFloat = Theme.corner) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

struct HeaderIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Chip(configuration: configuration)
    }

    private struct Chip: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(fill)))
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }

        private var fill: Double {
            if configuration.isPressed { return 0.22 }
            return hovering ? 0.16 : 0.10
        }
    }
}

struct JustNoteMark: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        var path = Path()
        path.addRoundedRect(in: CGRect(x: rect.minX + 0.20 * rect.width, y: rect.minY + 0.12 * rect.height, width: 0.60 * rect.width, height: 0.76 * rect.height), cornerSize: CGSize(width: 0.10 * rect.width, height: 0.10 * rect.height))
        path.move(to: p(0.34, 0.31))
        path.addLine(to: p(0.66, 0.31))
        path.move(to: p(0.34, 0.46))
        path.addLine(to: p(0.66, 0.46))
        path.move(to: p(0.34, 0.61))
        path.addLine(to: p(0.57, 0.61))
        return path
    }
}

enum MenuBarIcon {
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let path = JustNoteMark().path(in: rect).cgPath
            context.addPath(path)
            context.setStrokeColor(NSColor.labelColor.cgColor)
            context.setLineWidth(1.7)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }
}

func resignTextFocus() {
    NSApp.keyWindow?.makeFirstResponder(nil)
}

/// Switch to a regular (Dock-visible) app before showing a real window. Paired with the
/// AppDelegate lifecycle, which returns to `.accessory` once the last titled window closes.
func prepareToShowWindow() {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
}
