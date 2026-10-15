import SwiftUI

/// Clipboard history — most recent first. Tap to copy back (briefly shows a check).
struct ClipboardView: View {
    @ObservedObject var clipboard: ClipboardService
    @State private var copiedID: UUID?

    var body: some View {
        if clipboard.items.isEmpty {
            FeedStatus(icon: "doc.on.clipboard", text: "Copied text will show up here")
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                SeparatedList(items: clipboard.items) { item in
                    ClipRow(item: item, copied: copiedID == item.id) {
                        clipboard.copy(item)
                        copiedID = item.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                            if copiedID == item.id { copiedID = nil }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct ClipRow: View {
    let item: ClipItem
    let copied: Bool
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Icon(copied ? "checkmark" : "doc.on.doc", size: 13, weight: .regular)
                    .id(copied)
                    .transition(.iconSwap)
                    .foregroundStyle(copied ? DS.good : DS.textTertiary)
                    .frame(width: 12)

                Text(item.preview)
                    .font(.body)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(item.date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                    .font(.caption)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            .rowSurface(hovering: hovering, height: 30)
        }
        .buttonStyle(Pressable())
        .onHover { h in withAnimation(DS.hover) { hovering = h } }
    }
}
