import Foundation
import Testing
@testable import EyeRestCore

// Most tests use a 60 s work interval, 20 s breaks and a 300 s long break
// every 3rd break; see `Rig.init`.

@MainActor
struct WorkAndBreak {
    @Test func startsWorkingWithAFullInterval() {
        let rig = Rig()
        #expect(rig.state == .working)
        #expect(rig.remaining == 60)
    }

    @Test func breakStartsWhenTheIntervalRunsOut() {
        var rig = Rig()
        rig.advance(59)
        #expect(rig.state == .working)
        #expect(rig.remaining == 1)
        rig.tick()
        #expect(rig.state == .onBreak)
        #expect(rig.remaining == 20)
    }

    @Test func breakFinishesAfterItsLength() {
        var rig = Rig()
        rig.advance(60)
        #expect(rig.advance(19).isEmpty)
        #expect(rig.state == .onBreak)
        #expect(rig.tick() == [.breakFinished(long: false)])
        #expect(rig.state == .working)
        #expect(rig.remaining == 60)
    }

    @Test func skipStartsAFullIntervalAndPostponeAShortOne() {
        var rig = Rig()
        rig.advance(60)
        rig.timer.skipBreak()
        #expect(rig.state == .working)
        #expect(rig.remaining == 60)

        rig.timer.takeBreakNow()
        #expect(rig.state == .onBreak)
        rig.timer.postponeBreak()
        #expect(rig.state == .working)
        #expect(rig.remaining == 30)
    }

    @Test func pauseStopsTheCountdownUntilTheGivenTime() {
        var rig = Rig()
        let until = rig.now.addingTimeInterval(100)
        rig.timer.pause(until: until)
        rig.advance(99)
        #expect(rig.state == .paused(until: until))
        rig.tick()
        #expect(rig.state == .working)
        #expect(rig.remaining == 60)
    }

    @Test func pauseWithoutAnEndLastsUntilResumed() {
        var rig = Rig()
        rig.timer.pause(until: nil)
        rig.advance(3600)
        #expect(rig.state == .paused(until: nil))
        rig.timer.resume()
        #expect(rig.state == .working)
        #expect(rig.remaining == 60)
    }

    @Test func changingTheIntervalDoesNotInterruptABreak() {
        var rig = Rig()
        rig.advance(60)
        rig.timer.config.workSeconds = 120
        rig.timer.restartWorkTimer()
        #expect(rig.state == .onBreak)
        rig.advance(20)
        #expect(rig.remaining == 120)
    }

    @Test func changingTheIntervalRestartsWork() {
        var rig = Rig()
        rig.advance(30)
        rig.timer.config.workSeconds = 120
        rig.timer.restartWorkTimer()
        #expect(rig.remaining == 120)
    }
}

@MainActor
struct Away {
    @Test func idleBeyondTheLimitResetsTheTimer() {
        var rig = Rig()
        rig.advance(30)
        rig.probe.idle = 120
        rig.tick()
        #expect(rig.state == .away)
        #expect(rig.remaining == 60)

        rig.probe.idle = 0
        rig.tick()
        #expect(rig.state == .working)
        #expect(rig.remaining == 59)
    }

    @Test func idleJustUnderTheLimitKeepsCounting() {
        var rig = Rig()
        rig.probe.idle = 119
        rig.advance(30)
        #expect(rig.state == .working)
        #expect(rig.remaining == 30)
    }

    @Test func watchingAVideoIsNotAway() {
        var rig = Rig()
        rig.probe.idle = 600
        rig.probe.displayHeldAwake = true
        rig.advance(60)
        #expect(rig.state == .onBreak)
    }

    @Test func aLockedScreenIsAway() {
        var rig = Rig()
        rig.probe.isScreenLocked = true
        rig.advance(100)
        #expect(rig.state == .away)
        #expect(rig.remaining == 60)
    }

    @Test func sleepIsAway() {
        var rig = Rig()
        rig.advance(30)
        rig.tick(3600)
        #expect(rig.state == .away)
        #expect(rig.remaining == 60)
    }

    @Test func aGapNoLongerThanABreakIsNotSleep() {
        var rig = Rig()
        rig.advance(30)
        rig.tick(20)
        #expect(rig.state == .working)
        #expect(rig.remaining == 10)
    }

