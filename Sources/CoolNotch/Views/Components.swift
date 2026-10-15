import SwiftUI

/// Card surface — a 1px outline on pure black. No fill, no gradient, no shadow.
/// Used sparingly (media, drop zone, inputs); most content groups by space and
/// hairline dividers instead of boxes.
struct CardBackground: ViewModifier {
    var radius: CGFloat = DS.cardRadius
    var padding: CGFloat = DS.inset
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .outline(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    /// 1px outline on pure black — the only surface treatment in the app.
    func outline<S: InsettableShape>(_ shape: S, hovering: Bool = false, active: Bool = false,
                                     tint: Color? = nil) -> some View {
        overlay(shape.strokeBorder(tint ?? (active ? DS.strokeActive : (hovering ? DS.strokeHover : DS.stroke)),
                                   lineWidth: 1))
    }

    func card(radius: CGFloat = DS.cardRadius, padding: CGFloat = DS.inset) -> some View {
        modifier(CardBackground(radius: radius, padding: padding))
    }

    /// The one list-row surface every feed uses: fixed height, no box at rest —
    /// rows are separated by hairlines (`SeparatedList`); an outline appears only
    /// while hovering, as the interactive affordance.
    func rowSurface(hovering: Bool = false, height: CGFloat = DS.rowHeight) -> some View {
        self
            .padding(.horizontal, DS.inset)
            .frame(height: height)
            .outline(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous),
                     tint: hovering ? DS.strokeHover : .clear)
            .contentShape(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
    }
}

/// Scale-on-press feedback (0.96 — the tactile sweet spot, never below 0.95).
struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(DS.press, value: configuration.isPressed)
    }
}

/// Round icon button used in the header shoulders and inline actions.
struct IconButton: View {
    let symbol: String
    var size: CGFloat = DS.control
    var tint: Color = DS.textSecondary
    var active = false
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Icon(symbol, size: size * 0.56, weight: .semibold)
                .id(symbol)
                .transition(.iconSwap)
                .foregroundStyle(active ? DS.accent : (hovering ? DS.textPrimary : tint))
                .frame(width: size, height: size)
                .outline(Circle(), hovering: hovering, tint: active ? DS.accent.opacity(0.6) : nil)
                .contentShape(Circle())
        }
        .buttonStyle(Pressable())
        .help(help)
        .accessibilityLabel(help)
        .onHover { h in withAnimation(DS.hover) { hovering = h } }
    }
}

/// Small pill button ("Clear", "Run check", "Open Docker").
struct PillButton: View {
    let title: String
    var symbol: String? = nil
    var prominent = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Icon(symbol, size: 11.7, weight: .bold) }
                Text(title).font(.ui(10.5, .semibold))
            }
            .foregroundStyle(prominent ? DS.accent : (hovering ? DS.textPrimary : DS.textSecondary))
            .padding(.horizontal, 11)
            .frame(height: 26)
            .outline(Capsule(), hovering: hovering,
                     tint: prominent ? DS.accent.opacity(hovering ? 0.8 : 0.5) : nil)
            .contentShape(Capsule())
        }
        .buttonStyle(Pressable())
        .onHover { h in withAnimation(DS.hover) { hovering = h } }
    }
}

/// Uppercase section label with an optional trailing accessory, aligned to card edges.
struct SectionLabel<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(text.uppercased())
                .font(.label).tracking(0.5)
                .foregroundStyle(DS.textTertiary)
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension SectionLabel where Trailing == EmptyView {
    init(_ text: String) { self.text = text; self.trailing = EmptyView() }
}

/// 1px divider, inset to the content edge so it lines up with row text.
struct Hairline: View {
    var inset: CGFloat = DS.inset
    var vertical = false
    var body: some View {
        if vertical {
            Rectangle().fill(DS.hairline).frame(width: 1)
        } else {
            Rectangle().fill(DS.hairline).frame(height: 1).padding(.horizontal, inset)
        }
    }
}

/// A vertical list with hairlines *between* rows (never above the first or below
/// the last) — the grouped-list look, without a box per row.
struct SeparatedList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                row(item)
                if i < items.count - 1 { Hairline() }
            }
        }
    }
}

/// Segmented control on one outlined track; the selection is an inner outlined
/// capsule that slides between segments.
struct Segmented<T: Hashable>: View {
    let options: [(value: T, title: String)]
    @Binding var selection: T
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { opt in
                let on = opt.value == selection
                Button { withAnimation(DS.content) { selection = opt.value } } label: {
                    Text(opt.title)
                        .font(.mono(10.5, on ? .semibold : .medium))
                        .foregroundStyle(on ? DS.textPrimary : DS.textTertiary)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background {
                            if on {
                                Capsule().strokeBorder(DS.strokeActive, lineWidth: 1)
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(Pressable())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .outline(Capsule())
    }
}

/// A compact metric: big tabular value + unit, small label underneath. Borderless —
/// placed in equal-width columns separated by vertical hairlines.
struct StatTile: View {
    let label: String
    let value: String
    var unit: String = ""
    var tint: Color = DS.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.mono(17, .semibold)).foregroundStyle(tint)
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit).font(.mono(10.5, .medium)).foregroundStyle(DS.textTertiary)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            Text(label.uppercased()).font(.label).tracking(0.4).foregroundStyle(DS.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value) \(unit)")
    }
}

/// Live-status dot with an optional expanding pulse ring.
struct StatusDot: View {
    let color: Color
    var pulsing = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(color).frame(width: 6, height: 6)
            if pulsing && !reduceMotion {
                Circle().stroke(color.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 6, height: 6)
                    .scaleEffect(pulse ? 2.3 : 1)
                    .opacity(pulse ? 0 : 0.8)
            }
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
        .onAppear {
            guard pulsing else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// Contextual icon swap: scale 0.25→1, opacity 0→1, blur 4→0 on a bounce-free spring.
private struct IconSwapModifier: ViewModifier {
    let hidden: Bool
    func body(content: Content) -> some View {
        content.scaleEffect(hidden ? 0.25 : 1).opacity(hidden ? 0 : 1).blur(radius: hidden ? 4 : 0)
    }
}

extension AnyTransition {
    static var iconSwap: AnyTransition {
        .modifier(active: IconSwapModifier(hidden: true), identity: IconSwapModifier(hidden: false))
            .animation(.spring(duration: 0.3, bounce: 0))
    }
}

/// Staggered entrance for panel sections. Content is always mounted (so springs
/// stay interruptible); it reveals with a small per-section delay when expanded,
/// using opacity + a short lift. The shell opens first, then sections settle in.
struct RevealOnExpand: ViewModifier {
    let expanded: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Opacity only — content is laid out at its final position and simply
        // appears as the shape opens around it, so nothing shifts.
        content
            .opacity(expanded ? 1 : 0)
            .animation(
                expanded ? .easeOut(duration: 0.2).delay(reduceMotion ? 0 : 0.08 + Double(index) * 0.04)
                         : .easeOut(duration: 0.08),
                value: expanded
            )
    }
}

extension View {
    func revealOnExpand(_ expanded: Bool, index: Int) -> some View {
        modifier(RevealOnExpand(expanded: expanded, index: index))
    }
}
