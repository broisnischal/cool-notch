import SwiftUI

/// A focus timer (25 min work / 5 min break). App-level singleton so it keeps
/// running as you switch tabs.
@MainActor
final class PomodoroTimer: ObservableObject {
    static let shared = PomodoroTimer()

    @Published private(set) var remaining: Int = 25 * 60
    @Published private(set) var running = false
    @Published private(set) var isBreak = false

    private var timer: Timer?
    private let workLen = 25 * 60
    private let breakLen = 5 * 60

    var total: Int { isBreak ? breakLen : workLen }
    var progress: Double { 1 - Double(remaining) / Double(max(1, total)) }
    var label: String { String(format: "%d:%02d", remaining / 60, remaining % 60) }

    func toggle() { running ? pause() : start() }

    func start() {
        guard !running else { return }
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func pause() {
        running = false
        timer?.invalidate(); timer = nil
    }

    func reset() {
        pause(); isBreak = false; remaining = workLen
    }

    private func tick() {
        guard remaining > 0 else { switchPhase(); return }
        remaining -= 1
    }

    private func switchPhase() {
        isBreak.toggle()
        remaining = total
    }
}
