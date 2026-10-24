import Foundation

/// What the app is doing right now, written to `status.json` for the MCP
/// server, which runs as a separate process.
public struct StatusSnapshot: Codable, Equatable, Sendable {
    /// "working", "waiting", "waitingForTyping", "away", "onBreak" or "paused".
    public var state: String
    /// Why a due break is waiting, when `state` is "waiting".
    public var waitingReason: String?
    /// When the next break is due, while working.
    public var nextBreakAt: Date?
    public var nextBreakIsLong: Bool
    /// When the current break ends, while on a break.
    public var breakEndsAt: Date?
    public var isLongBreak: Bool
    /// When a pause ends; nil while paused means until the user resumes.
    public var pausedUntil: Date?
    public var workMinutes: Int
    public var breakSeconds: Int
    /// 0 when long breaks are off.
    public var longBreakEvery: Int
    public var longBreakMinutes: Int
    /// The app's process, to tell whether it's still running.
    public var pid: Int32
    public var updatedAt: Date

    public init(state: String, waitingReason: String? = nil, nextBreakAt: Date? = nil, nextBreakIsLong: Bool = false,
                breakEndsAt: Date? = nil, isLongBreak: Bool = false, pausedUntil: Date? = nil,
                workMinutes: Int, breakSeconds: Int, longBreakEvery: Int, longBreakMinutes: Int,
                pid: Int32, updatedAt: Date) {
        self.state = state
        self.waitingReason = waitingReason
        self.nextBreakAt = nextBreakAt
        self.nextBreakIsLong = nextBreakIsLong
        self.breakEndsAt = breakEndsAt
        self.isLongBreak = isLongBreak
        self.pausedUntil = pausedUntil
        self.workMinutes = workMinutes
        self.breakSeconds = breakSeconds
        self.longBreakEvery = longBreakEvery
        self.longBreakMinutes = longBreakMinutes
        self.pid = pid
        self.updatedAt = updatedAt
    }
}

/// The files EyeRest keeps in its data folder: `activity.jsonl`, one
/// `ActivityRecord` per line, and `status.json`. Nothing leaves the Mac.
public struct ActivityStore: Sendable {
    public let directory: URL

    public var activityURL: URL { directory.appendingPathComponent("activity.jsonl") }
    public var statusURL: URL { directory.appendingPathComponent("status.json") }

    /// `~/Library/Application Support/EyeRest`, or `$EYEREST_DATA_DIR` if set.
    public static var defaultDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["EYEREST_DATA_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("EyeRest", isDirectory: true)
    }

    public init(directory: URL = ActivityStore.defaultDirectory) {
        self.directory = directory
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: Activity log

    public func append(_ records: [ActivityRecord]) throws {
        guard !records.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.lines(records)
        if let handle = try? FileHandle(forWritingTo: activityURL) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: activityURL)
        }
    }

    /// All records, skipping lines that don't parse (such as a line still
    /// being written by the app).
    public func records() -> [ActivityRecord] {
        guard let data = try? Data(contentsOf: activityURL) else { return [] }
        let decoder = Self.decoder()
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(ActivityRecord.self, from: Data($0)) }
    }

    /// Drops records older than `days` days before `now` and merges each
    /// stretch's chunks into one record, rewriting the file only if that
    /// changes anything. Done daily, it keeps the log small and quick to read.
    public func compact(keepingDays days: Int, now: Date) throws {
        let cutoff = now.addingTimeInterval(-TimeInterval(days) * 86_400)
        let all = records()
        let kept = ActivityRecord.mergingChunks(all.filter { ($0.end ?? $0.start) >= cutoff })
        guard kept.count < all.count else { return }
        try Self.lines(kept).write(to: activityURL, options: .atomic)
    }

    /// The records as JSON, one per line.
    private static func lines(_ records: [ActivityRecord]) throws -> Data {
        let encoder = Self.encoder()
        var data = Data()
        for record in records {
            data.append(try encoder.encode(record))
            data.append(0x0A)
        }
        return data
    }

    // MARK: Status

    public func writeStatus(_ status: StatusSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder().encode(status).write(to: statusURL, options: .atomic)
    }

    public func status() -> StatusSnapshot? {
        guard let data = try? Data(contentsOf: statusURL) else { return nil }
        return try? Self.decoder().decode(StatusSnapshot.self, from: data)
    }
}
