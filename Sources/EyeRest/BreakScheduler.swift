import AppKit
import EyeRestCore
import os

private let log = Logger(subsystem: "io.github.fengzdadi.EyeRest", category: "scheduler")

/// Runs the `BreakTimer` once a second and mirrors it into the UI: the break
/// screen, the heads-up and the menu bar.
@MainActor
final class BreakScheduler: ObservableObject {
    typealias State = BreakTimer.State

    @Published private(set) var state: State = .working
    /// Seconds until the next break, or until the current break ends.
    @Published private(set) var remaining: TimeInterval
    @Published private(set) var isLongBreak = false
    @Published private(set) var nextBreakIsLong = false
    /// Length of the current break, or of the next one.
    @Published private(set) var breakLength: TimeInterval = 0

    var onUpdate: (() -> Void)?

    let calendar = MeetingCalendar()
    private let probe: LiveProbe
    private var core = BreakTimer(config: .current)
    private let overlay = BreakOverlay()
    private let headsUp = HeadsUp()
    private var ticker: Timer?
    /// A monotonic clock (unlike Date, unaffected by clock changes) that keeps
    /// counting while the Mac sleeps, so a sleep shows up as a long gap.
    private var lastTick = ContinuousClock.now

    init() {
        probe = LiveProbe(calendar: calendar)
        remaining = core.remaining
        overlay.onSkip = { [weak self] in self?.skipBreak() }
        overlay.onPostpone = { [weak self] in self?.postponeBreak() }
        headsUp.onStartNow = { [weak self] in self?.takeBreakNow() }
        headsUp.onPostpone = { [weak self] in self?.postponeBreak() }
    }

    func start() {
        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Ticks measure real elapsed time, so letting macOS shift them a little to
        // batch wakeups with other work costs no accuracy.
        ticker.tolerance = 0.3
        RunLoop.main.add(ticker, forMode: .common)  // keep ticking while the menu is open
        self.ticker = ticker
        sync()
    }

    // MARK: Actions

    func takeBreakNow() {
        core.takeBreakNow()
        sync()
    }

    func skipBreak() {
        log.notice("break skipped")
        core.skipBreak()
        sync()
    }

    func postponeBreak() {
        log.notice("break postponed")
        core.postponeBreak()
        sync()
    }

    func pause(for duration: TimeInterval?) {
        core.pause(until: duration.map { Date().addingTimeInterval($0) })
        sync()
    }

    func resume() {
        core.resume()
        sync()
    }

    /// Starts a fresh work interval, e.g. after the interval setting changes.
    func restartWorkTimer() {
        core.config = .current
        core.restartWorkTimer()
        sync()
    }

    // MARK: Timer

    private func tick() {
        let now = ContinuousClock.now
        let elapsed = (now - lastTick).seconds
        lastTick = now

        core.config = .current
        if core.tick(elapsed: elapsed, now: Date(), probe: probe) == .breakFinished, Settings.playSound {
            NSSound(named: "Glass")?.play()
        }
        sync()
    }

    /// Copies the timer's state to the published properties and shows or hides
    /// the break screen and the heads-up to match.
    private func sync() {
        let previous = state
        if core.state != previous {
            log.notice("state: \(String(describing: self.core.state), privacy: .public)")
        }
        state = core.state
        remaining = core.remaining
        isLongBreak = core.isLongBreak
        nextBreakIsLong = core.nextBreakIsLong
        breakLength = core.breakLength

        if state == .onBreak && previous != .onBreak {
            overlay.show(scheduler: self)
        } else if state != .onBreak && previous == .onBreak {
            overlay.hide()
        }
        if core.showsHeadsUp {
            headsUp.show(scheduler: self)
        } else {
            headsUp.hide()
        }
        onUpdate?()
    }
}

private extension Duration {
    var seconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
