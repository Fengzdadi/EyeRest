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

    public init(date: String) {
        self.date = date
    }

    /// Summaries for the `days` calendar days ending with the day of `now`,
    /// oldest first. Stretches crossing midnight are split between the days.
    public static func summaries(of records: [ActivityRecord], days: Int, now: Date,
                                 calendar: Calendar = .current) -> [DaySummary] {
        let today = calendar.startOfDay(for: now)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        return (0..<max(1, days)).reversed().map { back in
            let dayStart = calendar.date(byAdding: .day, value: -back, to: today)!
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            return summary(of: records, from: dayStart, to: dayEnd, date: formatter.string(from: dayStart))
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
