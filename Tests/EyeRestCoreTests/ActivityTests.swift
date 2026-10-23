import Foundation
import Testing
@testable import EyeRestCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15 08:00 UTC

private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func active(_ start: TimeInterval, _ end: TimeInterval) -> ActivityRecord {
    ActivityRecord(kind: .active, start: at(start), end: at(end))
}

struct Recorder {
    /// Feeds one check per second from `from` to `to`; `seen(t)` is the
    /// lastSeen for second t (nil when not at the screen).
    private func run(_ recorder: inout ScreenTimeRecorder, _ from: Int, _ to: Int,
                     seen: (Int) -> Date?) -> [ActivityRecord] {
        (from...to).compactMap { recorder.record(now: at(TimeInterval($0)), lastSeen: seen($0)) }
    }

    @Test func aStretchEndsWhenABreakStarts() {
        var recorder = ScreenTimeRecorder()
        var records = run(&recorder, 0, 30) { at(TimeInterval($0)) }
        records += run(&recorder, 31, 31) { _ in nil }
        #expect(records == [active(0, 30)])
    }

    @Test func longStretchesAreWrittenInContiguousChunks() {
        var recorder = ScreenTimeRecorder(chunkSeconds: 60)
        var records = run(&recorder, 0, 150) { at(TimeInterval($0)) }
        if let last = recorder.close() { records.append(last) }
        #expect(records == [active(0, 60), active(60, 120), active(120, 150)])
    }

    @Test func walkingAwayIsCutAtTheLastInput() {
        var recorder = ScreenTimeRecorder(chunkSeconds: 60)
        // Typing until second 10, then no input until it counts as away at 130.
        var records = run(&recorder, 0, 129) { at(TimeInterval(min($0, 10))) }
        records += run(&recorder, 130, 130) { _ in nil }
        #expect(records == [active(0, 10)])
    }

    @Test func aVideoKeepsTheStretchGoing() {
        var recorder = ScreenTimeRecorder(chunkSeconds: 600)
        _ = run(&recorder, 0, 300) { at(TimeInterval($0)) }  // lastSeen == now while a video plays
        #expect(recorder.close() == active(0, 300))
    }

    @Test func closingWithNothingOpenRecordsNothing() {
        var recorder = ScreenTimeRecorder()
        #expect(recorder.close() == nil)
    }

    @MainActor
    @Test func lastSeenFollowsInputBreaksLocksAndSleep() {
        let probe = FakeProbe()
        let now = at(100)
        func seen(onBreak: Bool = false, elapsed: TimeInterval = 1) -> Date? {
            ScreenTimeRecorder.lastSeen(now: now, probe: probe, onBreak: onBreak, elapsed: elapsed,
                                        idleLimit: 120, sleepGap: 20)
        }
        probe.idle = 5
        #expect(seen() == at(95))
        #expect(seen(onBreak: true) == nil)
        #expect(seen(elapsed: 3600) == nil)
        probe.idle = 120
        #expect(seen() == nil)
        probe.displayHeldAwake = true
        #expect(seen() == now)
        probe.isScreenLocked = true
        #expect(seen() == nil)
    }
}

struct Summaries {
    private func day(_ records: [ActivityRecord], back: Int = 0, now: Date = at(3600)) -> DaySummary {
        let days = DaySummary.summaries(of: records, days: back + 1, now: now, calendar: utc)
        return days[days.count - 1 - back]
    }

    @Test func screenTimeAddsUpTheDaysStretches() {
        let summary = day([active(0, 600), active(1200, 1500)])
        #expect(summary.date == "2027-01-15")
        #expect(summary.screenSeconds == 900)
    }

    @Test func aStretchOverMidnightIsSplit() {
        // 23:50 to 00:10 UTC.
        let start = -8 * 3600 - 600.0
        let records = [active(start, start + 1200)]
        #expect(day(records).screenSeconds == 600)
        #expect(day(records, back: 1).screenSeconds == 600)
        #expect(day(records, back: 1).date == "2027-01-14")
    }

    @Test func contiguousChunksMakeOneStretch() {
        let summary = day([active(0, 60), active(60, 120), active(120, 150), active(170, 400)])
        #expect(summary.longestStretchSeconds == 230)  // the 20 s gap (a break) splits them
        #expect(summary.screenSeconds == 380)
    }

    @Test func breaksAreCounted() {
        let records = [
            ActivityRecord(kind: .breakStarted, start: at(10), long: false),
            ActivityRecord(kind: .breakFinished, start: at(30), long: false),
            ActivityRecord(kind: .breakFinished, start: at(400), long: true),
            ActivityRecord(kind: .breakSkipped, start: at(500), long: false),
            ActivityRecord(kind: .breakPostponed, start: at(600)),
            ActivityRecord(kind: .breakInterrupted, start: at(700), long: false),
        ]
        let summary = day(records)
        #expect(summary.breaksFinished == 2)
        #expect(summary.longBreaksFinished == 1)
        #expect(summary.breaksSkipped == 1)
        #expect(summary.breaksPostponed == 1)
    }

    @Test func daysComeOldestFirst() {
        let days = DaySummary.summaries(of: [], days: 3, now: at(0), calendar: utc)
        #expect(days.map(\.date) == ["2027-01-13", "2027-01-14", "2027-01-15"])
    }
}

struct Store {
    private func makeStore() -> ActivityStore {
        ActivityStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("EyeRestTests-\(UUID().uuidString)"))
    }

    @Test func recordsRoundTrip() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let records = [active(0, 60), ActivityRecord(kind: .paused, start: at(70), until: at(1870))]
        try store.append(Array(records[..<1]))
        try store.append(Array(records[1...]))
        #expect(store.records() == records)
    }

    @Test func aHalfWrittenLineIsSkipped() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.append([active(0, 60)])
        let handle = try FileHandle(forWritingTo: store.activityURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"kind\":\"act".utf8))
        try handle.close()
        #expect(store.records() == [active(0, 60)])
    }

    @Test func pruningDropsOldRecords() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.append([active(-100 * 86_400, -100 * 86_400 + 60), active(0, 60)])
        try store.prune(keepingDays: 90, now: at(0))
        #expect(store.records() == [active(0, 60)])
    }

    @Test func statusRoundTrips() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(store.status() == nil)
        let status = StatusSnapshot(state: "working", nextBreakAt: at(750), workMinutes: 20, breakSeconds: 20,
                                    longBreakEvery: 3, longBreakMinutes: 5, pid: 42, updatedAt: at(0))
        try store.writeStatus(status)
        #expect(store.status() == status)
    }
}
