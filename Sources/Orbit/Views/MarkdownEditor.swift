import SwiftUI
import AppKit

/// Not editörü yazı ayarları (Ayarlar ve editördeki "Aa" menüsünden değişir)
struct EditorTypography: Equatable {
    enum Family: String, CaseIterable, Identifiable {
        case system, serif, rounded, mono
        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: "SF Pro"
            case .serif: "New York (Serif)"
            case .rounded: "SF Rounded"
            case .mono: "SF Mono"
            }
        }
        var design: Font.Design {
            switch self { case .system: .default; case .serif: .serif; case .rounded: .rounded; case .mono: .monospaced }
        }
        var nsDesign: NSFontDescriptor.SystemDesign {
            switch self { case .system: .default; case .serif: .serif; case .rounded: .rounded; case .mono: .monospaced }
        }
    }
    var family: Family = .system
    var size: CGFloat = 15
    /// Satır yüksekliği çarpanı
    var lineHeight: CGFloat = 1.45

    static var current: EditorTypography {
        let d = UserDefaults.standard
        return EditorTypography(
            family: Family(rawValue: d.string(forKey: "editorFont") ?? "") ?? .system,
            size: CGFloat(d.object(forKey: "editorSize") as? Double ?? 15),
            lineHeight: CGFloat(d.object(forKey: "editorLineHeight") as? Double ?? 1.45))
    }

    func nsFont(_ size: CGFloat? = nil, weight: NSFont.Weight = .regular, italic: Bool = false) -> NSFont {
        let base = NSFont.systemFont(ofSize: size ?? self.size, weight: weight)
        var desc = base.fontDescriptor.withDesign(family.nsDesign) ?? base.fontDescriptor
        if italic { desc = desc.withSymbolicTraits(.italic) }
        return NSFont(descriptor: desc, size: size ?? self.size) ?? base
    }
    func headingSize(_ level: Int) -> CGFloat { size * [1.8, 1.45, 1.2][max(0, min(2, level - 1))] }
    var codeSize: CGFloat { size * 0.88 }
    /// SwiftUI satır arası boşluk (pt)
    var lineSpacing: CGFloat { size * (lineHeight - 1) }
}

/// Toolbar komutlarını editöre iletmek için köprü
final class EditorController: ObservableObject {
    weak var textView: NSTextView?

    var selectedText: String {
        guard let tv = textView else { return "" }
        return (tv.string as NSString).substring(with: tv.selectedRange())
    }

    /// Seçimi önek/sonek ile sarar (bold, italic…)
    func wrap(_ prefix: String, _ suffix: String? = nil, placeholder: String = "metin") {
        guard let tv = textView else { return }
        let s = suffix ?? prefix
        let r = tv.selectedRange()
        let sel = (tv.string as NSString).substring(with: r)
        let body = sel.isEmpty ? placeholder : sel
        replace(r, with: prefix + body + s)
        tv.setSelectedRange(NSRange(location: r.location + (prefix as NSString).length, length: (body as NSString).length))
    }

    /// Seçili satırların başına önek koyar/kaldırır (başlık, liste, alıntı…)
    func linePrefix(_ prefix: String, numbered: Bool = false) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let lineRange = ns.lineRange(for: tv.selectedRange())
        let text = ns.substring(with: lineRange)
        var lines = text.components(separatedBy: "\n")
        let trailing = lines.last == "" ? lines.removeLast() : nil
        let headingRe = try! NSRegularExpression(pattern: #"^(#{1,6} |- \[[ x]\] |- |\d+\. |> )"#)
        let allHave = lines.allSatisfy { numbered ? $0.range(of: #"^\d+\. "#, options: .regularExpression) != nil : $0.hasPrefix(prefix) }
        var n = 1
        lines = lines.map { line in
            let stripped = headingRe.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: (line as NSString).length), withTemplate: "")
            if allHave { return stripped }
            defer { n += 1 }
            return (numbered ? "\(n). " : prefix) + stripped
        }
        var out = lines.joined(separator: "\n")
        if trailing != nil { out += "\n" }
        replace(lineRange, with: out)
    }

    func insert(_ text: String) {
        guard let tv = textView else { return }
        replace(tv.selectedRange(), with: text)
    }

