import AppKit
import EyeRestCore

/// The real `ActivityProbe`: reads the Mac's state and applies the user's
/// "Hold Breaks During" settings.
@MainActor
final class LiveProbe: ActivityProbe {
    private let calendar: MeetingCalendar
    private(set) var isScreenLocked = false

    init(calendar: MeetingCalendar) {
        self.calendar = calendar
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isScreenLocked = true }
        }
        center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isScreenLocked = false }
        }
    }

    func idleSeconds() -> TimeInterval { Activity.idleSeconds() }
    func secondsSinceKeyPress() -> TimeInterval { Activity.secondsSinceKeyPress() }
    func isDisplayHeldAwake() -> Bool { Activity.isDisplayHeldAwake() }

    func busyReason() -> String? {
        if Settings.holdDuringCalls, let reason = Activity.callInProgress() {
            return reason
        }
        if Settings.holdDuringSlideshows, let app = Activity.slideshowApp() {
            return "\(app) slideshow"
        }
        if Settings.holdDuringMeetings, let title = calendar.currentMeeting() {
            let short = title.count > 30 ? title.prefix(29) + "…" : Substring(title)
            return "meeting: \(short)"
        }
        return nil
    }
}
