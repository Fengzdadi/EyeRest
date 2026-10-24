import Foundation

/// What the break timer needs to know about the user and the Mac on each tick.
@MainActor
public protocol ActivityProbe {
    /// Seconds since any keyboard, mouse or trackpad input.
    func idleSeconds() -> TimeInterval
    /// Seconds since the last key press.
    func secondsSinceKeyPress() -> TimeInterval
    /// Some app (usually a video player) is keeping the display awake.
    func isDisplayHeldAwake() -> Bool
    /// A call is in progress: the camera or microphone is in use.
    func isInCall() -> Bool
    var isScreenLocked: Bool { get }
    /// Why a due break should wait (a call, a slideshow, a meeting), or nil.
    func busyReason() -> String?
}

/// The break timer's state machine. It has no UI and reads the outside world
/// only through an `ActivityProbe`, so tests can drive it with a fake probe and
/// made-up elapsed times.
@MainActor
public struct BreakTimer {
    public enum State: Equatable, Sendable {
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

    /// Durations, in seconds.
    public struct Config: Equatable, Sendable {
        /// Time between breaks.
        public var workSeconds: TimeInterval = 20 * 60
        public var breakSeconds: TimeInterval = 20
        /// How far "Postpone" pushes a break back.
        public var postponeSeconds: TimeInterval = 5 * 60
        /// No input for this long counts as a natural break.
        public var idleResetSeconds: TimeInterval = 2 * 60
        /// After a held break is released, wait this long before starting it.
        public var graceSeconds: TimeInterval = 60
        /// Show the heads-up this long before a break; 0 turns it off.
        public var headsUpSeconds: TimeInterval = 10
        /// A due break waits until there's been no key press for this long...
        public var typingPauseSeconds: TimeInterval = 2
        /// ...but starts anyway once it has waited this long.
        public var maxTypingWaitSeconds: TimeInterval = 30
        /// Every this many breaks, the break is a long one; 0 turns long breaks off.
        public var longBreakEvery = 3
        public var longBreakSeconds: TimeInterval = 5 * 60

        public init() {}
    }

    /// Something that happened, for the activity log and the end-of-break sound.
    public enum Event: Equatable, Sendable {
        case breakStarted(long: Bool)
        /// The break ran its full length.
        case breakFinished(long: Bool)
        case breakSkipped(long: Bool)
        /// From the heads-up or the break screen.
        case breakPostponed
        /// The Mac slept through the break.
        case breakInterrupted(long: Bool)
        case paused(until: Date?)
        case resumed
    }

    /// Whether the user is at the screen, worked out once a tick for both the
    /// timer and the screen time log.
    public enum Presence: Equatable, Sendable {
        /// At the screen, last seen this many seconds ago: at the last input,
        /// or now while a video or a call keeps them there.
        case here(secondsAgo: TimeInterval)
        /// Away this long: no input with nothing keeping them at the screen,
        /// the screen locked, or the Mac asleep.
        case away(seconds: TimeInterval)
    }

    public var config: Config
    public private(set) var state: State = .working
    /// Seconds until the next break, or until the current break ends.
    public private(set) var remaining: TimeInterval
    /// Whether the heads-up should be on screen.
    public private(set) var showsHeadsUp = false
    /// Whether the current break, if any, is a long one.
    public private(set) var isLongBreak = false
    /// Breaks taken since the last long one (or since the user was away for
    /// at least a long break's length).
    public private(set) var breaksSinceLong = 0
    /// Whether the user was at the screen on the last tick.
    public private(set) var presence = Presence.here(secondsAgo: 0)

    /// Whether the next break will be a long one.
    public var nextBreakIsLong: Bool {
        config.longBreakEvery > 0 && breaksSinceLong + 1 >= config.longBreakEvery
    }

    /// Length of the current break, or of the next one.
    public var breakLength: TimeInterval {
        let long = state == .onBreak ? isLongBreak : nextBreakIsLong
        return long ? config.longBreakSeconds : config.breakSeconds
    }

    /// Events since the last `takeEvents()`.
    private var events: [Event] = []
    /// Total seconds ticked so far: the timer's own monotonic clock.
    private var clock: TimeInterval = 0
    /// When the current break became due, while it waits for a pause in typing.
    private var dueSince: TimeInterval?

    public init(config: Config = Config()) {
        self.config = config
        remaining = config.workSeconds
    }

    // MARK: Ticking

    /// Returns the events that happened since the last call, oldest first.
    public mutating func takeEvents() -> [Event] {
        defer { events = [] }
        return events
    }

