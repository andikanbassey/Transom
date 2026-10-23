import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

// Layout pieces for the settings panes: sections, rows, the app lists, panel sizes and the licence sheet.

struct Section<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(Look.overline).tracking(0.6).foregroundStyle(.secondary).padding(.leading, 6)
            VStack(spacing: 0) { content() }
                .lookCard()
        }
    }
}

/// Hairline between rows, inset like system lists.
struct RowDivider: View {
    var body: some View { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1).padding(.leading, 16) }
}

struct Row<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: () -> Control
    init(_ title: String, subtitle: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title; self.subtitle = subtitle; self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Look.body)
                if let subtitle {
                    Text(subtitle).font(Look.meta).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control().buttonStyle(PillButtonStyle())
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .frame(minHeight: 50)
    }
}

struct AppList: View {
    let title: String
    let note: String
    let apps: Binding<[AppRef]>
    let active: Bool

    var body: some View {
        Section(title) {
            Row(active ? "In use" : "Not in use", subtitle: note) {
                Button("Add App…", action: add)
            }
            ForEach(apps.wrappedValue) { app in
                RowDivider()
                HStack(spacing: 10) {
                    if let icon = AppIcons.icon(app.bundleID) { Image(nsImage: icon).resizable().frame(width: 22, height: 22) }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(app.name).font(.system(size: 13))
                        Text(app.bundleID).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { apps.wrappedValue.removeAll { $0 == app } } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
            }
        }
        .opacity(active ? 1 : 0.6)
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let ref = AppRef(appURL: url), !apps.wrappedValue.contains(ref) { apps.wrappedValue.append(ref) }
        }
    }
}

/// A pad with one slot per panel. Pick a panel up, slide it over another slot and the others make way, with a tick
/// on a trackpad for each slot you cross and a thud when you put it down.
struct PanelPad: View {
    @ObservedObject var settings = Settings.shared
    @StateObject private var dragging = Box<Panel?>(nil)
    @StateObject private var dragX = Box<CGFloat>(0)
    @StateObject private var startX = Box<CGFloat>(0)
    private let pad: CGFloat = 16, gap: CGFloat = 10, tileHeight: CGFloat = 88

    var body: some View {
        GeometryReader { geo in
            let order = settings.v.orderedPanels
            let count = CGFloat(order.count)
            let slotW = (geo.size.width - pad * 2 - gap * (count - 1)) / count
            let step = slotW + gap
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    var y: CGFloat = 8
                    while y < size.height {
                        var x: CGFloat = 8
                        while x < size.width {
                            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(.primary.opacity(0.09)))
                            x += 14
                        }
                        y += 14
                    }
                }
                ForEach(0..<order.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .frame(width: slotW, height: tileHeight)
                        .offset(x: pad + CGFloat(i) * step, y: pad)
                }
                ForEach(order, id: \.self) { p in
                    let index = order.firstIndex(of: p) ?? 0
                    let held = dragging.value == p
                    tile(p, held: held)
                        .frame(width: slotW, height: tileHeight)
                        .scaleEffect(held ? 1.07 : 1)
                        .shadow(color: .black.opacity(held ? 0.4 : 0), radius: held ? 16 : 0, y: held ? 9 : 0)
                        .offset(x: held ? dragX.value : pad + CGFloat(index) * step, y: pad)
                        .zIndex(held ? 1 : 0)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                .onChanged { g in
                                    if dragging.value == nil {
                                        startX.value = pad + CGFloat(index) * step
                                        Haptics.pickup()
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { dragging.value = p }
                                    }
                                    let x = min(max(startX.value + g.translation.width, pad), pad + (count - 1) * step)
                                    dragX.value = x
                                    let target = min(max(Int(((x - pad) / step).rounded()), 0), order.count - 1)
                                    var current = settings.v.orderedPanels
                                    if let from = current.firstIndex(of: p), from != target {
                                        current.remove(at: from)
                                        current.insert(p, at: target)
                                        Haptics.tick()
                                        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { settings.v.panelOrder = current }
                                    }
                                }
                                .onEnded { _ in
                                    Haptics.drop()
                                    withAnimation(.spring(response: 0.36, dampingFraction: 0.62)) { dragging.value = nil }
                                }
                        )
                }
            }
        }
        .frame(height: tileHeight + pad * 2)
    }

    private func tile(_ p: Panel, held: Bool) -> some View {
        let shown = settings.v.isShown(p)
        return VStack(spacing: 6) {
            Image(systemName: p.symbol).font(.system(size: 22, weight: .medium)).frame(height: 28)
            Text(p.title).font(.system(size: 13, weight: .semibold))
            Text(shown ? " " : "Hidden").font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .foregroundStyle(shown ? Color.accentColor : Color.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(shown ? Color.accentColor.opacity(held ? 0.28 : 0.16) : Color.primary.opacity(0.07))
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(shown ? Color.accentColor.opacity(held ? 0.7 : 0.35) : Color.primary.opacity(0.12), lineWidth: 1))
        .opacity(shown ? 1 : 0.7)
    }
}

/// The licence text shown from Settings › General › About. It reads the LICENSE file copied into the app.
struct LicenseSheet: View {
    let close: () -> Void
    private var text: String {
        if let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil), let t = try? String(contentsOf: url, encoding: .utf8) { return t }
        return "MIT License. The full text is at \(Brand.repoURL.appendingPathComponent("blob/main/LICENSE").absoluteString)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("License").font(Look.sectionTitle)
                Spacer()
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
            ScrollView {
                Text(text).font(.system(size: 12.5, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }
            .background(Look.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Look.hairline, lineWidth: 1))
        }
        .padding(22).frame(width: 560, height: 420).background(Look.page)
    }
}
