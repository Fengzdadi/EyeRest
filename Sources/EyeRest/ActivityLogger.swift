import EyeRestCore
import Foundation
import os

private let log = Logger(subsystem: "io.github.fengzdadi.EyeRest", category: "activity")

/// Keeps the activity log and the status file that the MCP server reads, and
/// the last week of the log for the menu.
@MainActor
final class ActivityLogger {
    private let store = ActivityStore()
    private var recorder = ScreenTimeRecorder()
    /// The log is compacted on the first tick, then on the first of each day.
    private var compaction = OncePerDay()
    /// What the status file says now, minus timestamps that move every second.
    private var statusKey = ""
    /// The last week of the log, read from the file the first time the menu
    /// asks and kept up to date as records are written. The menu asks every
    /// second while it's open, and Accessibility clients can make it ask
    /// while it's closed, so the file is read only once.
    private var recent: [ActivityRecord]?
    /// When the log begins.
    private var firstRecord: Date?

    /// Summaries for the last `days` days, oldest first, counting the stretch
    /// at the screen not written to the log yet. Days before the log begins
    /// are left out.
    func summaries(days: Int, now: Date) -> [DaySummary] {
        if recent == nil {
            let records = store.records()
            firstRecord = records.map(\.start).min()
            recent = Self.lastWeek(of: records, now: now)
        }
        let pending = recorder.pending
        let records = (recent ?? []) + (pending.map { [$0] } ?? [])
        return DaySummary.summaries(of: records, days: days, now: now, since: firstRecord ?? pending?.start ?? now)
    }

    /// The records of the last 8 days, enough for a week of calendar days,
    /// with each stretch's chunks merged.
    private static func lastWeek(of records: [ActivityRecord], now: Date) -> [ActivityRecord] {
        let cutoff = now.addingTimeInterval(-8 * 86_400)
        return ActivityRecord.mergingChunks(records.filter { ($0.end ?? $0.start) >= cutoff })
    }

    /// Records whether the user is at the screen, once a tick, from what the
    /// timer worked out on that tick, and which app is in front if apps are
    /// recorded.
    func recordPresence(now: Date, timer: BreakTimer) {
        let lastSeen = ScreenTimeRecorder.lastSeen(now: now, presence: timer.presence, onBreak: timer.state == .onBreak)
        let app = Settings.recordApps ? Activity.frontmostApp() : nil
        if let record = recorder.record(now: now, lastSeen: lastSeen, app: app) {
            write([record])
        }
        if compaction.isDue(now: now) {
            compact(now: now)
        }
    }

    /// Drops records older than 90 days and merges each stretch's chunks, and
    /// does the same to the last week kept for the menu.
    private func compact(now: Date) {
        recent = recent.map { Self.lastWeek(of: $0, now: now) }
        do {
            try store.compact(keepingDays: 90, now: now)
        } catch {
            log.error("can't compact the activity log: \(error.localizedDescription, privacy: .public)")
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
        if recent != nil {
            recent?.append(contentsOf: records)
            if firstRecord == nil { firstRecord = records.first?.start }
        }
        do {
            try store.append(records)
        } catch {
            log.error("can't write the activity log: \(error.localizedDescription, privacy: .public)")
        }
    }
}
