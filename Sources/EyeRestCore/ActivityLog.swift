import Foundation

/// One line of the activity log: a stretch of time at the screen, or a break
/// event.
public struct ActivityRecord: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// The user was at the screen from `start` to `end`.
        case active
        case breakStarted, breakFinished, breakSkipped, breakPostponed, breakInterrupted
        case paused, resumed
    }

    public var kind: Kind
    /// When it happened, or when an active stretch began.
    public var start: Date
    /// The end of an active stretch.
    public var end: Date?
    /// For break events: whether it was a long break.
    public var long: Bool?
    /// For `paused`: when the pause ends, if it has an end.
    public var until: Date?
    /// For `active`, when apps are recorded: the seconds of the stretch each
    /// app was in front, by bundle identifier.
    public var apps: [String: TimeInterval]?

    public init(kind: Kind, start: Date, end: Date? = nil, long: Bool? = nil, until: Date? = nil,
                apps: [String: TimeInterval]? = nil) {
        self.kind = kind
        self.start = start
        self.end = end
        self.long = long
        self.until = until
        self.apps = apps
    }

    /// The record for a timer event that happened at `time`.
    public init(_ event: BreakTimer.Event, at time: Date) {
        switch event {
        case .breakStarted(let long): self.init(kind: .breakStarted, start: time, long: long)
        case .breakFinished(let long): self.init(kind: .breakFinished, start: time, long: long)
        case .breakSkipped(let long): self.init(kind: .breakSkipped, start: time, long: long)
        case .breakPostponed: self.init(kind: .breakPostponed, start: time)
        case .breakInterrupted(let long): self.init(kind: .breakInterrupted, start: time, long: long)
        case .paused(let until): self.init(kind: .paused, start: time, until: until)
        case .resumed: self.init(kind: .resumed, start: time)
        }
    }

    /// `records` with each stretch's chunks, which meet end to start, merged
    /// into an `active` record per calendar day, even across events logged
    /// during the stretch. Time at the screen and stretches come out the same;
    /// the log just shrinks to about a line per stretch. A record holds only
    /// chunks that start on one day, so its time in each app is that day's.
    public static func mergingChunks(_ records: [ActivityRecord], calendar: Calendar = .current) -> [ActivityRecord] {
        var merged: [ActivityRecord] = []
        var lastActive: Int?
        for record in records {
            if record.kind == .active, let index = lastActive, merged[index].end == record.start,
               calendar.isDate(record.start, inSameDayAs: merged[index].start) {
                merged[index].end = record.end
                if let apps = record.apps {
                    merged[index].apps = (merged[index].apps ?? [:]).merging(apps, uniquingKeysWith: +)
                }
            } else {
                if record.kind == .active { lastActive = merged.count }
                merged.append(record)
            }
        }
        return merged
    }
}

/// Turns once-a-second "is the user at the screen?" checks into `active`
/// records. A long stretch is written in chunks of `chunkSeconds`, so little is
/// lost if the app quits unexpectedly; chunks of one stretch meet end to start,
/// and `ActivityStore.compact` later merges them. Told which app is in front
/// at each check, a chunk also says how long each app was.
public struct ScreenTimeRecorder: Sendable {
    public var chunkSeconds: TimeInterval
    private var start: Date?
    /// The last moment the user was known to be there.
    private var lastSeen: Date?
    /// The current chunk's seconds in each app.
    private var apps: [String: TimeInterval] = [:]
    /// The app in front at the last check.
    private var appInFront: String?

    public init(chunkSeconds: TimeInterval = 60) {
        self.chunkSeconds = chunkSeconds
    }

    /// When the user was last known to be at the screen, or nil if they don't
    /// count as there now: on a break, or away (see `BreakTimer.Presence`).
    public static func lastSeen(now: Date, presence: BreakTimer.Presence, onBreak: Bool) -> Date? {
        guard !onBreak, case .here(let secondsAgo) = presence else { return nil }
        return now.addingTimeInterval(-secondsAgo)
    }

    /// Records one check at `now`; `lastSeen` is nil when the user isn't there,
    /// and `app` is the bundle identifier of the app in front, if apps are
    /// recorded. A stretch that ends is cut at the last moment the user was
    /// seen, so walking away doesn't count the idle time before it was noticed.
    public mutating func record(now: Date, lastSeen: Date?, app: String? = nil) -> ActivityRecord? {
        guard let lastSeen else { return close() }
        defer { appInFront = app }
        guard let start, let previous = self.lastSeen else {
            self.start = now
            self.lastSeen = now
            return nil
        }
        // Chunks end at the last sighting, not at `now`: if the user has
        // already walked away, the idle time isn't counted, and if not, the
        // next chunk picks it up.
        let seen = max(lastSeen, start)
        // What the stretch grew by goes to the app that was in front at the
        // last check, so a chunk's apps add up to its length. Not the one in
        // front now: a pause is counted only once the user is back, and coming
        // back may mean switching apps.
        if let appInFront, seen > previous { apps[appInFront, default: 0] += seen.timeIntervalSince(previous) }
        self.lastSeen = seen
        if seen.timeIntervalSince(start) >= chunkSeconds {
            defer { apps = [:] }
            self.start = seen
            return ActivityRecord(kind: .active, start: start, end: seen, apps: appSeconds)
        }
        return nil
    }

    /// The part of the current stretch not written yet: from its start, or
    /// the end of its last chunk, to the last sighting.
    public var pending: ActivityRecord? {
        guard let start, let lastSeen, lastSeen > start else { return nil }
        return ActivityRecord(kind: .active, start: start, end: lastSeen, apps: appSeconds)
    }

    /// Ends the current stretch, e.g. when the app quits.
    public mutating func close() -> ActivityRecord? {
        defer {
            start = nil
            lastSeen = nil
            apps = [:]
            appInFront = nil
        }
        return pending
    }

    /// The current chunk's time in each app, in whole seconds to keep the log
    /// short, or nil if no app was recorded.
    private var appSeconds: [String: TimeInterval]? {
        let seconds = apps.mapValues { $0.rounded() }.filter { $0.value > 0 }
        return seconds.isEmpty ? nil : seconds
    }
}
