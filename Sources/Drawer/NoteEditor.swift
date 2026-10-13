import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Live Markdown styling

/// Styles Markdown as you type: headings, bold, italic, strikethrough, code, links, lists, quotes. The syntax stays in
/// the text (notes are plain Markdown files) but is dimmed, so the page reads as formatted.
enum MarkdownStyler {
    static func apply(to storage: NSTextStorage, size: CGFloat) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        let base = NSFont.systemFont(ofSize: size)
        let dim = NSColor.tertiaryLabelColor
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 4
        storage.beginEditing()
        storage.setAttributes([.font: base, .foregroundColor: NSColor.labelColor, .paragraphStyle: para], range: full)

        func each(_ pattern: String, _ options: NSRegularExpression.Options = [], _ body: (NSTextCheckingResult) -> Void) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            re.enumerateMatches(in: storage.string, range: full) { m, _, _ in if let m { body(m) } }
        }
        func addTrait(_ trait: NSFontTraitMask, _ range: NSRange) {
            storage.enumerateAttribute(.font, in: range) { value, r, _ in
                let f = (value as? NSFont) ?? base
                storage.addAttribute(.font, value: NSFontManager.shared.convert(f, toHaveTrait: trait), range: r)
            }
        }
        func markers(_ m: NSTextCheckingResult, _ n: Int) {
            storage.addAttribute(.foregroundColor, value: dim, range: NSRange(location: m.range.location, length: n))
            storage.addAttribute(.foregroundColor, value: dim, range: NSRange(location: m.range.location + m.range.length - n, length: n))
        }

        each(#"^(#{1,3})[ \t]+(.*)$"#, [.anchorsMatchLines]) { m in
            let level = m.range(at: 1).length
            let sizes: [CGFloat] = [size * 1.8, size * 1.45, size * 1.2]
            let font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: sizes[level - 1]), toHaveTrait: .boldFontMask)
            storage.addAttribute(.font, value: font, range: m.range)
            storage.addAttribute(.foregroundColor, value: dim, range: m.range(at: 1))
        }
        each(#"\*\*(?=\S)(.+?)(?<=\S)\*\*"#) { m in addTrait(.boldFontMask, m.range(at: 1)); markers(m, 2) }
        each(#"(?<![\*\w])\*(?=\S)([^\*\n]+?)(?<=\S)\*(?![\*\w])"#) { m in addTrait(.italicFontMask, m.range(at: 1)); markers(m, 1) }
        each(#"~~(?=\S)(.+?)(?<=\S)~~"#) { m in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 1)); markers(m, 2)
        }
        each(#"`([^`\n]+)`"#) { m in
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size * 0.92, weight: .regular), range: m.range(at: 1))
            storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: m.range(at: 1))
            markers(m, 1)
        }
        each(#"\[([^\]\n]+)\]\(([^)\n]+)\)"#) { m in
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: m.range(at: 1))
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 1))
            storage.addAttribute(.foregroundColor, value: dim, range: m.range(at: 2))
        }
        each(#"^[ \t]*([-*])[ \t]"#, [.anchorsMatchLines]) { m in storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: m.range(at: 1)) }
        each(#"^[ \t]*(\d+\.)[ \t]"#, [.anchorsMatchLines]) { m in storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: m.range(at: 1)) }
        each(#"^[ \t]*- \[([xX])\][ \t]*(.*)$"#, [.anchorsMatchLines]) { m in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 2))
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range(at: 2))
        }
        each(#"^>[ \t]?.*$"#, [.anchorsMatchLines]) { m in
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range)
            addTrait(.italicFontMask, m.range)
        }
        each(#"^-{3,}$"#, [.anchorsMatchLines]) { m in storage.addAttribute(.foregroundColor, value: dim, range: m.range) }
        storage.endEditing()
    }
}

// MARK: - Formatting actions

/// The bridge between the toolbar and the text view: wraps selections and toggles line prefixes as Markdown.
final class NoteEditorController: ObservableObject {
    weak var textView: NSTextView?

    private func replace(_ range: NSRange, with s: String, select: NSRange) {
        guard let tv = textView else { return }
        if tv.shouldChangeText(in: range, replacementString: s) {
            tv.textStorage?.replaceCharacters(in: range, with: s)
            tv.didChangeText()
        }
        tv.setSelectedRange(select)
        tv.window?.makeFirstResponder(tv)
    }

