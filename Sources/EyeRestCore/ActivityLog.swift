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

    public init(kind: Kind, start: Date, end: Date? = nil, long: Bool? = nil, until: Date? = nil) {
        self.kind = kind
        self.start = start
        self.end = end
        self.long = long
        self.until = until
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
}

/// Turns once-a-second "is the user at the screen?" checks into `active`
/// records. A long stretch is written in chunks of `chunkSeconds`, so little is
/// lost if the app quits unexpectedly; chunks of one stretch meet end to start.
public struct ScreenTimeRecorder: Sendable {
    public var chunkSeconds: TimeInterval
    private var start: Date?
    /// The last moment the user was known to be there.
    private var lastSeen: Date?

    public init(chunkSeconds: TimeInterval = 60) {
        self.chunkSeconds = chunkSeconds
    }

    /// When the user was last known to be at the screen, or nil if they don't
    /// count as there now: on a break, or away (see `BreakTimer.Presence`).
    public static func lastSeen(now: Date, presence: BreakTimer.Presence, onBreak: Bool) -> Date? {
        guard !onBreak, case .here(let secondsAgo) = presence else { return nil }
        return now.addingTimeInterval(-secondsAgo)
    }

    /// Records one check at `now`; `lastSeen` is nil when the user isn't there.
    /// A stretch that ends is cut at the last moment the user was seen, so
    /// walking away doesn't count the idle time before it was noticed.
    public mutating func record(now: Date, lastSeen: Date?) -> ActivityRecord? {
        guard let lastSeen else { return close() }
        guard let start else {
            self.start = now
            self.lastSeen = now
            return nil
        }
        // Chunks end at the last sighting, not at `now`: if the user has
        // already walked away, the idle time isn't counted, and if not, the
        // next chunk picks it up.
        let seen = max(lastSeen, start)
        self.lastSeen = seen
        if seen.timeIntervalSince(start) >= chunkSeconds {
            self.start = seen
            return ActivityRecord(kind: .active, start: start, end: seen)
        }
        return nil
    }

    /// Ends the current stretch, e.g. when the app quits.
    public mutating func close() -> ActivityRecord? {
        guard let start, let lastSeen else { return nil }
        self.start = nil
        self.lastSeen = nil
        return lastSeen > start ? ActivityRecord(kind: .active, start: start, end: lastSeen) : nil
    }
}
