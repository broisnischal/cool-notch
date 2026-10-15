import SwiftUI

/// The tab strip lives in the notch shoulders — the black band either side of the
/// camera that's otherwise dead space. Tabs split evenly, each half centred in its
/// shoulder so the strip is mirror-symmetric about the notch. One pill slides
/// between them (passing behind the camera when it crosses sides).
struct ShoulderTabs: View {
    @ObservedObject var state: NotchState
    @ObservedObject private var settings = AppSettings.shared
    @Namespace private var ns

    var body: some View {
        let tabs = settings.enabledTabs
        let split = (tabs.count + 1) / 2
        let gap = state.geo.notchWidth > 0 ? state.geo.notchWidth + 20 : 20
        HStack(spacing: 0) {
            group(Array(tabs.prefix(split)))
                .frame(maxWidth: .infinity)
            Color.clear.frame(width: gap)
            group(Array(tabs.dropFirst(split)))
                .frame(maxWidth: .infinity)
        }
        .frame(height: state.geo.notchHeight)
    }

    private func group(_ tabs: [NotchTab]) -> some View {
        HStack(spacing: DS.tabSpacing) {
            ForEach(tabs) { tab in
                TabSegment(tab: tab, selected: state.selectedTab == tab, ns: ns) { state.select(tab) }
            }
        }
    }
}

private struct TabSegment: View {
    let tab: NotchTab
    let selected: Bool
    let ns: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Icon(tab.icon, size: 17, weight: selected ? .semibold : .regular)
                .foregroundStyle(selected ? DS.textPrimary : (hovering ? DS.textSecondary : DS.textTertiary))
                .frame(width: DS.tab, height: DS.tab)
                .overlay(alignment: .bottom) {
                    if selected {
                        Capsule()
                            .fill(DS.accent)
                            .frame(width: 12, height: 2.5)
                            .offset(y: 3)
                            .matchedGeometryEffect(id: "tabdot", in: ns)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(Pressable())
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { h in withAnimation(DS.hover) { hovering = h } }
    }
}

/// Shared empty / status state for the feeds.
struct FeedStatus: View {
    let icon: String
    let text: String
    var accessory: AnyView? = nil

    var body: some View {
        VStack(spacing: 6) {
            Icon(icon, size: 20.8, weight: .regular)
                .foregroundStyle(DS.textTertiary)
            Text(text)
                .font(.ui(11, .regular))
                .foregroundStyle(DS.textTertiary)
                .multilineTextAlignment(.center)
            if let accessory { accessory.padding(.top, 2) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }
}
