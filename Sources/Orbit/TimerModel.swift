import SwiftUI
import AppKit
import UserNotifications

@MainActor
@Observable
final class TimerModel {
    enum Phase: Equatable { case idle, intro(Int), running, paused, finished }

    var mode: Mode = .focus
    var phase: Phase = .idle
    /// Dial value (continuous while dragging so the knob glides).
    var minutes: Double = 25
    var duration: TimeInterval = 25 * 60
    var remaining: TimeInterval = 25 * 60 {
        didSet { if phase != .running || AppActivity.shared.windowVisible { dialRemaining = remaining } }
    }
    /// What the big dial shows. Frozen while the window can't be seen, so a
    /// covered/minimised window costs nothing; resynced when it reappears.
    var dialRemaining: TimeInterval = 25 * 60

    func syncDial() { dialRemaining = remaining }

    var dialSeconds: Int { Int(max(dialRemaining, 0).rounded(.up)) }
    var dialTimeString: String { String(format: "%02d:%02d", dialSeconds / 60, dialSeconds % 60) }
    var dialProgress: Double { duration > 0 ? max(0, min(1, dialRemaining / duration)) : 0 }
    var dialFinal: Bool { phase == .running && dialSeconds <= 10 && dialSeconds > 0 }
    var dialEndsAt: String { Date().addingTimeInterval(dialRemaining).formatted(date: .omitted, time: .shortened) }

    var taskName: String = "" { didSet { UserDefaults.standard.set(taskName, forKey: "taskName") } }
    var soundsOn: Bool = true { didSet { UserDefaults.standard.set(soundsOn, forKey: "soundsOn") } }
    var introOn: Bool = true { didSet { UserDefaults.standard.set(introOn, forKey: "introOn") } }

    var sessionsToday = 0
    var focusSecondsToday: Double = 0

    /// Bumped to fire confetti.
    var celebrate = 0
    /// True while a preset chip hovers over the dial.
    var chipHovering = false
    /// Bumped to shake the dial.
    var shake = 0

    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var introTask: Task<Void, Never>?
    @ObservationIgnored private var advanceTask: Task<Void, Never>?
    @ObservationIgnored private var lastSecond = -1
    /// Exact time left. `remaining` (observed by the UI) is only refreshed when the
    /// displayed second changes, so views redraw once per second, not per tick.
    @ObservationIgnored private var preciseRemaining: TimeInterval = 0
    @ObservationIgnored private var askedNotifications = false

    init() {
        let d = UserDefaults.standard
        taskName = d.string(forKey: "taskName") ?? ""
        soundsOn = d.object(forKey: "soundsOn") as? Bool ?? true
        introOn = d.object(forKey: "introOn") as? Bool ?? true
        loadStats()
        loadMinutes()
    }

    // MARK: Derived

    var displaySeconds: Int { Int(max(remaining, 0).rounded(.up)) }

