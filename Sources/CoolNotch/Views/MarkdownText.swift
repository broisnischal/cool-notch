import SwiftUI

/// A small block-level markdown renderer good enough for chat: headings, bullet
/// and numbered lists, block quotes, fenced code, and inline **bold** / *italic* /
/// `code` / links. SwiftUI's `AttributedString(markdown:)` only does inline, so we
/// split into blocks ourselves and style each.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                block.view
            }
        }
    }

    private var blocks: [MDBlock] { MDParser.parse(text) }
}

private enum MDBlock {
    case heading(level: Int, String)
    case bullet(String)
    case numbered(String, String)   // marker, text
    case quote(String)
    case code(String)
    case paragraph(String)

    @ViewBuilder var view: some View {
        switch self {
        case .heading(let level, let s):
            inline(s)
                .font(.ui(level <= 1 ? 16 : (level == 2 ? 14 : 13), .bold))
                .foregroundStyle(DS.textPrimary)
                .padding(.top, 2)
        case .bullet(let s):
            HStack(alignment: .top, spacing: 7) {
                Text("•").font(.ui(12, .bold)).foregroundStyle(DS.accent)
                inline(s).frame(maxWidth: .infinity, alignment: .leading)
            }
        case .numbered(let m, let s):
            HStack(alignment: .top, spacing: 7) {
                Text(m).font(.mono(11, .semibold)).foregroundStyle(DS.accent)
                inline(s).frame(maxWidth: .infinity, alignment: .leading)
            }
        case .quote(let s):
            HStack(spacing: 8) {
                Rectangle().fill(DS.accent.opacity(0.5)).frame(width: 2)
                inline(s).foregroundStyle(DS.textSecondary)
            }
        case .code(let s):
            Text(s)
                .font(.mono(11, .regular))
                .foregroundStyle(DS.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.35)))
        case .paragraph(let s):
            inline(s).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func inline(_ s: String) -> Text {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attr = try? AttributedString(markdown: s, options: opts) {
            return Text(attr).font(.ui(12, .regular))
        }
        return Text(s).font(.ui(12, .regular))
    }
}

private enum MDParser {
    static func parse(_ text: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        var inCode = false
        var codeLines: [String] = []

        for raw in text.components(separatedBy: "\n") {
            let line = raw

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines = []; inCode = false
                } else { inCode = true }
                continue
            }
            if inCode { codeLines.append(line); continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if let h = heading(trimmed) { blocks.append(h); continue }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                blocks.append(.bullet(String(trimmed.dropFirst(2)))); continue
            }
            if let num = numbered(trimmed) { blocks.append(num); continue }
            if trimmed.hasPrefix("> ") {
                blocks.append(.quote(String(trimmed.dropFirst(2)))); continue
            }
            blocks.append(.paragraph(trimmed))
        }
        if inCode, !codeLines.isEmpty { blocks.append(.code(codeLines.joined(separator: "\n"))) }
        return blocks
    }

    private static func heading(_ s: String) -> MDBlock? {
        var level = 0
        for ch in s { if ch == "#" { level += 1 } else { break } }
        guard level >= 1, level <= 6, s.count > level, s[s.index(s.startIndex, offsetBy: level)] == " "
        else { return nil }
        return .heading(level: level, String(s.dropFirst(level + 1)))
    }

    private static func numbered(_ s: String) -> MDBlock? {
        guard let dot = s.firstIndex(of: "."), s.distance(from: s.startIndex, to: dot) <= 2 else { return nil }
        let marker = String(s[s.startIndex..<dot])
        guard Int(marker) != nil, s.index(after: dot) < s.endIndex,
              s[s.index(after: dot)] == " " else { return nil }
        let rest = String(s[s.index(dot, offsetBy: 2)...])
        return .numbered(marker + ".", rest)
    }
}
