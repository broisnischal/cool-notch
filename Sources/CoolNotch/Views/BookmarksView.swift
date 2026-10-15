import SwiftUI

/// Website bookmarks — add a URL, tap to open in the default browser.
struct BookmarksView: View {
    @StateObject private var store = BookmarksService.shared
    @State private var url = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: DS.gap) {
            HStack(spacing: 8) {
                Icon("link", size: 14.3, weight: .semibold).foregroundStyle(DS.accent)
                TextField("Add a URL…", text: $url)
                    .textFieldStyle(.plain).font(.body).foregroundStyle(DS.textPrimary)
                    .focused($focused)
                    .onSubmit(add)
                Button(action: add) {
                    Icon("plus.circle.fill", size: 22.1)
                        .foregroundStyle(url.isEmpty ? DS.textTertiary : DS.accent)
                        .symbolRenderingMode(.hierarchical)
                }.buttonStyle(Pressable()).disabled(url.isEmpty).accessibilityLabel("Add bookmark")
            }
            .padding(.leading, DS.inset).padding(.trailing, 6)
            .frame(height: 36)
            .outline(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous), tint: focused ? DS.accent.opacity(0.6) : nil)
            .onAppear { NotificationCenter.default.post(name: .coolNotchNeedsKey, object: nil) }

            if store.items.isEmpty {
                FeedStatus(icon: "bookmark", text: "No bookmarks yet")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    SeparatedList(items: store.items) { item in BookmarkRow(item: item) }
                        .padding(.vertical, 2)
                }
            }
        }
    }

    private func add() {
        store.add(name: "", url: url)
        url = ""
    }
}

struct BookmarkRow: View {
    let item: Bookmark
    @State private var hovering = false

    var body: some View {
        Button { BookmarksService.shared.open(item) } label: {
            HStack(spacing: 8) {
                Icon("globe", size: 14.3, weight: .semibold).foregroundStyle(DS.accent)
                    .frame(width: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(.title).foregroundStyle(DS.textPrimary).lineLimit(1)
                    Text(item.url).font(.caption).foregroundStyle(DS.textTertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 6)
                if hovering {
                    Button { BookmarksService.shared.remove(item) } label: {
                        Icon("xmark.circle.fill", size: 15.6)
                            .foregroundStyle(.white, .black.opacity(0.4))
                    }.buttonStyle(Pressable())
                    .transition(.iconSwap)
                    .accessibilityLabel("Remove \(item.name)")
                }
                Icon("arrow.up.right", size: 11.7, weight: .semibold)
                    .foregroundStyle(DS.textTertiary)
            }
            .rowSurface(hovering: hovering)
        }
        .buttonStyle(Pressable())
        .onHover { h in withAnimation(DS.hover) { hovering = h } }
    }
}