    /// **bold**, *italic*, ~~strike~~, `code`: wrap the selection, or unwrap it if it is already wrapped.
    func wrap(_ marker: String) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        let m = marker.count
        if sel.length == 0 {
            replace(sel, with: marker + marker, select: NSRange(location: sel.location + m, length: 0))
            return
        }
        let before = sel.location >= m ? ns.substring(with: NSRange(location: sel.location - m, length: m)) : ""
        let afterLoc = sel.location + sel.length
        let after = afterLoc + m <= ns.length ? ns.substring(with: NSRange(location: afterLoc, length: m)) : ""
        if before == marker, after == marker {
            let outer = NSRange(location: sel.location - m, length: sel.length + 2 * m)
            replace(outer, with: ns.substring(with: sel), select: NSRange(location: outer.location, length: sel.length))
        } else {
            replace(sel, with: marker + ns.substring(with: sel) + marker, select: NSRange(location: sel.location + m, length: sel.length))
        }
    }

    private static let listPrefix = try! NSRegularExpression(pattern: #"^(\s*)(- \[[ xX]\] |[-*] |\d+\. |> )"#)

    /// Bulleted, numbered, checklist and quote lines: applied to every selected line, removed if all already have it.
    func list(_ kind: String) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let lineRange = ns.lineRange(for: tv.selectedRange())
        var block = ns.substring(with: lineRange)
        let trailing = block.hasSuffix("\\n")
        if trailing { block.removeLast() }
        var lines = block.components(separatedBy: "\\n")
        func prefix(_ i: Int) -> String {
            switch kind { case "number": "\\(i + 1). "; case "check": "- [ ] "; case "quote": "> "; default: "- " }
        }
        func stripped(_ line: String) -> String {
            let r = NSRange(location: 0, length: (line as NSString).length)
            guard let m = Self.listPrefix.firstMatch(in: line, range: r) else { return line }
            return (line as NSString).substring(with: m.range(at: 1)) + (line as NSString).substring(from: m.range.location + m.range.length)
        }
        func has(_ line: String) -> Bool {
            switch kind {
            case "number": return line.range(of: #"^\\s*\\d+\\. "#, options: .regularExpression) != nil
            case "check": return line.range(of: #"^\\s*- \\[[ xX]\\] "#, options: .regularExpression) != nil
            case "quote": return line.hasPrefix("> ")
            default: return line.range(of: #"^\\s*[-*] (?!\\[)"#, options: .regularExpression) != nil
            }
        }
        let allHave = lines.allSatisfy(has)
        lines = lines.enumerated().map { i, line in
            let bare = stripped(line)
            return allHave ? bare : prefix(i) + bare
        }
        let new = lines.joined(separator: "\\n") + (trailing ? "\\n" : "")
        replace(lineRange, with: new, select: NSRange(location: lineRange.location, length: (new as NSString).length - (trailing ? 1 : 0)))
    }

    /// Title, heading, subtitle (1–3 hashes) or body text (0).
    func heading(_ level: Int) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let lineRange = ns.lineRange(for: tv.selectedRange())
        var line = ns.substring(with: lineRange)
        let trailing = line.hasSuffix("\\n")
        if trailing { line.removeLast() }
        let current = line.prefix(while: { $0 == "#" }).count
        if let r = line.range(of: #"^#{1,6}\\s+"#, options: .regularExpression) { line.removeSubrange(r) }
        if level > 0, current != level { line = String(repeating: "#", count: level) + " " + line }
        let new = line + (trailing ? "\\n" : "")
        replace(lineRange, with: new, select: NSRange(location: lineRange.location + (new as NSString).length - (trailing ? 1 : 0), length: 0))
    }

    func link() {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        let label = sel.length > 0 ? ns.substring(with: sel) : "link text"
        let new = "[\\(label)](https://)"
        let urlStart = sel.location + (label as NSString).length + 3
        replace(sel, with: new, select: NSRange(location: urlStart, length: 8))
    }

    func divider() {
        guard let tv = textView else { return }
        let sel = tv.selectedRange()
        replace(sel, with: "\\n\\n---\\n\\n", select: NSRange(location: sel.location + 7, length: 0))
    }
}

// MARK: - The editor

/// A text view that shows Markdown formatted as you type. Replaces TextEditor so the toolbar can reach the selection.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    let controller: NoteEditorController

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 0, height: 4)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.insertionPointColor = .controlAccentColor
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        controller.textView = tv
        tv.string = text
        restyle(tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        controller.textView = tv
        context.coordinator.parent = self
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
        }
        restyle(tv)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    fileprivate func restyle(_ tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        MarkdownStyler.apply(to: storage, size: fontSize)
        tv.typingAttributes = [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.labelColor]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        init(_ parent: MarkdownEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.restyle(tv)
        }
    }
}

