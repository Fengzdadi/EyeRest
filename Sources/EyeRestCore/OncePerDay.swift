import Foundation

/// Says when a daily chore is due: the first time it's asked, and then the
/// first time it's asked on each new calendar day.
public struct OncePerDay: Sendable {
    private var lastDone: Date?

    public init() {}

    public mutating func isDue(now: Date, calendar: Calendar = .current) -> Bool {
        if let lastDone, calendar.isDate(now, inSameDayAs: lastDone) { return false }
        lastDone = now
        return true
    }
}
