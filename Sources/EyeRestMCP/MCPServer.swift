import EyeRestCore
import Foundation

/// A small MCP server: JSON-RPC 2.0 messages, one per line, over stdio. It
/// offers read-only tools over the files EyeRest writes; it never changes them.
public struct MCPServer {
    public let store: ActivityStore
    public var version: String
    public var now: () -> Date
    /// Whether the EyeRest app with this process ID is still running.
    public var isRunning: (Int32) -> Bool

    public init(store: ActivityStore, version: String,
                now: @escaping () -> Date = Date.init,
                isRunning: @escaping (Int32) -> Bool = { kill($0, 0) == 0 }) {
        self.store = store
        self.version = version
        self.now = now
        self.isRunning = isRunning
    }

    /// Newest first. A client asking for another version gets the newest.
    static let protocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    static let instructions = """
        EyeRest is a break reminder on the user's Mac: every 20 minutes it asks them to look at \
        something 20 feet away for 20 seconds, with a longer stand-up break about every hour. \
        These tools show whether a break is coming up, how long the user has been at the screen \
        today and over recent days, and how they've kept up with breaks. Screen time is time with \
        recent keyboard or mouse input, or a video playing; it doesn't track which apps are used. \
        All data stays on this Mac.
        """

    // MARK: JSON-RPC

    /// Handles one incoming line. Returns the response line, or nil for a
    /// notification, which gets no response.
    public func handle(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        guard let id = message["id"] else { return nil }
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]

        let response: [String: Any]
        switch method {
        case "initialize":
            response = ["result": initialize(params)]
        case "ping":
            response = ["result": [String: Any]()]
        case "tools/list":
            response = ["result": ["tools": Self.tools]]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            if let result = callTool(name, arguments) {
                response = ["result": result]
            } else {
                response = ["error": ["code": -32602, "message": "Unknown tool: \(name)"]]
            }
        default:
            response = ["error": ["code": -32601, "message": "Method not found: \(method)"]]
        }
        return encode(response.merging(["jsonrpc": "2.0", "id": id]) { $1 })
    }

    private func initialize(_ params: [String: Any]) -> [String: Any] {
        let requested = params["protocolVersion"] as? String ?? ""
        return [
            "protocolVersion": Self.protocolVersions.contains(requested) ? requested : Self.protocolVersions[0],
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": "eyerest", "title": "EyeRest", "version": version],
            "instructions": Self.instructions,
        ]
    }

    private func encode(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Tools

    static let tools: [[String: Any]] = [
        [
            "name": "get_status",
            "title": "Break status",
            "description": "What EyeRest is doing right now: whether the user is working, on a break, away or has paused reminders, and how long until the next break (and whether it's a long one).",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
        [
            "name": "get_today",
            "title": "Today's screen time and breaks",
            "description": "Today so far: time at the screen, the longest stretch without a break, and how many breaks the user finished, skipped or postponed.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
        [
            "name": "get_history",
            "title": "Screen time and breaks by day",
            "description": "One summary per day for recent days, oldest first: time at the screen, the longest stretch without a break, and breaks finished, skipped and postponed.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "days": [
                        "type": "integer", "minimum": 1, "maximum": 90, "default": 7,
                        "description": "How many days to include, ending today.",
                    ],
                ],
            ],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
    ]

    /// The tool's result, or nil if there's no such tool.
    private func callTool(_ name: String, _ arguments: [String: Any]) -> [String: Any]? {
        var output: [String: Any]
        switch name {
        case "get_status":
            output = status()
        case "get_today":
            let records = store.records()
            output = summary(DaySummary.summaries(of: records, days: 1, now: now())[0])
            output["trackingSince"] = trackingSince(records)
        case "get_history":
            let days = min(90, max(1, (arguments["days"] as? Int) ?? 7))
            let records = store.records()
            output = ["days": DaySummary.summaries(of: records, days: days, now: now()).map(summary)]
            output["trackingSince"] = trackingSince(records)
        default:
            return nil
        }
        return [
            "content": [["type": "text", "text": encode(output)]],
            "structuredContent": output,
            "isError": false,
        ]
    }

    private func status() -> [String: Any] {
        guard let status = store.status(), isRunning(status.pid) else {
            return ["running": false, "description": "EyeRest isn't running, so no breaks are being scheduled."]
        }
        let now = now()
        var out: [String: Any] = [
            "running": true,
            "state": status.state,
            "nextBreakIsLong": status.nextBreakIsLong,
            "settings": [
                "breakEveryMinutes": status.workMinutes,
                "breakSeconds": status.breakSeconds,
                "longBreakEveryNthBreak": status.longBreakEvery,
                "longBreakMinutes": status.longBreakMinutes,
            ],
        ]
        let kind = status.nextBreakIsLong ? "long break" : "break"
        switch status.state {
        case "working":
            let seconds = max(0, (status.nextBreakAt ?? now).timeIntervalSince(now))
            out["nextBreakInSeconds"] = Int(seconds)
            out["description"] = "Working. Next \(kind) in \(Self.duration(seconds))."
        case "waiting":
            out["waitingReason"] = status.waitingReason
            out["description"] = "A \(kind) is due but waiting because the user is busy (\(status.waitingReason ?? "busy"))."
        case "waitingForTyping":
            out["description"] = "A \(kind) is due and will start when the user pauses typing."
        case "away":
            out["description"] = "The user is away from the screen; the timer restarts when they're back."
        case "onBreak":
            let seconds = max(0, (status.breakEndsAt ?? now).timeIntervalSince(now))
            out["isLongBreak"] = status.isLongBreak
            out["breakEndsInSeconds"] = Int(seconds)
            out["description"] = "On a \(status.isLongBreak ? "long break" : "break"), ending in \(Self.duration(seconds))."
        case "paused":
            if let until = status.pausedUntil {
                out["pausedUntil"] = ISO8601DateFormatter().string(from: until)
                out["description"] = "Break reminders are paused for \(Self.duration(until.timeIntervalSince(now)))."
            } else {
                out["description"] = "Break reminders are paused until the user resumes them."
            }
        default:
            out["description"] = status.state
        }
        return out
    }

    private func summary(_ day: DaySummary) -> [String: Any] {
        [
            "date": day.date,
            "screenTime": Self.duration(day.screenSeconds),
            "screenSeconds": Int(day.screenSeconds),
            "longestStretch": Self.duration(day.longestStretchSeconds),
            "longestStretchSeconds": Int(day.longestStretchSeconds),
            "breaksFinished": day.breaksFinished,
            "longBreaksFinished": day.longBreaksFinished,
            "breaksSkipped": day.breaksSkipped,
            "breaksPostponed": day.breaksPostponed,
        ]
    }

    /// When the log starts, so a short history isn't mistaken for no screen time.
    private func trackingSince(_ records: [ActivityRecord]) -> String? {
        records.map(\.start).min().map { ISO8601DateFormatter().string(from: $0) }
    }

    /// "2h 05m", "12m", "45s".
    static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s >= 3600 { return String(format: "%dh %02dm", s / 3600, s % 3600 / 60) }
        if s >= 60 { return "\(s / 60)m" }
        return "\(s)s"
    }
}
