import SwiftUI
import AppKit

final class OnboardingWindow {
    static let shared = OnboardingWindow()
    private var window: NSWindow?

    func show() {
        window?.close()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 680),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.contentView = NSHostingView(rootView: OnboardingView { [weak w] in
            Settings.shared.v.onboarded = true
            w?.close()
        })
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

struct OnboardingView: View {
    let finish: () -> Void
    @StateObject private var step = Box(Int(ProcessInfo.processInfo.environment["DRAWER_STEP"] ?? "") ?? 0)
    @ObservedObject var settings = Settings.shared

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Group {
                    switch step.value {
                    case 0: welcome
                    case 1: quickStart
                    default: accessibility
                    }
                }
                .id(step.value)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity))
                Spacer(minLength: 0)
                HStack(spacing: 7) {
                    ForEach(0..<3) { i in
                        Capsule().fill(Color.white.opacity(i == step.value ? 0.9 : 0.22))
                            .frame(width: i == step.value ? 20 : 6, height: 6)
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .frame(width: 560, height: 680)
        .animation(.easeInOut(duration: 0.28), value: step.value)
    }

    /// Deep slate with a soft accent glow behind the icon.
    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.13, green: 0.14, blue: 0.19), Color(red: 0.07, green: 0.07, blue: 0.10)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.accentColor.opacity(0.34), Color.accentColor.opacity(0)],
                           center: .center, startRadius: 0, endRadius: 260)
                .frame(width: 520, height: 520)
                .offset(y: step.value == 0 ? -110 : -230)
        }
        .ignoresSafeArea()
    }

    private var icon: some View {
        let size: CGFloat = step.value == 0 ? 112 : 76
        return Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: size, height: size)
            .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 30, weight: .bold)).multilineTextAlignment(.center)
            Text(subtitle).font(.system(size: 14.5)).foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center).lineSpacing(3)
        }
        .padding(.horizontal, 52)
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Text(title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 30).padding(.vertical, 12)
            .glassSurface(Capsule(), tint: Color.accentColor.opacity(0.85), interactive: true)
            .background(Color.accentColor.opacity(0.0001), in: Capsule())
            .contentShape(Capsule()).onTapGesture(perform: action)
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Text(title).font(.system(size: 14.5, weight: .medium)).foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 26).padding(.vertical, 12)
            .glassSurface(Capsule(), interactive: true)
            .contentShape(Capsule()).onTapGesture(perform: action)
    }

    private var welcome: some View {
        VStack(spacing: 30) {
            icon
            heading("Your clipboard,\nalways within reach",
                    "Drawer remembers what you copy and keeps notes and files tucked at the top of your screen. Scroll there to open it.")
            primary("Get Started") { step.value = 1 }
        }
    }

    private var quickStart: some View {
        VStack(spacing: 26) {
            icon
            heading("Quick Start", "A few choices to get going. You can change all of them later.")
            VStack(spacing: 0) {
                row("Run in background", "Open at login and keep running") {
                    Toggle("", isOn: SettingsActions.launchAtLogin).toggleStyle(.switch).labelsHidden()
                }
                RowDivider()
                row("iCloud Drive", Settings.iCloudDrive == nil ? "Not available on this Mac" : "Keep notes and files in sync") {
                    ICloudToggle()
                }
                RowDivider()
                row("Activation shortcut", "Open Drawer from any app") { HotKeyField() }
                RowDivider()
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Clipboard history").font(.system(size: 13.5))
                        Text("How long to keep what you copy").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                    }
                    RetentionSlider()
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
            }
            .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 44)
            primary("Continue") { step.value = 2 }
        }
    }

    private func row<C: View>(_ title: String, _ subtitle: String, @ViewBuilder control: () -> C) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13.5))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 12)
            control().buttonStyle(PillButtonStyle())
        }
        .padding(.horizontal, 18).padding(.vertical, 13)
    }

    private var accessibility: some View {
        VStack(spacing: 28) {
            icon
            heading("Paste to any app",
                    "To paste straight into the app you're using, allow Drawer in Privacy & Security › Accessibility. Without it, items are copied and you paste them yourself.")
            HStack(spacing: 12) {
                secondary("Not Now", action: finish)
                primary("Open System Settings") {
                    Paster.requestTrust()
                    Paster.openAccessibilitySettings()
                    finish()
                }
            }
        }
    }
}