    @Test func theIdleLimitIsAtLeastOneBreakLong() {
        var rig = Rig { $0.idleResetSeconds = 5 }
        rig.probe.idle = 10  // past idleResetSeconds, but shorter than a 20 s break
        rig.advance(30)
        #expect(rig.state == .working)
        #expect(rig.remaining == 30)
    }
}

@MainActor
struct BusyHolds {
    @Test func aCallHoldsADueBreak() {
        var rig = Rig()
        rig.probe.busy = "camera in use"
        rig.advance(60)
        #expect(rig.state == .waiting(reason: "camera in use"))
        rig.advance(600)
        #expect(rig.state == .waiting(reason: "camera in use"))
    }

    @Test func beingBusyEarlierDoesNotStopTheCountdown() {
        var rig = Rig()
        rig.probe.busy = "camera in use"
        rig.advance(30)
        #expect(rig.state == .working)
        #expect(rig.remaining == 30)
    }

    @Test func theBreakWaitsOutTheGraceAfterACall() {
        var rig = Rig()
        rig.probe.busy = "microphone in use"
        rig.advance(70)
        rig.probe.busy = nil
        rig.tick()
        #expect(rig.state == .working)
        #expect(rig.remaining == 10)
        rig.advance(9)
        #expect(rig.state == .working)
        rig.tick()
        #expect(rig.state == .onBreak)
    }

    @Test func noGraceMeansTheBreakStartsRightAway() {
        var rig = Rig { $0.graceSeconds = 0 }
        rig.probe.busy = "Keynote slideshow"
        rig.advance(70)
        rig.probe.busy = nil
        rig.tick()
        #expect(rig.state == .onBreak)
    }

    @Test func aNewCallDuringTheGraceHoldsAgain() {
        var rig = Rig()
        rig.probe.busy = "camera in use"
        rig.advance(70)
        rig.probe.busy = nil
        rig.advance(5)
        #expect(rig.remaining == 6)  // the grace started at 10 on the first of those ticks
        rig.probe.busy = "meeting: Standup"
        rig.advance(5)
        #expect(rig.state == .working)  // the grace still runs out first
        rig.tick()
        #expect(rig.state == .waiting(reason: "meeting: Standup"))
    }
}

@MainActor
struct TypingWait {
    @Test func typingHoldsTheBreakUntilAPause() {
        var rig = Rig()
        rig.probe.sinceKeyPress = 0.5
        rig.advance(60)
        #expect(rig.state == .waitingForTyping)
        rig.advance(5)
        #expect(rig.state == .waitingForTyping)
        rig.probe.sinceKeyPress = 2
        rig.tick()
        #expect(rig.state == .onBreak)
    }

    @Test func theWaitIsCapped() {
        var rig = Rig()
        rig.probe.sinceKeyPress = 0
        rig.advance(60)
        rig.advance(29)
        #expect(rig.state == .waitingForTyping)
        rig.tick()
        #expect(rig.state == .onBreak)
    }

    @Test func eachBreakGetsAFreshWait() {
        var rig = Rig()
        rig.probe.sinceKeyPress = 0
        rig.advance(90)  // first break: due at 60, capped at 90
        #expect(rig.state == .onBreak)
        rig.advance(20 + 60 + 29)
        #expect(rig.state == .waitingForTyping)
    }

    @Test func aCallTakesPrecedenceOverTyping() {
        var rig = Rig()
        rig.probe.sinceKeyPress = 0
        rig.probe.busy = "camera in use"
        rig.advance(60)
        #expect(rig.state == .waiting(reason: "camera in use"))
    }
}

@MainActor
struct HeadsUp {
    @Test func showsInTheLastSeconds() {
        var rig = Rig()
        rig.advance(49)
        #expect(rig.remaining == 11)
        #expect(!rig.timer.showsHeadsUp)
        rig.tick()
        #expect(rig.timer.showsHeadsUp)
        rig.advance(9)
        #expect(rig.timer.showsHeadsUp)
        rig.tick()
        #expect(rig.state == .onBreak)
        #expect(!rig.timer.showsHeadsUp)
    }

    @Test func staysUpWhileWaitingForTyping() {
        var rig = Rig()
        rig.probe.sinceKeyPress = 0
        rig.advance(65)
        #expect(rig.state == .waitingForTyping)
        #expect(rig.timer.showsHeadsUp)
    }

    @Test func isSkippedForABreakThatWillBeHeld() {
        var rig = Rig()
        rig.probe.busy = "camera in use"
        rig.advance(55)
        #expect(!rig.timer.showsHeadsUp)
    }