    var timeString: String {
        let s = displaySeconds
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    var progress: Double { duration > 0 ? max(0, min(1, remaining / duration)) : 0 }
    var isRunning: Bool { phase == .running }
    var isActive: Bool { phase == .running || phase == .paused }
    var canEdit: Bool { phase == .idle || phase == .finished }
    var isFinalCountdown: Bool { phase == .running && displaySeconds <= 10 && displaySeconds > 0 }
    var isIntro: Bool { if case .intro = phase { return true } else { return false } }

    var endsAt: String {
        Date().addingTimeInterval(remaining).formatted(date: .omitted, time: .shortened)
    }

    var cyclePosition: Int { sessionsToday == 0 ? 0 : ((sessionsToday - 1) % 4) + 1 }

    var focusedString: String {
        let m = Int(focusSecondsToday / 60)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    // MARK: Setting time

    func setMinutes(_ m: Double, save: Bool = true) {
        minutes = min(max(m, 1), 120)
        duration = minutes.rounded() * 60
        remaining = duration
        if phase == .finished { phase = .idle }
        if save { UserDefaults.standard.set(minutes.rounded(), forKey: "minutes.\(mode.rawValue)") }
    }

    private func loadMinutes() {
        let saved = UserDefaults.standard.double(forKey: "minutes.\(mode.rawValue)")
        setMinutes(saved > 0 ? saved : Double(mode.defaultMinutes), save: false)
    }

    func select(_ m: Mode) {
        cancelAll()
        mode = m
        phase = .idle
        loadMinutes()
    }

    // MARK: Controls

    func primaryAction() {
        switch phase {
        case .idle, .finished: start()
        case .intro: skipIntro()
        case .running: pause()
        case .paused: resume()
        }
    }

    func start() {
        advanceTask?.cancel()
        requestNotifications()
        if remaining <= 0 { remaining = duration }
        if introOn { runIntro() } else { beginRunning() }
    }

    private func runIntro() {
        introTask?.cancel()
        introTask = Task { [weak self] in
            for n in [3, 2, 1] {
                guard let self, !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { self.phase = .intro(n) }
                self.play("Tink", volume: 0.5)
                Haptics.tick()
                try? await Task.sleep(for: .milliseconds(850))
            }
            guard let self, !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { self.phase = .intro(0) }
            self.play("Hero", volume: 0.5)
            Haptics.bump()
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self.beginRunning()
        }
    }

    func skipIntro() {
        introTask?.cancel()
        beginRunning()
    }

    private func beginRunning() {
        endDate = Date().addingTimeInterval(remaining)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { phase = .running }
        lastSecond = displaySeconds
        startTicker()
    }

    func pause() {
        tick()
        remaining = preciseRemaining
        ticker?.invalidate()
        withAnimation(.snappy) { phase = .paused }
    }

    func resume() { beginRunning() }

    func reset() {
        cancelAll()
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
            phase = .idle
            remaining = duration
        }
    }

    func skip() {
        cancelAll()
        advanceMode()
    }

    private func cancelAll() {
        introTask?.cancel()
        advanceTask?.cancel()
        ticker?.invalidate()
    }

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.05   // lets macOS coalesce wake-ups
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        guard phase == .running, let end = endDate else { return }
        preciseRemaining = max(0, end.timeIntervalSinceNow)
        let s = Int(preciseRemaining.rounded(.up))
        if s != lastSecond {
            lastSecond = s
            remaining = preciseRemaining
            if s <= 3 && s > 0 { play("Tink", volume: 0.45) }
        }
        if preciseRemaining <= 0 {
            remaining = 0
            finish()
        }
    }

    private func finish() {
        ticker?.invalidate()
        let finishedMode = mode
        withAnimation(.spring) { phase = .finished }
        celebrate += 1
        play("Glass", volume: 0.8)
        Haptics.bump()
        if finishedMode == .focus {
            sessionsToday += 1
            focusSecondsToday += duration
            saveStats()
        }
        notify(finished: finishedMode)
        advanceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard let self, !Task.isCancelled, self.phase == .finished, self.mode == finishedMode else { return }
            self.advanceMode()
        }
    }

    private func advanceMode() {
        let next: Mode
        if mode == .focus {
            next = (sessionsToday > 0 && sessionsToday % 4 == 0) ? .longBreak : .shortBreak
        } else {
            next = .focus
        }
        withAnimation(.smooth(duration: 0.8)) { select(next) }
    }

    func play(_ name: String, volume: Float = 0.6) {
        if soundsOn { Sounds.play(name, volume: volume) }
    }

    // MARK: Stats

    private static var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func loadStats() {
        let d = UserDefaults.standard
        if d.string(forKey: "statsDay") == Self.todayKey {
            sessionsToday = d.integer(forKey: "sessionsToday")
            focusSecondsToday = d.double(forKey: "focusSecondsToday")
        } else {
            sessionsToday = 0
            focusSecondsToday = 0
        }
    }

    private func saveStats() {
        let d = UserDefaults.standard
        if d.string(forKey: "statsDay") != Self.todayKey {
            d.set(Self.todayKey, forKey: "statsDay")
        }
        d.set(sessionsToday, forKey: "sessionsToday")
        d.set(focusSecondsToday, forKey: "focusSecondsToday")
    }

    // MARK: Notifications

    private func requestNotifications() {
        guard !askedNotifications, Bundle.main.bundleIdentifier != nil else { return }
        askedNotifications = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(finished: Mode) {
        guard Bundle.main.bundleIdentifier != nil, !NSApp.isActive else { return }
        let c = UNMutableNotificationContent()
        if finished == .focus {
            c.title = "Focus session complete"
            c.body = taskName.isEmpty ? "Great work. Time for a breather." : "Great work on \(taskName). Time for a breather."
        } else {
            c.title = "Break's over"
            c.body = "Ready to lock back in?"
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}
