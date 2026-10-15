import SwiftUI

/// Home hero — borderless and mirrored about the centre: a big clock with the
/// date (or next event) on the leading side; battery status and ring on the
/// trailing side, right-aligned so both halves hug the panel edges.
struct HomeHero: View {
    let info: BatteryInfo
    var event: CalEvent?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(ctx.date, format: .dateTime.hour().minute())
                            .font(.mono(34, .semibold))
                            .tracking(-1)
                            .foregroundStyle(DS.textPrimary)
                            .contentTransition(.numericText())
                        Text(ctx.date, format: .dateTime.second())
                            .font(.mono(11, .medium))
                            .foregroundStyle(DS.textTertiary)
                    }
                    subtitle(now: ctx.date)
                }
                Spacer(minLength: 8)
                battery
            }
        }
    }

    @ViewBuilder private func subtitle(now: Date) -> some View {
        if let event, event.start > now, event.start.timeIntervalSince(now) < 12 * 3600 {
            HStack(spacing: 5) {
                Circle().fill(DS.accent).frame(width: 5, height: 5)
                Text(event.title).foregroundStyle(DS.textSecondary).lineLimit(1)
                Text(Self.countdown(to: event.start, now: now)).foregroundStyle(DS.accent).fixedSize()
            }
            .font(.caption)
        } else {
            Text(now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.caption).foregroundStyle(DS.textSecondary)
        }
    }

    private var battery: some View {
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(info.isCharging ? "Charging" : (info.isPluggedIn ? "Plugged in" : "Battery"))
                    .font(.title).foregroundStyle(DS.textPrimary)
                Text(status).font(.caption).foregroundStyle(DS.textSecondary).lineLimit(1)
            }
            ZStack {
                Circle().stroke(DS.hairline, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(info.level) / 100)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(DS.content, value: info.level)
                Text("\(info.level)")
                    .font(.mono(13, .bold))
                    .foregroundStyle(DS.textPrimary)
                    .contentTransition(.numericText())
            }
            .frame(width: 44, height: 44)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery \(info.level) percent, \(status)")
    }

    private var ringColor: Color {
        if info.isCharging { return DS.good }
        if info.level <= 20 { return DS.danger }
        return DS.accent
    }

    private var status: String {
        if !info.hasBattery { return "AC power" }
        if info.isCharging {
            if let m = info.timeToFull { return "\(m / 60)h \(m % 60)m to full" }
            return "\(info.level)%"
        }
        if let m = info.timeToEmpty { return "\(m / 60)h \(m % 60)m left" }
        return "\(info.level)%"
    }

    private static func countdown(to date: Date, now: Date) -> String {
        let s = Int(date.timeIntervalSince(now))
        if s < 3600 { return "in \(max(1, s / 60))m" }
        return "in \(s / 3600)h \((s % 3600) / 60)m"
    }
}

/// Now Playing — artwork, title/artist, a live scrubber, and real transport.
struct MediaCard: View {
    @ObservedObject var np: NowPlayingService

    var body: some View {
        HStack(spacing: 10) {
            artwork
            if let info = np.info {
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title.trimmingCharacters(in: CharacterSet(charactersIn: " |·-")))
                        .font(.title)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1).truncationMode(.tail)
                    Text(info.artist.isEmpty ? info.album : info.artist)
                        .font(.caption)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                    scrubber(info)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nothing playing").font(.title).foregroundStyle(DS.textSecondary)
                    Text("Play something to control it here").font(.caption).foregroundStyle(DS.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            controls
        }
        .card()
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.clear)
            if let art = np.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                Icon("music.note", size: 18.2, weight: .medium)
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        // Subtle image outline (pure white at low opacity), per better-ui.
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(.white.opacity(0.10), lineWidth: 1))
    }

    private func scrubber(_ info: NowPlaying) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let p = info.progress(at: ctx.date)
            let now = info.elapsed(at: ctx.date)
            VStack(spacing: 2) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule().fill(DS.accent).frame(width: max(0, geo.size.width * p))
                    }
                }
                .frame(height: 3)
                HStack {
                    Text(Self.time(now)).font(.mono(9, .medium)).foregroundStyle(DS.textTertiary)
                    Spacer()
                    Text(Self.time(info.duration)).font(.mono(9, .medium)).foregroundStyle(DS.textTertiary)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            MediaButton(symbol: "backward.fill", size: 10, label: "Previous") { np.previous() }
            MediaButton(symbol: (np.info?.isPlaying ?? false) ? "pause.fill" : "play.fill",
                        size: 12, prominent: true,
                        label: (np.info?.isPlaying ?? false) ? "Pause" : "Play") { np.toggle() }
            MediaButton(symbol: "forward.fill", size: 10, label: "Next") { np.next() }
        }
    }

    private static func time(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let t = Int(s); return String(format: "%d:%02d", t / 60, t % 60)
    }
}

struct MediaButton: View {
    let symbol: String
    var size: CGFloat = 13
    var prominent: Bool = false
    var label: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Icon(symbol, size: size * 1.3, weight: .semibold)
                .id(symbol)                       // swap animates via iconSwap
                .transition(.iconSwap)
                .foregroundStyle(prominent ? DS.accent : DS.textPrimary)
                .frame(width: 32, height: 32)
                .outline(Circle(), hovering: hovering,
                         tint: prominent ? DS.accent.opacity(hovering ? 0.8 : 0.5) : nil)
                .contentShape(Circle())
        }
        .buttonStyle(Pressable())
        .accessibilityLabel(label)
        .onHover { h in
            withAnimation(DS.hover) { hovering = h }
        }
    }
}
