import SwiftUI

/// Settings window content. Dark to match the notch aesthetic.
struct PreferencesView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject private var solidBar = SolidMenuBar.shared
    @State private var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                section("Accent") {
                    HStack(spacing: 12) {
                        ForEach(AccentPreset.allCases) { preset in
                            Button { settings.accent = preset } label: {
                                Circle()
                                    .fill(preset.color)
                                    .frame(width: 26, height: 26)
                                    .overlay(Circle().strokeBorder(.white,
                                        lineWidth: settings.accent == preset ? 2.5 : 0))
                                    .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                }

                section("Tabs") {
                    VStack(spacing: 2) {
                        ForEach(NotchTab.allCases) { tab in
                            Toggle(isOn: Binding(
                                get: { settings.isEnabled(tab) },
                                set: { _ in settings.toggle(tab) }
                            )) {
                                Label(tab.title, systemImage: tab.icon)
                                    .font(.ui(13, .medium))
                            }
                            .toggleStyle(.switch)
                            .tint(DS.accent)
                        }
                    }
                }

                section("General") {
                    VStack(spacing: 2) {
                        Toggle(isOn: $settings.launchAtLogin) {
                            Text("Launch at login").font(.ui(13, .medium))
                        }.toggleStyle(.switch).tint(DS.accent)
                        Toggle(isOn: $settings.mediaLiveActivity) {
                            Text("Now-playing live activity").font(.ui(13, .medium))
                        }.toggleStyle(.switch).tint(DS.accent)
                        Toggle(isOn: $settings.hideSystemHUD) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Hide macOS volume/brightness popup").font(.ui(13, .medium))
                                Text("Shows volume in the notch instead").font(.ui(10, .regular))
                                    .foregroundStyle(DS.textTertiary)
                            }
                        }.toggleStyle(.switch).tint(DS.accent)
                        Toggle(isOn: $settings.openSound) {
                            Text("Sound when the notch opens").font(.ui(13, .medium))
                        }.toggleStyle(.switch).tint(DS.accent)
                        Toggle(isOn: $settings.agentAlerts) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Agent chime").font(.ui(13, .medium))
                                Text("Soft sound + pill when a Claude session finishes")
                                    .font(.ui(10, .regular)).foregroundStyle(DS.textTertiary)
                            }
                        }.toggleStyle(.switch).tint(DS.accent)
                        Toggle(isOn: $settings.aiEffect) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Background effect while Claude works").font(.ui(13, .medium))
                                Text("Shown in the notch and behind chat").font(.ui(10, .regular))
                                    .foregroundStyle(DS.textTertiary)
                            }
                        }.toggleStyle(.switch).tint(DS.accent)
                        if settings.aiEffect {
                            Picker("", selection: $settings.aiEffectStyle) {
                                ForEach(AIEffectStyle.allCases) { style in
                                    Text(style.title).tag(style)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .padding(.top, 2)
                        }
                    }
                }

                section("Menu bar") {
                    solidMenuBarControls
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Pixel pets").font(.ui(13, .medium))
                            Text("Cat, Claude & robot stroll along the menu bar")
                                .font(.ui(10, .regular)).foregroundStyle(DS.textTertiary)
                        }
                        Spacer()
                        Picker("", selection: $settings.menuBarPets) {
                            ForEach(MenuBarPetsMode.allCases) { m in
                                Text(m.title).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    .padding(.top, 4)

                }

                section("Shortcut") {
                    HStack {
                        Text("Toggle notch").font(.ui(13, .medium)).foregroundStyle(DS.textSecondary)
                        Spacer()
                        Text("⌘⌃N").font(.mono(13, .semibold))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 7).fill(DS.cardFill))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .frame(width: 420, height: 620)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)) { _ in
            reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }
        .background(Color(white: 0.09))
        .environment(\.colorScheme, .dark)
        .foregroundStyle(DS.textPrimary)
    }

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.06))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .font(.system(size: 20)).foregroundStyle(DS.accent)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("Cool Notch").font(.ui(18, .bold))
                Text("v1.0 · the developer's notch")
                    .font(.ui(11, .medium)).foregroundStyle(DS.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: Solid menu bar

    @ViewBuilder private var solidMenuBarControls: some View {
        Toggle(isOn: $settings.solidBarEnabled) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Solid menu bar").font(.ui(13, .medium))
                Text("Paints a solid strip into your wallpaper under the menu bar. Black hides the notch.")
                    .font(.ui(10, .regular)).foregroundStyle(DS.textTertiary)
            }
        }
        .toggleStyle(.switch).tint(DS.accent)

        if settings.solidBarEnabled {
            if reduceTransparency {
                HStack(alignment: .top, spacing: 8) {
                    Icon("exclamationmark.triangle", size: 14).foregroundStyle(DS.amber)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reduce transparency is on, so macOS draws its own grey bar over the strip. Turn it off to see this colour.")
                            .font(.ui(11, .regular)).foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        PillButton(title: "Open Display Settings", prominent: true) {
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Display")!)
                        }
                    }
                }
                .padding(10)
                .outline(RoundedRectangle(cornerRadius: 10, style: .continuous), tint: DS.amber.opacity(0.4))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                ForEach(SolidBarStyle.allCases) { style in
                    let selected = settings.solidBarStyle == style
                    Button { settings.solidBarStyle = style } label: {
                        VStack(spacing: 4) {
                            swatch(style)
                                .frame(height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(selected ? DS.accent : DS.hairline, lineWidth: selected ? 2 : 1))
                            Text(style.title).font(.ui(10, .medium))
                                .foregroundStyle(selected ? DS.textPrimary : DS.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if settings.solidBarStyle == .custom {
                HStack {
                    ColorPicker("Light mode", selection: $settings.solidBarCustomLight, supportsOpacity: false)
                    Spacer()
                    ColorPicker("Dark mode", selection: $settings.solidBarCustomDark, supportsOpacity: false)
                }
                .font(.ui(12, .medium))
            }

            settingRow("Divider") {
                Picker("", selection: $settings.solidBarDivider) {
                    ForEach(SolidBarDivider.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            settingRow("Height") {
                Picker("", selection: $settings.solidBarHeightAdjust) {
                    Text("−1 px").tag(-1); Text("Exact").tag(0); Text("+1 px").tag(1)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            settingRow("Screen corners") {
                HStack(spacing: 8) {
                    Slider(value: Binding(get: { Double(settings.solidBarCornerRadius) },
                                          set: { settings.solidBarCornerRadius = Int($0.rounded()) }),
                           in: 0...10, step: 1)
                        .frame(width: 140).tint(DS.accent)
                    Text(settings.solidBarCornerRadius == 0 ? "Square" : "\(settings.solidBarCornerRadius) pt")
                        .font(.mono(11, .medium)).foregroundStyle(DS.textSecondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }
            if !solidBar.status.isEmpty && solidBar.status != "On" {
                Text(solidBar.status).font(.ui(10.5, .regular)).foregroundStyle(DS.amber)
            }
        }
    }

    @ViewBuilder private func swatch(_ style: SolidBarStyle) -> some View {
        if style == .custom {
            HStack(spacing: 0) {
                settings.solidBarCustomLight
                settings.solidBarCustomDark
            }
        } else {
            let c = style.rgb(dark: false, light: RGB(0, 0, 0), dark: RGB(0, 0, 0))
            c.color
        }
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Text(title).font(.ui(12, .medium)).foregroundStyle(DS.textSecondary)
            Spacer()
            content()
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.ui(10, .bold)).tracking(0.6)
                .foregroundStyle(DS.textTertiary)
            content()
        }
    }
}
