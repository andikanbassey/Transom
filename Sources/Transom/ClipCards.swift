import SwiftUI
import AppKit
// How a clipboard item looks: the row, the card, the preview inside it and the full view of one item.

struct ClipRow: View {
    let clip: Clip
    let store: ClipboardStore
    var quickKey: Int?
    /// In the Library a click copies; in the drawer it pastes into the app underneath.
    var inWindow = false
    @StateObject private var hovering = Box(false)
    private let cover: CGFloat = 54

    var body: some View {
        let cat = clip.category
        HStack(spacing: 10) {
            Image(systemName: clip.pinned ? "star.fill" : "star")
                .font(.system(size: fs(11)))
                .foregroundStyle(clip.pinned ? Color.yellow : Color.secondary.opacity(hovering.value ? 0.8 : 0))
                .frame(width: 14)
                .contentShape(Rectangle())
                .accessibleTap(clip.pinned ? "Unpin" : "Pin", combine: false) { store.togglePin(clip) }
            coverArt(cat)
                .frame(width: cover, height: cover)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
            VStack(alignment: .leading, spacing: 6) {
                Text(clip.title)
                    .font(.system(size: fs(13.5), weight: .medium))
                    .lineLimit(cat == .text ? 2 : 1).truncationMode(.middle)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    Pill(category: cat, sensitive: clip.sensitive)
                    if let expiry = clip.sensitiveExpiry { SensitiveClock(expiry: expiry) }
                }
            }
            Spacer(minLength: 4)
            ZStack {
                if hovering.value {
                    Image(systemName: "xmark").font(.system(size: fs(10), weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                        .accessibleTap("Delete", combine: false) { store.delete(clip) }
                } else {
                    HStack(spacing: 6) {
                        if let icon = AppIcons.icon(clip.sourceBundleID) {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18).opacity(0.85)
                        }
                        if let n = quickKey {
                            Text("\(Settings.shared.v.quickPasteModifier.symbol)\(n)")
                                .font(.system(size: fs(10), weight: .medium, design: .rounded)).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(store.cursor == clip.id ? Color.accentColor.opacity(0.22) : (hovering.value ? Color.primary.opacity(0.08) : .clear),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering.value = $0 }
        .accessibleTap(hint: "Pastes or copies the item") {
            if Settings.shared.v.pasteMode == .expand { store.expanded = clip }
            else if inWindow { store.copy(clip); if Settings.shared.v.sounds { NSSound(named: "Pop")?.play() } }
            else { AppModel.shared.use(clip) }
        }
        .onDrag { dragProvider(clip) }
        .contextMenu { if inWindow { LibraryClipMenu(clip: clip, store: store) } else { ClipMenu(clip: clip, store: store) } }
    }

    /// A square cover that says what the clip is: real artwork for media, a tinted symbol for the rest.
    @ViewBuilder private func coverArt(_ cat: Category) -> some View {
        let size = CGSize(width: cover, height: cover)
        if clip.sensitive {
            SensitiveCover(clip: clip, active: hovering.value)
        } else {
        switch cat {
        case .color:
            (Clip.hexColor((clip.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? .gray)
        case .image, .gif, .video:
            ZStack {
                if let url = clip.previewURL { Thumb(url: url, size: size) }
                if cat == .video {
                    Image(systemName: "play.fill").font(.system(size: fs(10))).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(.black.opacity(0.55), in: Circle())
                }
            }
        case .pdf, .folder, .file:
            ZStack {
                Color.primary.opacity(0.06)
                if let url = clip.previewURL { Thumb(url: url, size: CGSize(width: cover - 8, height: cover - 8), fill: false) }
            }
        case .link where clip.linkImageURL != nil:
            Thumb(url: clip.linkImageURL!, size: size)
        case .text, .link, .audio:
            ZStack {
                Contrast.solidChips ? cat.tint : cat.tint.opacity(0.18)
                Image(systemName: cat == .text ? "text.alignleft" : cat.symbol)
                    .font(.system(size: fs(20), weight: .medium)).foregroundStyle(Contrast.solidChips ? Color.white : cat.tint)
            }
        }
        }
    }
}

/// A single clipboard item shown in full inside the clipboard column.
struct ExpandedClipView: View {
    let clip: Clip
    let store: ClipboardStore
    var inWindow = false

    var body: some View {
        let cat = clip.category
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { store.expanded = nil } label: { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Pill(category: cat, sensitive: clip.sensitive)
                if let expiry = clip.sensitiveExpiry { SensitiveClock(expiry: expiry) }
                Spacer()
                Button("Copy") {
                    store.copy(clip)
                    if Settings.shared.v.sounds { NSSound(named: "Pop")?.play() }
                }
                if !inWindow { Button("Paste") { AppModel.shared.use(clip, paste: true) }.keyboardShortcut(.defaultAction) }
            }
            .padding(.horizontal, 14)
            content(cat)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12).padding(.bottom, 14)
        }
    }

    @ViewBuilder private func content(_ cat: Category) -> some View {
        if clip.sensitive && ![.text, .link, .color].contains(cat) {
            SensitiveCover(clip: clip, active: true)
        } else {
        switch cat {
        case .text, .link, .color:
            ScrollView {
                if clip.sensitive {
                    SensitiveText(length: (clip.text ?? "").count, active: true, size: fs(13), expiry: clip.sensitiveExpiry)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                } else {
                    Text(clip.text ?? clip.title)
                        .font(.system(size: fs(13))).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
            }
        case .image, .gif:
            if let url = clip.imageURL ?? clip.fileURLs.first, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit().padding(8)
            } else {
                Text("Preview unavailable").foregroundStyle(.secondary)
            }
        default:
            GeometryReader { geo in
                VStack(spacing: 8) {
                    if let url = clip.previewURL {
                        Thumb(url: url, size: CGSize(width: geo.size.width - 20, height: max(40, geo.size.height - 70)), fill: false)
                    }
                    Text(clip.fileURLs.map(\.lastPathComponent).joined(separator: ", "))
                        .font(.system(size: fs(12))).foregroundStyle(.secondary).lineLimit(2).padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        }
    }
}

/// The preview area of a card: text excerpt, link cover, colour, picture or file thumbnail.
struct ClipPreview: View {
    let clip: Clip
    @StateObject private var hovering = Box(false)

    var body: some View { preview(clip.category).onHover { hovering.value = $0 } }

    @ViewBuilder private func preview(_ cat: Category) -> some View {
        GeometryReader { geo in
            if clip.sensitive && cat != .text {
                SensitiveCover(clip: clip, active: hovering.value)
            } else {
            switch cat {
            case .color:
                ZStack {
                    (Clip.hexColor((clip.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? .gray)
                    Text(clip.title).font(.system(size: fs(15), weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white).shadow(radius: 2)
                }
            case .image, .gif, .video:
                ZStack {
                    if let url = clip.previewURL { Thumb(url: url, size: geo.size) }
                    if cat == .video {
                        Image(systemName: "play.fill").font(.system(size: 14)).foregroundStyle(.white)
                            .frame(width: 34, height: 34).background(.black.opacity(0.55), in: Circle())
                    }
                }
            case .pdf, .folder, .file, .audio:
                ZStack {
                    Color.primary.opacity(0.04)
                    if let url = clip.previewURL {
                        Thumb(url: url, size: CGSize(width: geo.size.width - 20, height: geo.size.height - 12), fill: false)
                    }
                }
            case .link:
                VStack(alignment: .leading, spacing: 4) {
                    if let img = clip.linkImageURL {
                        Thumb(url: img, size: CGSize(width: geo.size.width, height: max(40, geo.size.height - 50)))
                    } else {
                        ZStack { cat.tint.opacity(0.15); Image(systemName: "link").font(.system(size: 24)).foregroundStyle(cat.tint) }
                            .frame(height: max(40, geo.size.height - 50))
                    }
                    Text(clip.title).font(.system(size: fs(12.5), weight: .semibold)).lineLimit(1).padding(.horizontal, 10)
                    Text(host).font(.system(size: fs(11))).foregroundStyle(.secondary).lineLimit(1).padding(.horizontal, 10)
                }
            case .text:
                Group {
                    if clip.sensitive {
                        SensitiveText(length: (clip.text ?? "").count, active: hovering.value, size: fs(12.5), expiry: clip.sensitiveExpiry)
                    } else {
                        Text(clip.text ?? "").font(.system(size: fs(12.5))).multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
            }
            }
        }
    }

    private var host: String {
        let t = (clip.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: t)?.host?.replacingOccurrences(of: "www.", with: "") ?? t
    }

}

/// A clipboard item as a card: coloured header with type and age, a preview, and a footer with the details.
struct ClipCard: View {
    static let baseWidth: CGFloat = 196
    static let baseHeight: CGFloat = 230
    let clip: Clip
    let store: ClipboardStore
    var quickKey: Int?
    /// In the Library window there is no app to paste into, so a click copies and says so.
    var inWindow = false
    @StateObject private var hovering = Box(false)
    @StateObject private var copied = Box(false)

    var body: some View {
        let cat = clip.category
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Image(systemName: clip.kindSymbol).font(.system(size: fs(11), weight: .semibold))
                        Text(clip.kindLabel).font(.system(size: fs(13), weight: .semibold))
                    }
                    Text(clip.date.formatted(.relative(presentation: .named)))
                        .font(.system(size: fs(10.5))).opacity(0.85)
                }
                .frame(height: fs(38))
                Spacer(minLength: 4)
                // Same height as the title block, so where an item came from reads at a glance.
                if let icon = AppIcons.icon(clip.sourceBundleID) {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).frame(width: fs(38), height: fs(38))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(cat.tint)

            ClipPreview(clip: clip)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            HStack {
                if let expiry = clip.sensitiveExpiry {
                    SensitiveClock(expiry: expiry)
                } else {
                    Text(footer(cat)).font(.system(size: fs(10.5))).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 4)
                if let n = quickKey {
                    Text("\(Settings.shared.v.quickPasteModifier.symbol)\(n)")
                        .font(.system(size: fs(10), weight: .medium, design: .rounded)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .background(Color.primary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(hovering.value ? cat.tint : Color.primary.opacity(0.1), lineWidth: hovering.value ? 2 : 1))
        .overlay(alignment: .topTrailing) {
            if hovering.value {
                HStack(spacing: 6) {
                    cardButton(clip.pinned ? "pin.fill" : "pin") { store.togglePin(clip) }
                    cardButton("trash") { store.delete(clip) }
                }
                .padding(.top, 8).padding(.trailing, 8)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering.value = $0 }
        .overlay {
            if copied.value {
                Text("Copied").font(.system(size: fs(13), weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7).background(.black.opacity(0.7), in: Capsule())
                    .transition(.opacity)
            }
        }
        .accessibleTap(hint: "Copies the item") {
            if Settings.shared.v.pasteMode == .expand { store.expanded = clip; return }
            if inWindow {
                store.copy(clip)
                if Settings.shared.v.sounds { NSSound(named: "Pop")?.play() }
                withAnimation(.easeOut(duration: 0.15)) { copied.value = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation { copied.value = false } }
            } else {
                AppModel.shared.use(clip)
            }
        }
        .onDrag { dragProvider(clip) }
        .contextMenu { ClipMenu(clip: clip, store: store) }
    }

    private func cardButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 24, height: 24).background(.black.opacity(0.55), in: Circle())
            .contentShape(Circle()).accessibleTap(symbolLabel(symbol), combine: false, action)
    }

    private var host: String {
        let t = (clip.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: t)?.host?.replacingOccurrences(of: "www.", with: "") ?? t
    }

    private func footer(_ cat: Category) -> String {
        switch cat {
        case .text: return clip.sensitive ? "Hidden" : "\((clip.text ?? "").count) characters"
        case .link: return host
        case .color: return "Color"
        case .image where clip.imageURL != nil: return clip.imageURL.flatMap(Thumbs.dimensions) ?? "Image"
        default:
            guard let url = clip.fileURLs.first else { return cat.label }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
            let name = clip.fileURLs.count > 1 ? "\(url.lastPathComponent) + \(clip.fileURLs.count - 1)" : url.lastPathComponent
            return [name, size].compactMap { $0 }.joined(separator: " · ")
        }
    }
}
