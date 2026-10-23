import EventKit

/// Finds a meeting in the user's calendars that is happening right now.
@MainActor
final class MeetingCalendar {
    private let store = EKEventStore()
    private var current: String?
    private var lastRefresh = Date.distantPast

    /// Calendar access can only be requested from the .app, which carries the
    /// usage description macOS shows in the permission prompt.
    var canRequestAccess: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil
    }

    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// The title of a meeting in progress, otherwise nil. Re-reads the
    /// calendars at most every 30 seconds.
    func currentMeeting() -> String? {
        guard hasAccess else { return nil }
        if Date().timeIntervalSince(lastRefresh) > 30 {
            lastRefresh = Date()
            let now = Date()
            let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(1), calendars: nil)
            current = store.events(matching: predicate).first(where: Self.isMeeting).map { $0.title ?? "Untitled" }
        }
        return current
    }

    private static let videoLinkHosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "facetime.apple.com", "meeting.tencent.com", "voovmeeting.com",
    ]

    /// A timed event you haven't declined that either has other attendees or a
    /// video call link. Plain blocks of time ("Focus", "Lunch") don't count.
    private static func isMeeting(_ event: EKEvent) -> Bool {
        guard !event.isAllDay, event.status != .canceled, event.availability != .free else { return false }
        if let me = event.attendees?.first(where: \.isCurrentUser), me.participantStatus == .declined {
            return false
        }
        if event.hasAttendees { return true }
        let text = [event.url?.absoluteString, event.location, event.notes]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return videoLinkHosts.contains { text.contains($0) }
    }
}