// MARK: - Toolbar

/// A floating pill of formatting controls, in the manner of Craft's: text style, inline marks, lists, link, divider.
struct NoteToolbar: View {
    let controller: NoteEditorController

    var body: some View {
        HStack(spacing: 2) {
            Menu {
                Button("Title") { controller.heading(1) }
                Button("Heading") { controller.heading(2) }
                Button("Subtitle") { controller.heading(3) }
                Button("Body") { controller.heading(0) }
            } label: {
                HStack(spacing: 4) {
                    Text("Text").font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.primary).padding(.horizontal, 9).frame(height: 28)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            divider
            tool("bold", "Bold") { controller.wrap("**") }
            tool("italic", "Italic") { controller.wrap("*") }
            tool("strikethrough", "Strikethrough") { controller.wrap("~~") }
            tool("chevron.left.forwardslash.chevron.right", "Code") { controller.wrap("`") }
            tool("link", "Link") { controller.link() }
            divider
            tool("list.bullet", "Bulleted list") { controller.list("bullet") }
            tool("list.number", "Numbered list") { controller.list("number") }
            tool("checklist", "Checklist") { controller.list("check") }
            tool("text.quote", "Quote") { controller.list("quote") }
            tool("minus", "Divider") { controller.divider() }
        }
        .padding(5)
        .lookCard(radius: 13)
    }

    private var divider: some View {
        Rectangle().fill(Look.hairline).frame(width: 1, height: 18).padding(.horizontal, 4)
    }

    private func tool(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        ToolButton(symbol: symbol, help: help, action: action)
    }
}

private struct ToolButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @StateObject private var hovering = Box(false)

    var body: some View {
        Image(systemName: symbol).font(.system(size: 13, weight: .medium))
            .foregroundStyle(hovering.value ? Color.primary : Color.secondary)
            .frame(width: 30, height: 28)
            .background(hovering.value ? Look.selection : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hovering.value = $0 }
            .onTapGesture(perform: action)
            .help(help)
    }
}

// MARK: - Rendering and export

