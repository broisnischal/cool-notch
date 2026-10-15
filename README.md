# Cool Notch

A native macOS menu-bar app that turns the MacBook notch into a living surface.
The notch sits invisible until you move the cursor onto it — then it **grows
fluidly into a panel** of widgets, and retracts when you leave.

Built with SwiftUI + AppKit, no Xcode required — it compiles with the Swift
toolchain in Command Line Tools and assembles into a normal `.app`.

## Features

- **Invisible when idle** — the surface is exactly the notch and pure black (no
  border, no glow), so it disappears into the hardware.
- **Notch-only trigger** — it opens *only* when the cursor is over the notch, not a
  wider strip.
- **Fluid morph** — one black surface whose width, height and corner radius spring
  together across three sizes (notch → notification pill → panel), so it appears to
  physically stretch. Interruptible and reduced-motion aware.
- **Live activities & HUD** (collapsed, split around the camera, iOS-style):
  - **Now Playing** — album art + an animated equalizer while media plays.
  - **Volume HUD** — a level bar when you change volume (optionally suppresses the
    macOS popup, see Settings).
  - **Typing** — pulsing dots while Claude is streaming a reply.
  - **Notifications** — a pill (Claude active, container start/stop, plug/unplug,
    Claude's own hook events) that **shakes the notch** when it lands, then dismisses.
- **Now Playing (real)** — system-wide metadata + artwork + live scrubber + transport
  for any app, via the bundled `mediaremote-adapter` (works on macOS 15.4+/26 where
  MediaRemote reads are otherwise blocked).
- **In-panel navigation** — tapping a row pushes a detail page that slides in
  from the trailing edge; a back button and refresh live in the header. The panel
  stays open while you're on a detail page.
- **Feeds** (tab bar with a sliding selection pill):
  - **Home** — hero clock, battery ring, media transport, file shelf.
  - **Claude** — an *Ask Claude* box (chat with Claude via `claude -p` right in the
    notch) plus recent sessions with a pulsing "live" badge. Tap a session to read
    its transcript and **send it messages** (resumes the session with `claude
    --resume -p`), or *Resume in Terminal.app*.
  - **Docker** — running containers; tap one for a **live logs** page. Graceful
    "not running / not installed" states with an *Open Docker* shortcut.
  - **Network** — live ping (latency sparkline, jitter, packet loss) against
    1.1.1.1 / 8.8.8.8 / your router, live throughput and packets/s, a built-in
    speed test (`networkQuality`), and link details (IPs, gateway, DNS, Wi-Fi signal).
  - **Health** — one-tap device check: internet, DNS, Wi-Fi, CPU, memory pressure,
    swap, disk space, SMART, battery health, thermals, uptime, recent crashes, and
    SIP/FileVault.
  - **Clipboard** — clipboard history (persisted); tap any entry to copy it back.
  - **Dev** — a Pomodoro focus timer, git/PR status for the active Claude project,
    and listening TCP ports.
  - **Mirror** — a live front-camera mirror.
  - **Home** also shows your **next calendar event** with a live countdown.

## Settings, shortcuts, persistence

- **Preferences** (menu-bar icon ▸ Settings…, or ⌘,): accent color, which tabs are
  enabled, launch-at-login, now-playing live activity toggle, and **Hide macOS
  volume/brightness popup**.
- **Solid menu bar** (Settings ▸ Menu bar): the Boring Old Menu Bar technique —
  renders a copy of your wallpaper with a solid strip under the menu bar (Black hides
  the notch; also dark/light grey, white, Catalina dark/light, or custom light+dark
  colours), optional divider, ±1px height, rounded screen corners. The real menu bar
  keeps working on top; turning it off restores your wallpaper. Needs macOS
  *Reduce transparency* off.
- **⌘⌃N** toggles the notch open/closed from anywhere.
- Clipboard history, shelf, last tab, and all preferences **persist across restarts**.
- Picks the notched display automatically on multi-monitor setups.
- **Widgets** — hero clock with date, battery ring with time-to-full/empty,
  and media transport (play/pause · next · previous) that drives whatever app owns
  Now Playing via system media keys.
- **File Shelf** — drag files onto the panel to park them, drag them back out into
  any app or Finder later. No copies, no permissions — it just remembers URLs.
- **Pin** — click the cap (or the pin button) to keep the panel open.

## Design notes

Motion values are translated from Apple's *Designing Fluid Interfaces* damping/
response model into SwiftUI springs: the drop carries a touch of momentum
(`dampingFraction 0.80`), the retract is critically damped (`0.92`). Press feedback
is `scale(0.96)`; sections reveal with a ~45ms stagger; tabular rounded numerals
keep the clock from jittering; concentric radii (panel 26 → card 16 → chip 11);
translucent material with a bright top hairline.

## Build & run

```bash
./build_app.sh            # release build → ".build/Cool Notch.app"
open ".build/Cool Notch.app"
```

Quit from the menu-bar icon (▸ Quit Cool Notch), or `pkill -f CoolNotch`.

## Claude notifications → the notch

Claude Code's own notifications can surface as notch pills. Cool Notch watches
`~/.claude/coolnotch/notifications.jsonl`; wire a Notification hook to append to it.
In `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [
      { "hooks": [ { "type": "command",
        "command": "mkdir -p ~/.claude/coolnotch && jq -c '{title: \"Claude\", message: .message}' >> ~/.claude/coolnotch/notifications.jsonl" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command",
        "command": "mkdir -p ~/.claude/coolnotch && echo '{\"title\":\"Claude\",\"message\":\"Turn finished\"}' >> ~/.claude/coolnotch/notifications.jsonl" } ] }
    ]
  }
}
```

## Permissions

- **Battery / clock / shelf / terminal / clipboard / ports** — none required.
- **Now Playing** — none (the adapter uses the entitled `com.apple.*` perl binary).
- **Camera mirror** — Camera permission (prompted on first open).
- **Calendar** — Calendars access (prompted on first open).
- **Hide system HUD** — boots out `OSDUIHelper` via `launchctl` (no sudo); best-effort
  and reversible from the same toggle.

## Layout

```
Sources/CoolNotch/
  main.swift            NSApplication entry
  AppDelegate.swift     accessory app + status-bar menu
  NotchWindow.swift     borderless panel, click-through hit-testing, hover tracking
  NotchState.swift      shared observable state (expand/pin/shelf)
  Geometry.swift        notch detection + surface sizing
  DesignSystem.swift    springs, colors, radii, type
  Services/             BatteryService (IOKit), MediaController (CGEvent)
  Views/                RootView, CapView, PanelView, NotchShape, Widgets, ShelfView
```

## Roadmap

- Live Now-Playing metadata + artwork (currently transport-only)
- Weather / calendar widgets
- Multi-display support and per-screen placement
- Preferences window (which widgets, order, accent color)
