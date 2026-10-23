import EyeRestCore
import Foundation
import os

private let log = Logger(subsystem: "io.github.fengzdadi.EyeRest", category: "activity")

/// Keeps the activity log and the status file that the MCP server reads.
@MainActor
final class ActivityLogger {
    private let store = ActivityStore()
    private var recorder = ScreenTimeRecorder()
    /// What the status file says now, minus timestamps that move every second.
    private var statusKey = ""

    init() {
        do {
            try store.prune(keepingDays: 90, now: Date())
        } catch {
            log.error("can't prune the activity log: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Records whether the user is at the screen, once a tick.
    func recordPresence(now: Date, elapsed: TimeInterval, timer: BreakTimer, probe: ActivityProbe) {
        let lastSeen = ScreenTimeRecorder.lastSeen(
            now: now, probe: probe, onBreak: timer.state == .onBreak, elapsed: elapsed,
            idleLimit: max(timer.config.idleResetSeconds, timer.config.breakSeconds),
            sleepGap: timer.config.breakSeconds)
        if let record = recorder.record(now: now, lastSeen: lastSeen) {
            write([record])
        }
    }

    func record(_ events: [BreakTimer.Event], at now: Date) {
        write(events.map { ActivityRecord($0, at: now) })
    }

    /// Rewrites the status file when what it says has changed. The next
    /// break's time is compared to the nearest 15 seconds, since it shifts by
    /// a fraction of a second every tick.
    func updateStatus(_ timer: BreakTimer, now: Date) {
        let config = timer.config
        var status = StatusSnapshot(
            state: "working",
            nextBreakIsLong: timer.nextBreakIsLong,
            workMinutes: Int(config.workSeconds / 60),
            breakSeconds: Int(config.breakSeconds),
            longBreakEvery: config.longBreakEvery,
            longBreakMinutes: Int(config.longBreakSeconds / 60),
            pid: getpid(),
            updatedAt: now)
        switch timer.state {
        case .working:
            status.nextBreakAt = now.addingTimeInterval(timer.remaining)
        case .waiting(let reason):
            status.state = "waiting"
            status.waitingReason = reason
        case .waitingForTyping:
            status.state = "waitingForTyping"
        case .away:
            status.state = "away"
        case .onBreak:
            status.state = "onBreak"
            status.isLongBreak = timer.isLongBreak
            status.breakEndsAt = now.addingTimeInterval(timer.remaining)
        case .paused(let until):
            status.state = "paused"
            status.pausedUntil = until
        }

        func bucket(_ date: Date?) -> String { date.map { "\(Int($0.timeIntervalSince1970 / 15))" } ?? "-" }
        let key = [
            status.state, status.waitingReason ?? "-", "\(status.nextBreakIsLong)", "\(status.isLongBreak)",
            bucket(status.nextBreakAt), bucket(status.breakEndsAt), bucket(status.pausedUntil),
            "\(status.workMinutes) \(status.breakSeconds) \(status.longBreakEvery) \(status.longBreakMinutes)",
        ].joined(separator: "|")
        guard key != statusKey else { return }
        statusKey = key
        do {
            try store.writeStatus(status)
        } catch {
            log.error("can't write the status file: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Ends the current stretch and removes the status file, as the app quits.
    func shutdown() {
        if let record = recorder.close() { write([record]) }
        try? FileManager.default.removeItem(at: store.statusURL)
    }

    private func write(_ records: [ActivityRecord]) {
        do {
            try store.append(records)
        } catch {
            log.error("can't write the activity log: \(error.localizedDescription, privacy: .public)")
        }
    }
}
