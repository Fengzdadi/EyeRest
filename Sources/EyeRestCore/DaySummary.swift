import Foundation

/// One day's totals, computed from the activity log.
public struct DaySummary: Codable, Equatable, Sendable {
    /// The local calendar day, "yyyy-MM-dd".
    public var date: String
    /// Time at the screen.
    public var screenSeconds: TimeInterval = 0
    /// The longest time at the screen without a break or time away.
    public var longestStretchSeconds: TimeInterval = 0
    public var breaksFinished = 0
    /// Of `breaksFinished`, how many were long.
    public var longBreaksFinished = 0
    public var breaksSkipped = 0
    public var breaksPostponed = 0
    /// Time at the screen in each app, by bundle identifier, when apps are
    /// recorded.
    public var apps: [String: TimeInterval] = [:]

    public init(date: String) {
        self.date = date
    }

    /// The apps used at least a minute, most used first, at most `limit`.
    public func mostUsedApps(limit: Int) -> [(bundleID: String, seconds: TimeInterval)] {
        apps.filter { $0.value >= 60 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map { ($0.key, $0.value) }
    }

    /// Summaries for the `days` calendar days ending with the day of `now`,
    /// oldest first. Stretches crossing midnight are split between the days.
    /// Days that ended by `since`, such as days before the log begins, are
    /// left out; the day of `now` never is.
    public static func summaries(of records: [ActivityRecord], days: Int, now: Date, since: Date? = nil,
                                 calendar: Calendar = .current) -> [DaySummary] {
        let today = calendar.startOfDay(for: now)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        return (0..<max(1, days)).reversed().compactMap { back in
            // Counting back from today lands on the right day, but not always
            // at its start: where clocks skip midnight, a day starts at 01:00.
            let day = calendar.dateInterval(of: .day, for: calendar.date(byAdding: .day, value: -back, to: today)!)!
            if back > 0, let since, day.end <= since { return nil }
            return summary(of: records, from: day.start, to: day.end, date: formatter.string(from: day.start))
        }
    }

    /// Chunks of one stretch meet end to start; anything longer than this
    /// between them (a break, time away) separates two stretches.
    static let stretchGap: TimeInterval = 5

    static func summary(of records: [ActivityRecord], from dayStart: Date, to dayEnd: Date, date: String) -> DaySummary {
        var day = DaySummary(date: date)

        let spans = records
            .filter { $0.kind == .active }
            .compactMap { record -> (start: Date, end: Date)? in
                guard let end = record.end else { return nil }
                let start = max(record.start, dayStart)
                let clipped = min(end, dayEnd)
                return clipped > start ? (start, clipped) : nil
            }
            .sorted { $0.start < $1.start }

        var stretch: (start: Date, end: Date)?
        for span in spans {
            day.screenSeconds += span.end.timeIntervalSince(span.start)
            if let current = stretch, span.start.timeIntervalSince(current.end) <= stretchGap {
                stretch = (current.start, max(current.end, span.end))
            } else {
                stretch = span
            }
            if let stretch {
                day.longestStretchSeconds = max(day.longestStretchSeconds, stretch.end.timeIntervalSince(stretch.start))
            }
        }

        for record in records where record.start >= dayStart && record.start < dayEnd {
            switch record.kind {
            case .active:
                // A record holds chunks that start on one day (see
                // `mergingChunks`), so its apps count for that day, give or
                // take the chunk that runs past midnight.
                day.apps.merge(record.apps ?? [:], uniquingKeysWith: +)
            case .breakFinished:
                day.breaksFinished += 1
                if record.long == true { day.longBreaksFinished += 1 }
            case .breakSkipped: day.breaksSkipped += 1
            case .breakPostponed: day.breaksPostponed += 1
            default: break
            }
        }
        return day
    }
}