/// Markdown turned into formatted text for PDF, rich text and copy-as-rich-text.
enum NoteRenderer {
    static func attributed(_ markdown: String, size: CGFloat = 13) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        para.paragraphSpacing = 4
        func line(_ s: NSAttributedString) {
            let m = NSMutableAttributedString(attributedString: s)
            m.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: m.length))
            out.append(m)
            out.append(NSAttributedString(string: "\\n"))
        }
        func inline(_ s: String, _ prefix: String = "") -> NSAttributedString {
            let body = NSMutableAttributedString(attributedString: RichText.attributed(fromMarkdown: s))
            body.addAttribute(.font, value: NSFont.systemFont(ofSize: size), range: NSRange(location: 0, length: body.length))
            let all = NSMutableAttributedString(string: prefix, attributes: [.font: NSFont.systemFont(ofSize: size)])
            all.append(body)
            return all
        }
        for raw in markdown.components(separatedBy: "\\n") {
            if let m = raw.range(of: #"^(#{1,3})\\s+"#, options: .regularExpression) {
                let level = raw[m].filter { $0 == "#" }.count
                let sizes: [CGFloat] = [size * 1.9, size * 1.5, size * 1.2]
                let font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: sizes[level - 1]), toHaveTrait: .boldFontMask)
                line(NSAttributedString(string: String(raw[m.upperBound...]), attributes: [.font: font]))
            } else if raw.range(of: #"^\\s*- \\[[xX]\\] "#, options: .regularExpression) != nil {
                line(inline(raw.replacingOccurrences(of: #"^\\s*- \\[[xX]\\] "#, with: "", options: .regularExpression), "☑ "))
            } else if raw.range(of: #"^\\s*- \\[ \\] "#, options: .regularExpression) != nil {
                line(inline(raw.replacingOccurrences(of: #"^\\s*- \\[ \\] "#, with: "", options: .regularExpression), "☐ "))
            } else if raw.range(of: #"^\\s*[-*] "#, options: .regularExpression) != nil {
                line(inline(raw.replacingOccurrences(of: #"^\\s*[-*] "#, with: "", options: .regularExpression), "• "))
            } else if raw.hasPrefix("> ") {
                let q = NSMutableAttributedString(attributedString: inline(String(raw.dropFirst(2))))
                q.addAttribute(.foregroundColor, value: NSColor.darkGray, range: NSRange(location: 0, length: q.length))
                line(q)
            } else if raw.range(of: #"^-{3,}$"#, options: .regularExpression) != nil {
                line(NSAttributedString(string: "────────────────────", attributes: [.foregroundColor: NSColor.lightGray]))
            } else {
                line(inline(raw))
            }
        }
        return out
    }

    /// Markdown as plain text: syntax characters removed.
    static func plain(_ markdown: String) -> String {
        attributed(markdown).string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum NoteFormat {
    case markdown, text, rtf, pdf
    var ext: String {
        switch self { case .markdown: "md"; case .text: "txt"; case .rtf: "rtf"; case .pdf: "pdf" }
    }
}

enum NoteExport {
    static func export(_ note: Note, as format: NoteFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (note.title.isEmpty ? "Note" : note.title) + "." + format.ext
        if let type = UTType(filenameExtension: format.ext) { panel.allowedContentTypes = [type] }
        panel.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch format {
        case .markdown: try? note.text.write(to: url, atomically: true, encoding: .utf8)
        case .text: try? NoteRenderer.plain(note.text).write(to: url, atomically: true, encoding: .utf8)
        case .rtf:
            let attr = NoteRenderer.attributed(note.text)
            if let data = try? attr.data(from: NSRange(location: 0, length: attr.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                try? data.write(to: url)
            }
        case .pdf: writePDF(note, to: url)
        }
    }

    private static func writePDF(_ note: Note, to url: URL) {
        let width: CGFloat = 612 - 144
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        tv.isVerticallyResizable = true
        tv.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textStorage?.setAttributedString(NoteRenderer.attributed(note.text))
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        let used = tv.layoutManager?.usedRect(for: tv.textContainer!) ?? .zero
        tv.frame = NSRect(x: 0, y: 0, width: width, height: max(used.height + 8, 100))
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 612, height: 792)
        info.topMargin = 72; info.bottomMargin = 72; info.leftMargin = 72; info.rightMargin = 72
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let op = NSPrintOperation(view: tv, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.run()
    }
}

// MARK: - Right-click menu

/// Everything you can do with a note, wherever it is shown.
struct NoteMenu: View {
    let note: Note
    let store: NotesStore

    var body: some View {
        Button("Copy Text") { copy { $0.setString(NoteRenderer.plain(note.text), forType: .string) } }
        Button("Copy as Markdown") { copy { $0.setString(note.text, forType: .string) } }
        Button("Copy as Rich Text") { copy { _ in NSPasteboard.general.writeObjects([NoteRenderer.attributed(note.text)]) } }
        Divider()
        Button("Duplicate") { store.duplicate(note) }
        Menu("Export") {
            Button("Markdown (.md)") { NoteExport.export(note, as: .markdown) }
            Button("Plain Text (.txt)") { NoteExport.export(note, as: .text) }
            Button("Rich Text (.rtf)") { NoteExport.export(note, as: .rtf) }
            Button("PDF") { NoteExport.export(note, as: .pdf) }
        }
        if let f = note.fileName {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.folder.appendingPathComponent(f)]) }
        }
        Divider()
        Button("Delete") { store.delete(note) }
    }

    private func copy(_ write: (NSPasteboard) -> Void) {
        let pb = NSPasteboard.general
        pb.clearContents()
        write(pb)
    }
}
