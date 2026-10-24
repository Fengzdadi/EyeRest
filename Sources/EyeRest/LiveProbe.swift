import AppKit
import EyeRestCore

/// The real `ActivityProbe`: reads the Mac's state and applies the user's
/// "Hold Breaks During" settings.
@MainActor
final class LiveProbe: ActivityProbe {
    private let calendar: MeetingCalendar
    private(set) var isScreenLocked = false
    /// The call and slideshow checks are slow (the microphone check asks Core
    /// Audio about every process that has used audio) and a due break asks
    /// every second, so their answers are reused for a few seconds.
    private var calls = CachedCheck<String?>(lifetime: .seconds(5))
    private var slideshows = CachedCheck<String?>(lifetime: .seconds(5))

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

    /// Only while calls hold breaks, so turning that off (say, for an app that
    /// keeps the microphone open) also stops a call keeping you at the screen.
    func isInCall() -> Bool {
        Settings.holdDuringCalls && callReason() != nil
    }

    func busyReason() -> String? {
        if Settings.holdDuringCalls, let reason = callReason() {
            return reason
        }
        if Settings.holdDuringSlideshows, let app = slideshowApp() {
            return String(localized: "\(app) slideshow")
        }
        if Settings.holdDuringMeetings, let title = calendar.currentMeeting() {
            let short = title.count > 30 ? String(title.prefix(29)) + "…" : title
            return String(localized: "meeting: \(short)")
        }
        return nil
    }

    private func callReason() -> String? { calls.value { Activity.callInProgress() } }
    private func slideshowApp() -> String? { slideshows.value { Activity.slideshowApp() } }
}