    @Test func goesAwayWhenALateCallHoldsTheBreak() {
        var rig = Rig()
        rig.advance(52)
        #expect(rig.timer.showsHeadsUp)
        rig.probe.busy = "camera in use"
        rig.advance(3)
        #expect(rig.timer.showsHeadsUp)  // not re-checked every second once shown
        rig.advance(5)
        #expect(rig.state == .waiting(reason: "camera in use"))
        #expect(!rig.timer.showsHeadsUp)
    }

    @Test func canBeTurnedOff() {
        var rig = Rig { $0.headsUpSeconds = 0 }
        rig.probe.sinceKeyPress = 0
        rig.advance(65)
        #expect(rig.state == .waitingForTyping)
        #expect(!rig.timer.showsHeadsUp)
    }

    @Test func postponingHidesIt() {
        var rig = Rig()
        rig.advance(55)
        rig.timer.postponeBreak()
        #expect(!rig.timer.showsHeadsUp)
    }
}

@MainActor
struct LongBreaks {
    @Test func everyThirdBreakIsLong() {
        var rig = Rig()
        rig.takeShortBreak()
        rig.takeShortBreak()
        #expect(rig.timer.nextBreakIsLong)
        rig.advance(60)
        #expect(rig.state == .onBreak)
        #expect(rig.timer.isLongBreak)
        #expect(rig.remaining == 300)
        #expect(rig.advance(299).isEmpty)
        #expect(rig.tick() == [.breakFinished(long: true)])
        #expect(rig.timer.breaksSinceLong == 0)
        #expect(!rig.timer.nextBreakIsLong)
    }

    @Test func skippedShortBreaksStillCount() {
        var rig = Rig()
        for _ in 0..<2 {
            rig.advance(60)
            rig.timer.skipBreak()
        }
        rig.advance(60)
        #expect(rig.timer.isLongBreak)
    }

    @Test func postponingALongBreakKeepsItLong() {
        var rig = Rig()
        rig.takeShortBreak()
        rig.takeShortBreak()
        rig.advance(60)
        rig.timer.postponeBreak()
        #expect(rig.timer.nextBreakIsLong)
        rig.advance(30)
        #expect(rig.timer.isLongBreak)
    }

    @Test func skippingALongBreakStartsTheCountOver() {
        var rig = Rig()
        rig.takeShortBreak()
        rig.takeShortBreak()
        rig.advance(60)
        rig.timer.skipBreak()
        #expect(rig.timer.breaksSinceLong == 0)
    }

    @Test func beingAwayForALongBreakCountsAsOne() {
        var rig = Rig()
        rig.takeShortBreak()
        rig.takeShortBreak()
        rig.probe.idle = 300
        rig.tick()
        #expect(rig.state == .away)
        #expect(rig.timer.breaksSinceLong == 0)
        #expect(!rig.timer.nextBreakIsLong)
    }

    @Test func aShortAbsenceDoesNotCount() {
        var rig = Rig()
        rig.takeShortBreak()
        rig.takeShortBreak()
        rig.probe.idle = 150
        rig.tick()
        #expect(rig.state == .away)
        #expect(rig.timer.nextBreakIsLong)
    }

    @Test func sleepingLongerThanALongBreakCountsAsOne() {
        var rig = Rig()
        rig.takeShortBreak()
        rig.takeShortBreak()
        rig.tick(3600)
        #expect(!rig.timer.nextBreakIsLong)
    }

    @Test func canBeTurnedOff() {
        var rig = Rig { $0.longBreakEvery = 0 }
        for _ in 0..<5 { rig.takeShortBreak() }
        #expect(!rig.timer.nextBreakIsLong)
    }

    @Test func breakLengthFollowsTheNextBreak() {
        var rig = Rig()
        #expect(rig.timer.breakLength == 20)
        rig.takeShortBreak()
        rig.takeShortBreak()
        #expect(rig.timer.breakLength == 300)
    }
}

@MainActor
struct Events {
    @Test func aFullBreakStartsAndFinishes() {
        var rig = Rig()
        #expect(rig.advance(59).isEmpty)
        #expect(rig.tick() == [.breakStarted(long: false)])
        #expect(rig.advance(20) == [.breakFinished(long: false)])
    }