    /// Advances the timer by `elapsed` seconds of monotonic time. `now` is the
    /// wall-clock time, used only to end a "pause until" at the right moment.
    public mutating func tick(elapsed: TimeInterval, now: Date, probe: ActivityProbe) {
        // A monotonic source never goes backwards; guard anyway.
        let elapsed = max(0, elapsed)
        clock += elapsed
        presence = checkPresence(gap: elapsed, probe: probe)

        switch state {
        case .paused(let until):
            if let until, now >= until { resume() }

        case .onBreak:
            remaining -= elapsed
            if remaining <= 0 {
                // A gap longer than the whole break means the Mac slept through
                // it, so end the break quietly.
                events.append(elapsed <= breakLength
                    ? .breakFinished(long: isLongBreak)
                    : .breakInterrupted(long: isLongBreak))
                countBreak()
                endBreak(nextIn: config.workSeconds)
            }

        case .working, .waiting, .waitingForTyping, .away:
            if case .away(let seconds) = presence {
                state = .away
                remaining = config.workSeconds
                dueSince = nil
                // Away for as long as a long break counts as one.
                if seconds >= config.longBreakSeconds {
                    breaksSinceLong = 0
                }
            } else {
                remaining = max(0, remaining - elapsed)
                if remaining > 0 {
                    state = .working
                    dueSince = nil
                } else if let reason = probe.busyReason() {
                    state = .waiting(reason: reason)
                } else if case .waiting = state, config.graceSeconds > 0 {
                    // The call or meeting just ended; give a moment before the break.
                    state = .working
                    remaining = config.graceSeconds
                } else if isTyping(probe: probe) {
                    state = .waitingForTyping
                } else {
                    startBreak()
                }
            }
        }

        updateHeadsUp(probe: probe)
    }

    // MARK: Actions

    public mutating func takeBreakNow() {
        startBreak()
    }

    /// Skipping still counts toward the next long break, so skipping short
    /// breaks doesn't put a long one off.
    public mutating func skipBreak() {
        if state == .onBreak {
            events.append(.breakSkipped(long: isLongBreak))
            countBreak()
        }
        endBreak(nextIn: config.workSeconds)
    }

    public mutating func postponeBreak() {
        events.append(.breakPostponed)
        endBreak(nextIn: config.postponeSeconds)
    }

    public mutating func pause(until: Date?) {
        events.append(.paused(until: until))
        state = .paused(until: until)
        dueSince = nil
        isLongBreak = false
        showsHeadsUp = false
    }

    public mutating func resume() {
        events.append(.resumed)
        startWork()
    }

    /// Starts a fresh work interval, e.g. after the interval setting changes.
    /// Leaves a break or a pause alone.
    public mutating func restartWorkTimer() {
        switch state {
        case .onBreak, .paused: return
        default: startWork()
        }
    }

    // MARK: Helpers

    /// The user is away, taking a natural break, if the screen is locked, the
    /// Mac just woke from sleep (a gap longer than a break), or there has been
    /// no input for a while. Without input they still count as here while a
    /// video or a call keeps them at the screen. Once away, only input brings
    /// them back, so a long absence costs no slow checks.
    private func checkPresence(gap: TimeInterval, probe: ActivityProbe) -> Presence {
        let idle = probe.idleSeconds()
        if probe.isScreenLocked || gap > config.breakSeconds { return .away(seconds: max(gap, idle)) }
        if idle < max(config.idleResetSeconds, config.breakSeconds) { return .here(secondsAgo: idle) }
        if case .here = presence, probe.isDisplayHeldAwake() || probe.isInCall() { return .here(secondsAgo: 0) }
        return .away(seconds: idle)
    }

    /// A due break waits for a pause in typing, but no longer than
    /// `maxTypingWaitSeconds` after it became due.
    private mutating func isTyping(probe: ActivityProbe) -> Bool {
        if dueSince == nil { dueSince = clock }
        let waited = clock - (dueSince ?? clock)
        return probe.secondsSinceKeyPress() < config.typingPauseSeconds
            && waited < config.maxTypingWaitSeconds
    }

    /// Shown in the last seconds before a break and while a due break waits
    /// for a pause in typing.
    private mutating func updateHeadsUp(probe: ActivityProbe) {
        let warning = config.headsUpSeconds
        switch state {
        case .waitingForTyping:
            showsHeadsUp = warning > 0
        case .working:
            // No warning for a break that a busy check is about to hold. Once
            // shown, keep it up rather than re-checking every second.
            showsHeadsUp = warning > 0 && remaining <= warning && (showsHeadsUp || probe.busyReason() == nil)
        default:
            showsHeadsUp = false
        }
    }

    private mutating func startWork() {
        state = .working
        remaining = config.workSeconds
        dueSince = nil
        showsHeadsUp = false
    }

    private mutating func startBreak() {
        dueSince = nil
        isLongBreak = nextBreakIsLong
        events.append(.breakStarted(long: isLongBreak))
        state = .onBreak
        remaining = breakLength
        showsHeadsUp = false
    }

    /// Records a break that ended by running out or being skipped.
    private mutating func countBreak() {
        breaksSinceLong = isLongBreak ? 0 : breaksSinceLong + 1
    }

    private mutating func endBreak(nextIn interval: TimeInterval) {
        dueSince = nil
        isLongBreak = false
        state = .working
        remaining = interval
        showsHeadsUp = false
    }
}
