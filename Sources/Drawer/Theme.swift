import SwiftUI
import AppKit

// MARK: - Liquid Glass

extension View {
    /// Liquid Glass on macOS 26 and later (when enabled), a blurred material elsewhere.
    @ViewBuilder func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false, enabled: Bool = true) -> some View {
        if enabled, ProcessInfo.processInfo.environment["DRAWER_NOGLASS"] == nil, #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .background(tint ?? .clear, in: shape)
        }
    }
}

// MARK: - Controls

/// Secondary button used inside settings rows.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View { PillBody(configuration: configuration, prominent: prominent) }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @StateObject private var hovering = Box(false)
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .padding(.horizontal, 13).padding(.vertical, 6)
                .background(
                    Capsule().fill(prominent ? Color.accentColor : Color.primary.opacity(hovering.value ? 0.14 : 0.09))
                )
                .overlay(Capsule().strokeBorder(Color.primary.opacity(prominent ? 0 : 0.06), lineWidth: 1))
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
                .onHover { hovering.value = $0 }
        }
    }
}

// MARK: - Menu bar icon

enum MenuBarIcon {
    /// A screen edge with a drawer pulled down from it. Drawn as a template so macOS tints it for light and dark bars.
    static func image() -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let frame = NSBezierPath(roundedRect: NSRect(x: 2, y: 1.5, width: 16, height: 13), xRadius: 3.6, yRadius: 3.6)
            frame.lineWidth = 1.4
            frame.stroke()
            let drawer = NSBezierPath(roundedRect: NSRect(x: 4.6, y: 6.2, width: 10.8, height: 5.6), xRadius: 1.8, yRadius: 1.8)
            drawer.fill()
            let handle = NSBezierPath(roundedRect: NSRect(x: 8, y: 4.1, width: 4, height: 1.3), xRadius: 0.65, yRadius: 0.65)
            handle.fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}