    func codeBlock() {
        let sel = selectedText
        guard let tv = textView else { return }
        let r = tv.selectedRange()
        let body = sel.isEmpty ? "kod" : sel
        replace(r, with: "\n```\n\(body)\n```\n")
        tv.setSelectedRange(NSRange(location: r.location + 5, length: (body as NSString).length))
    }

    private func replace(_ r: NSRange, with s: String) {
        guard let tv = textView else { return }
        if tv.shouldChangeText(in: r, replacementString: s) {
            tv.textStorage?.replaceCharacters(in: r, with: s)
            tv.didChangeText()
        }
        tv.window?.makeFirstResponder(tv)
    }
}

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    let controller: EditorController
    var focusToken: UUID? = nil
    var typography = EditorTypography()

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.font = typography.nsFont()
        tv.textContainerInset = NSSize(width: 4, height: 12)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.string = text
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        controller.textView = tv
        context.coordinator.highlight(tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let tv = scroll.documentView as! NSTextView
        controller.textView = tv
        let typoChanged = context.coordinator.parent.typography != typography
        context.coordinator.parent = self
        if tv.string != text {
            tv.string = text
            context.coordinator.highlight(tv)
        } else if typoChanged {
            context.coordinator.highlight(tv)
        }
        if let token = focusToken, token != context.coordinator.lastFocus {
            context.coordinator.lastFocus = token
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        var lastFocus: UUID?
        init(_ p: MarkdownTextView) { parent = p; lastFocus = p.focusToken }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.text = tv.string
            highlight(tv)
        }

        /// Enter'a basınca liste işaretini devam ettirir
        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            guard sel == #selector(NSResponder.insertNewline(_:)) else { return false }
            let ns = tv.string as NSString
            let lr = ns.lineRange(for: NSRange(location: tv.selectedRange().location, length: 0))
            let line = ns.substring(with: lr).trimmingCharacters(in: .newlines)
            let patterns: [(String, (String) -> String)] = [
                (#"^(\s*)- \[[ x]\] "#, { m in m.replacingOccurrences(of: "[x]", with: "[ ]") }),
                (#"^(\s*)[-*] "#, { $0 }),
                (#"^(\s*)> "#, { $0 }),
                (#"^(\s*)(\d+)\. "#, { m in
                    let num = Int(m.trimmingCharacters(in: .whitespaces).dropLast(2)) ?? 0
                    return m.replacingOccurrences(of: "\(num).", with: "\(num + 1).")
                }),
            ]
            for (p, next) in patterns {
                if let r = line.range(of: p, options: .regularExpression) {
                    let marker = String(line[r])
                    if line.count == marker.count {
                        // boş öğe: listeyi bitir
                        tv.insertText("", replacementRange: NSRange(location: lr.location, length: (line as NSString).length))
                        return false
                    }
                    tv.insertText("\n" + next(marker), replacementRange: tv.selectedRange())
                    return true
                }
            }
            return false
        }

        func highlight(_ tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            let s = storage.string as NSString
            let full = NSRange(location: 0, length: s.length)
            let t = parent.typography
            let base = t.nsFont()
            let para = NSMutableParagraphStyle()
            para.lineHeightMultiple = t.lineHeight
            para.paragraphSpacing = t.size * 0.35
            let accent = NSColor(Color.accentColor)
            storage.beginEditing()
            storage.setAttributes([.font: base, .foregroundColor: NSColor.labelColor, .paragraphStyle: para], range: full)

            func apply(_ pattern: String, _ opts: NSRegularExpression.Options = [.anchorsMatchLines], _ attrs: (NSTextCheckingResult) -> [(NSRange, [NSAttributedString.Key: Any])]) {
                guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return }
                for m in re.matches(in: storage.string, range: full) {
                    for (r, a) in attrs(m) where r.location != NSNotFound { storage.addAttributes(a, range: r) }
                }
            }
            let dim: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.tertiaryLabelColor]
            let mono = NSFont.monospacedSystemFont(ofSize: t.codeSize, weight: .regular)
            apply(#"^(#{1,3}) (.*)$"#) { m in
                let level = m.range(at: 1).length
                let f = t.nsFont(t.headingSize(level), weight: .bold)
                let hp = NSMutableParagraphStyle()
                hp.lineHeightMultiple = 1.15
                hp.paragraphSpacingBefore = t.size * (level == 1 ? 0.9 : 0.6)
                hp.paragraphSpacing = t.size * 0.3
                return [(m.range, [.paragraphStyle: hp]), (m.range(at: 2), [.font: f]), (m.range(at: 1), dim.merging([.font: f]) { $1 })]
            }
            apply(#"\*\*([^*\n]+)\*\*"#) { m in [(m.range, [.font: t.nsFont(weight: .bold)])] }
            apply(#"(?<![*\w])\*([^*\n]+)\*(?!\*)"#) { m in [(m.range, [.font: t.nsFont(italic: true)])] }
            apply(#"<u>(.+?)</u>"#) { m in [(m.range(at: 1), [.underlineStyle: NSUnderlineStyle.single.rawValue]), (NSRange(location: m.range.location, length: 3), dim), (NSRange(location: NSMaxRange(m.range) - 4, length: 4), dim)] }
            apply(#"`([^`\n]+)`"#) { m in [(m.range, [.font: mono, .foregroundColor: NSColor.systemPink])] }
            apply(#"^```[\s\S]*?^```"#, [.anchorsMatchLines]) { m in
                let cp = NSMutableParagraphStyle()
                cp.lineHeightMultiple = 1.25
                return [(m.range, [.font: mono, .foregroundColor: NSColor.secondaryLabelColor, .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.08), .paragraphStyle: cp])]
            }
            apply(#"^> .*$"#) { m in [(m.range, [.foregroundColor: NSColor.secondaryLabelColor, .font: t.nsFont(italic: true)])] }
            apply(#"^\s*(- \[[ x]\]|[-*]|\d+\.) "#) { m in [(m.range(at: 1), [.foregroundColor: accent, .font: t.nsFont(weight: .bold)])] }
            apply(#"^\s*- \[x\] (.*)$"#) { m in [(m.range(at: 1), [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: NSColor.secondaryLabelColor])] }
            apply(#"\[\[([^\]]+)\]\]"#) { m in [(m.range, [.foregroundColor: accent, .font: t.nsFont(weight: .semibold)])] }
            apply(#"!?\[([^\]]*)\]\(([^)]+)\)"#) { m in [(m.range(at: 1), [.foregroundColor: NSColor.linkColor]), (m.range(at: 2), dim)] }
            storage.endEditing()
            tv.typingAttributes = [.font: base, .foregroundColor: NSColor.labelColor, .paragraphStyle: para]
        }
    }
}

// MARK: - Markdown önizleme

struct MarkdownPreview: View {
    let text: String
    var typography = EditorTypography()
    var onToggleCheckbox: ((Int) -> Void)? = nil
    var onOpenNote: ((String) -> Void)? = nil

    enum Block: Identifiable {
        case heading(Int, String, Int)
        case paragraph(String, Int)
        case bullet(String, Int, Int)
        case numbered(String, String, Int, Int)
        case check(Bool, String, Int)
        case quote(String, Int)
        case code(String, Int)
        case image(String, String, Int)
        case rule(Int)
        var id: Int {
            switch self {
            case .heading(_, _, let i), .paragraph(_, let i), .bullet(_, _, let i), .numbered(_, _, _, let i), .check(_, _, let i), .quote(_, let i), .code(_, let i), .image(_, _, let i), .rule(let i): i
            }
        }
    }

    var blocks: [Block] {
        var out: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)
            let indent = (line.prefix { $0 == " " }.count) / 2
            if t.hasPrefix("```") {
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { code.append(lines[i]); i += 1 }
                out.append(.code(code.joined(separator: "\n"), i))
            } else if let m = t.wholeMatch(of: /(#{1,3}) (.+)/) {
                out.append(.heading(m.1.count, String(m.2), i))
            } else if let m = t.wholeMatch(of: /- \[([ xX])\] (.*)/) {
                out.append(.check(m.1 != " ", String(m.2), i))
            } else if let m = t.wholeMatch(of: /[-*] (.*)/) {
                out.append(.bullet(String(m.1), indent, i))
            } else if let m = t.wholeMatch(of: /(\d+)\. (.*)/) {
                out.append(.numbered(String(m.1), String(m.2), indent, i))
            } else if t.hasPrefix("> ") {
                out.append(.quote(String(t.dropFirst(2)), i))
            } else if let m = t.wholeMatch(of: /!\[(.*)\]\((.+)\)/) {
                out.append(.image(String(m.1), String(m.2), i))
            } else if t == "---" || t == "***" {
                out.append(.rule(i))
            } else if !t.isEmpty {
                out.append(.paragraph(t, i))
            }
            i += 1
        }
        return out
    }

    var bodyFont: Font { .system(size: typography.size, design: typography.family.design) }

    func inline(_ s: String) -> Text {
        // [[Not]] → orbit://note/Not ; <u>x</u> → altı çizili
        var src = s.replacing(/\[\[([^\]]+)\]\]/) { m in "[\(m.1)](orbit://note/\(String(m.1).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""))" }
        var underlines: [String] = []
        src = src.replacing(/<u>(.+?)<\/u>/) { m in underlines.append(String(m.1)); return String(m.1) }
        var attr = (try? AttributedString(markdown: src, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(src)
        for u in underlines {
            if let r = attr.range(of: u) { attr[r].underlineStyle = .single }
        }
        return Text(attr)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { b in
                switch b {
                case .heading(let l, let s, _):
                    inline(s).font(.system(size: typography.headingSize(l), weight: .bold, design: typography.family.design)).padding(.top, l == 1 ? 6 : 10)
                case .paragraph(let s, _):
                    inline(s).font(bodyFont).lineSpacing(typography.lineSpacing)
                case .bullet(let s, let ind, _):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Color.accentColor).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        inline(s).font(bodyFont).lineSpacing(typography.lineSpacing)
                    }.padding(.leading, CGFloat(ind) * 18 + 4)
                case .numbered(let n, let s, let ind, _):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(n).").font(.system(size: typography.size, weight: .semibold, design: typography.family.design)).foregroundStyle(Color.accentColor).monospacedDigit()
                        inline(s).font(bodyFont).lineSpacing(typography.lineSpacing)
                    }.padding(.leading, CGFloat(ind) * 18 + 2)
                case .check(let done, let s, let line):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: done ? "checkmark.square.fill" : "square")
                            .foregroundStyle(done ? Palette.success : .secondary)
                            .onTapGesture { onToggleCheckbox?(line) }
                        inline(s).font(bodyFont).lineSpacing(typography.lineSpacing).strikethrough(done).foregroundStyle(done ? .secondary : .primary)
                    }
                case .quote(let s, _):
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 2).fill(Palette.purple).frame(width: 3)
                        inline(s).font(.system(size: typography.size + 0.5, design: typography.family.design)).italic().foregroundStyle(.secondary)
                    }.fixedSize(horizontal: false, vertical: true)
                case .code(let s, _):
                    Text(s).font(.system(size: typography.codeSize, design: .monospaced)).lineSpacing(3).textSelection(.enabled)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
                case .image(let alt, let src, _):
                    if let url = URL(string: src), url.isFileURL, let img = NSImage(contentsOf: url) {
                        Image(nsImage: img).resizable().scaledToFit().frame(maxWidth: 560).clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Label(alt.isEmpty ? src : alt, systemImage: "photo").foregroundStyle(.secondary)
                    }
                case .rule:
                    Divider()
                }
            }
        }
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "orbit", url.host == "note" {
                onOpenNote?(url.path.removingPercentEncoding.map { String($0.dropFirst()) } ?? "")
                return .handled
            }
            return .systemAction
        })
    }
}

enum Attachments {
    static var dir: URL {
        let d = URL.applicationSupportDirectory.appending(path: "Orbit/Attachments", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Dosyayı uygulama klasörüne kopyalar ve markdown bağlantısını döner
    static func pick(images: Bool) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if images { panel.allowedContentTypes = [.image] }
        guard panel.runModal() == .OK, let src = panel.url else { return nil }
        let dest = dir.appending(path: "\(UUID().uuidString.prefix(8))-\(src.lastPathComponent)")
        do { try FileManager.default.copyItem(at: src, to: dest) } catch { return nil }
        let name = src.deletingPathExtension().lastPathComponent
        return images ? "![\(name)](\(dest.absoluteString))" : "[📎 \(src.lastPathComponent)](\(dest.absoluteString))"
    }
}
