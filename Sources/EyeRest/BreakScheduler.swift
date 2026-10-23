import AppKit
import os

private let log = Logger(subsystem: "io.github.fengzdadi.EyeRest", category: "scheduler")

/// Counts down work time, starts breaks, and decides when the user is away or
/// busy (on a call, presenting, in a meeting).
@MainActor
final class BreakScheduler: ObservableObject {
    enum State: Equatable {
        case working
        /// A break is due but held because the user is busy.
        case waiting(reason: String)
        /// No recent input or the screen is locked; the work timer stays reset.
        case away
        case onBreak
        /// `until == nil` means paused until the user resumes.
        case paused(until: Date?)
    }

    @Published private(set) var state: State = .working {
        didSet {
            if state != oldValue { log.notice("state: \(String(describing: self.state), privacy: .public)") }
        }
    }
    /// Seconds until the next break, or until the current break ends.
    @Published private(set) var remaining: TimeInterval

    var onUpdate: (() -> Void)?

    let calendar = MeetingCalendar()
    private let overlay = BreakOverlay()
    private var timer: Timer?
    private var lastTick = Date()
    private var screenLocked = false

    private var workDuration: TimeInterval { TimeInterval(Settings.workSeconds) }
    private var breakDuration: TimeInterval { TimeInterval(Settings.breakSeconds) }

    init() {
        remaining = TimeInterval(Settings.workSeconds)
        overlay.onSkip = { [weak self] in self?.skipBreak() }
        overlay.onPostpone = { [weak self] in self?.postponeBreak() }
    }

    func start() {
        observeScreenLock()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Ticks measure real elapsed time, so letting macOS shift them a little to
        // batch wakeups with other work costs no accuracy.
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)  // keep ticking while the menu is open
        self.timer = timer
        onUpdate?()
    }

    // MARK: Actions

    func takeBreakNow() {
        startBreak()
    }

    func skipBreak() {
        endBreak(nextIn: workDuration)
    }

    func postponeBreak() {
        endBreak(nextIn: TimeInterval(Settings.postponeSeconds))
    }

    func pause(for duration: TimeInterval?) {
        overlay.hide()
        state = .paused(until: duration.map { Date().addingTimeInterval($0) })
        onUpdate?()
    }

    func resume() {
        state = .working
        remaining = workDuration
        onUpdate?()
    }

    /// Starts a fresh work interval, e.g. after the interval setting changes.
    func restartWorkTimer() {
        switch state {
        case .onBreak, .paused: return
        default: resume()
        }
    }

    // MARK: Timer

    private func tick() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTick)
        lastTick = now

        switch state {
        case .paused(let until):
            if let until, now >= until { resume() }
            return

        case .onBreak:
            remaining -= elapsed
            if remaining <= 0 {
                NSSound(named: "Glass")?.play()
                endBreak(nextIn: workDuration)
                return
            }

        case .working, .waiting, .away:
            if isAway(gap: elapsed) {
                state = .away
                remaining = workDuration
            } else {
                remaining = max(0, remaining - elapsed)
                if remaining > 0 {
                    state = .working
                } else if let reason = busyReason() {
                    state = .waiting(reason: reason)
                } else if case .waiting = state, Settings.graceSeconds > 0 {
                    // The call or meeting just ended; give a moment before the break.
                    state = .working
                    remaining = TimeInterval(Settings.graceSeconds)
                } else {
                    startBreak()
                    return
                }
            }
        }
        onUpdate?()
    }

    /// The user is taking a natural break if the screen is locked, the Mac just
    /// woke from sleep (a long gap between ticks), or there has been no input for
    /// a while and no video is keeping the display awake.
    private func isAway(gap: TimeInterval) -> Bool {
        if screenLocked || gap > breakDuration { return true }
        let idleLimit = max(TimeInterval(Settings.idleResetSeconds), breakDuration)
        return Activity.idleSeconds() >= idleLimit && !Activity.isDisplayHeldAwake()
    }

    /// Why a due break should wait, or nil if it can start now.
    private func busyReason() -> String? {
        if Settings.holdDuringCalls, let reason = Activity.callInProgress() {
            return reason
        }
        if Settings.holdDuringSlideshows, let app = Activity.slideshowApp() {
            return "\(app) slideshow"
        }
        if Settings.holdDuringMeetings, let title = calendar.currentMeeting() {
            let short = title.count > 30 ? title.prefix(29) + "…" : Substring(title)
            return "meeting: \(short)"
        }
        return nil
    }

    private func startBreak() {
        state = .onBreak
        remaining = breakDuration
        overlay.show(scheduler: self)
        onUpdate?()
    }

    private func endBreak(nextIn interval: TimeInterval) {
        overlay.hide()
        state = .working
        remaining = interval
        onUpdate?()
    }

    private func observeScreenLock() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLocked = true }
        }
        center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLocked = false }
        }
    }
}