    @Test func longBreaksSayTheyAreLong() {
        var rig = Rig()
        rig.takeShortBreak()
        rig.takeShortBreak()
        #expect(rig.advance(60) == [.breakStarted(long: true)])
        rig.timer.skipBreak()
        #expect(rig.timer.takeEvents() == [.breakSkipped(long: true)])
    }

    @Test func postponingFromTheHeadsUpIsLoggedWithoutAStart() {
        var rig = Rig()
        rig.advance(55)
        rig.timer.postponeBreak()
        #expect(rig.timer.takeEvents() == [.breakPostponed])
    }

    @Test func aPauseThatRunsOutResumes() {
        var rig = Rig()
        let until = rig.now.addingTimeInterval(10)
        rig.timer.pause(until: until)
        #expect(rig.timer.takeEvents() == [.paused(until: until)])
        #expect(rig.advance(10) == [.resumed])
    }

    @Test func changingTheIntervalIsNotLogged() {
        var rig = Rig()
        rig.timer.config.workSeconds = 120
        rig.timer.restartWorkTimer()
        #expect(rig.timer.takeEvents().isEmpty)
    }
}

@MainActor
struct ClockEdges {
    @Test func aClockGoingBackwardsIsIgnored() {
        var rig = Rig()
        rig.advance(30)
        rig.tick(-3600)
        #expect(rig.state == .working)
        #expect(rig.remaining == 30)
    }

    @Test func sleepingThroughABreakEndsItQuietly() {
        var rig = Rig()
        rig.advance(60)
        #expect(rig.tick(3600) == [.breakInterrupted(long: false)])
        #expect(rig.state == .working)
        #expect(rig.remaining == 60)
    }

    @Test func aSlowTickWithinTheBreakStillFinishesIt() {
        var rig = Rig()
        rig.advance(60)
        #expect(rig.tick(20) == [.breakFinished(long: false)])
    }

    @Test func fractionalTicksAddUp() {
        var rig = Rig()
        for _ in 0..<119 { rig.tick(0.5) }
        #expect(rig.state == .working)
        rig.tick(0.5)
        #expect(rig.state == .onBreak)
    }

    @Test func aPauseThatEndsDuringSleepResumes() {
        var rig = Rig()
        rig.timer.pause(until: rig.now.addingTimeInterval(100))
        rig.tick(3600)
        #expect(rig.state == .working)
        #expect(rig.remaining == 60)
    }
}

// MARK: - Test doubles

@MainActor
final class FakeProbe: ActivityProbe {
    var idle: TimeInterval = 0
    var sinceKeyPress: TimeInterval = 60
    var displayHeldAwake = false
    var isScreenLocked = false
    var busy: String?

    func idleSeconds() -> TimeInterval { idle }
    func secondsSinceKeyPress() -> TimeInterval { sinceKeyPress }
    func isDisplayHeldAwake() -> Bool { displayHeldAwake }
    func busyReason() -> String? { busy }
}

/// A `BreakTimer` with a fake probe and a fake clock.
@MainActor
struct Rig {
    var timer: BreakTimer
    let probe = FakeProbe()
    var now = Date(timeIntervalSinceReferenceDate: 0)

    init(_ configure: (inout BreakTimer.Config) -> Void = { _ in }) {
        var config = BreakTimer.Config()
        config.workSeconds = 60
        config.breakSeconds = 20
        config.postponeSeconds = 30
        config.idleResetSeconds = 120
        config.graceSeconds = 10
        config.headsUpSeconds = 10
        config.typingPauseSeconds = 2
        config.maxTypingWaitSeconds = 30
        config.longBreakEvery = 3
        config.longBreakSeconds = 300
        configure(&config)
        timer = BreakTimer(config: config)
    }

    var state: BreakTimer.State { timer.state }
    var remaining: TimeInterval { timer.remaining }

    /// One tick, `elapsed` seconds after the last. Returns the events it caused.
    @discardableResult
    mutating func tick(_ elapsed: TimeInterval = 1) -> [BreakTimer.Event] {
        now += elapsed
        timer.tick(elapsed: elapsed, now: now, probe: probe)
        return timer.takeEvents()
    }

    /// Works through one interval and takes the (short) break that follows.
    mutating func takeShortBreak() {
        advance(60)
        precondition(state == .onBreak && !timer.isLongBreak)
        advance(20)
    }

    /// One tick per second for `seconds` seconds. Returns the events seen.
    @discardableResult
    mutating func advance(_ seconds: Int) -> [BreakTimer.Event] {
        (0..<seconds).flatMap { _ in tick() }
    }
}
