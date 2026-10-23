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
        /// A break is due but waits for a pause in typing.
        case waitingForTyping
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
    private let headsUp = HeadsUp()
    private var timer: Timer?
    /// When the current break became due, while it waits for a pause in typing.
    private var dueSince: ContinuousClock.Instant?
    /// A monotonic clock (unlike Date, unaffected by clock changes) that keeps
    /// counting while the Mac sleeps, so a sleep shows up as a long gap.
    private var lastTick = ContinuousClock.now
    private var screenLocked = false

    private var workDuration: TimeInterval { TimeInterval(Settings.workSeconds) }
    private var breakDuration: TimeInterval { TimeInterval(Settings.breakSeconds) }

    init() {
        remaining = TimeInterval(Settings.workSeconds)
        overlay.onSkip = { [weak self] in self?.skipBreak() }
        overlay.onPostpone = { [weak self] in self?.postponeBreak() }
        headsUp.onStartNow = { [weak self] in self?.takeBreakNow() }
        headsUp.onPostpone = { [weak self] in self?.postponeBreak() }
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
        changed()
    }

    // MARK: Actions

    func takeBreakNow() {
        startBreak()
    }

    func skipBreak() {
        log.notice("break skipped")
        endBreak(nextIn: workDuration)
    }

    func postponeBreak() {
        log.notice("break postponed")
        endBreak(nextIn: TimeInterval(Settings.postponeSeconds))
    }

    func pause(for duration: TimeInterval?) {
        overlay.hide()
        state = .paused(until: duration.map { Date().addingTimeInterval($0) })
        changed()
    }

    func resume() {
        state = .working
        remaining = workDuration
        changed()
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
        let now = ContinuousClock.now
        let elapsed = (now - lastTick).seconds
        lastTick = now

        switch state {
        case .paused(let until):
            if let until, Date() >= until { resume() }
            return

        case .onBreak:
            remaining -= elapsed
            if remaining <= 0 {
                NSSound(named: "Glass")?.play()
                endBreak(nextIn: workDuration)
                return
            }

        case .working, .waiting, .waitingForTyping, .away:
            if isAway(gap: elapsed) {
                state = .away
                remaining = workDuration
            } else {
                remaining = max(0, remaining - elapsed)
                if remaining > 0 {
                    state = .working
                    dueSince = nil
                } else if let reason = busyReason() {
                    state = .waiting(reason: reason)
                } else if case .waiting = state, Settings.graceSeconds > 0 {
                    // The call or meeting just ended; give a moment before the break.
                    state = .working
                    remaining = TimeInterval(Settings.graceSeconds)
                } else if isTyping(now: now) {
                    state = .waitingForTyping
                } else {
                    startBreak()
                    return
                }
            }
        }
        changed()
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

    /// A due break waits for a pause in typing, but no longer than
    /// `maxTypingWaitSeconds` after it became due.
    private func isTyping(now: ContinuousClock.Instant) -> Bool {
        if dueSince == nil { dueSince = now }
        let waited = (now - (dueSince ?? now)).seconds
        return Activity.secondsSinceKeyPress() < Settings.typingPauseSeconds
            && waited < TimeInterval(Settings.maxTypingWaitSeconds)
    }

    /// Shows the heads-up in the last seconds before a break and while a due
    /// break waits for a pause in typing.
    private func updateHeadsUp() {
        let warning = TimeInterval(Settings.headsUpSeconds)
        let show: Bool
        switch state {
        case .waitingForTyping:
            show = warning > 0
        case .working:
            // No warning for a break that a busy check is about to hold. Once
            // shown, keep it up rather than re-checking every second.
            show = warning > 0 && remaining <= warning && (headsUp.isShown || busyReason() == nil)
        default:
            show = false
        }
        if show { headsUp.show(scheduler: self) } else { headsUp.hide() }
    }

    private func changed() {
        updateHeadsUp()
        onUpdate?()
    }

    private func startBreak() {
        dueSince = nil
        state = .onBreak
        remaining = breakDuration
        overlay.show(scheduler: self)
        changed()
    }

    private func endBreak(nextIn interval: TimeInterval) {
        dueSince = nil
        overlay.hide()
        state = .working
        remaining = interval
        changed()
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

private extension Duration {
    var seconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
