import SwiftUI
import UniformTypeIdentifiers

/// A temporary parking spot for files. Drag files onto the panel to hold them,
/// then drag them back out into any app or Finder window later. No permissions,
/// no copies — it just remembers URLs for the session.
struct ShelfView: View {
    @ObservedObject var state: NotchState

    private var dropShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(dropShape.fill(state.isDropTargeted ? DS.accent.opacity(0.10) : .clear))
            .overlay(
                dropShape.strokeBorder(
                    state.isDropTargeted ? DS.accent : DS.stroke,
                    style: StrokeStyle(lineWidth: state.isDropTargeted ? 1.5 : 1,
                                       dash: state.shelfItems.isEmpty ? [4, 3] : [])
                )
            )
            .animation(DS.press, value: state.isDropTargeted)
            .dropDestination(for: URL.self) { urls, _ in
                state.addFiles(urls)
                return true
            } isTargeted: { targeted in
                state.isDropTargeted = targeted
            }
    }

    @ViewBuilder private var content: some View {
        if state.shelfItems.isEmpty {
            HStack(spacing: 6) {
                Icon("tray.and.arrow.down", size: 15.6, weight: .medium)
                Text("Drop files here to keep them handy")
                    .font(.ui(11, .medium))
            }
            .foregroundStyle(DS.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                SectionLabel(text: "Shelf · \(state.shelfItems.count)") {
                    PillButton(title: "Clear") { state.clearShelf() }
                }
                .padding(.horizontal, DS.inset).padding(.top, 6)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(state.shelfItems) { item in
                            ShelfChip(item: item) { state.remove(item) }
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                                    removal: .scale(scale: 0.85).combined(with: .opacity)
                                ))
                        }
                    }
                    .padding(.horizontal, 6).padding(.vertical, 4)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

/// A single file chip: Finder icon + name, draggable back out, removable on hover.
struct ShelfChip: View {
    let item: ShelfItem
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
            Text(item.name)
                .font(.ui(9, .medium))
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 50)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: DS.chipRadius, style: .continuous)
                .fill(Color.clear)
        )
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: onRemove) {
                    Icon("xmark.circle.fill", size: 15.6)
                        .foregroundStyle(.white, .black.opacity(0.5))
                        .background(Circle().fill(.black.opacity(0.001)))
                }
                .buttonStyle(Pressable())
                .offset(x: 3, y: -3)
                .transition(.iconSwap)
                .accessibilityLabel("Remove \(item.name)")
            }
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .draggable(item.url) {
            // Drag preview
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 44, height: 44)
        }
        .help(item.url.path)
    }
}
