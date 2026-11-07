import AppKit
import EyeRestCore

/// The real `ActivityProbe`: reads the Mac's state and applies the user's
/// "Hold Breaks During" settings.
@MainActor
final class LiveProbe: ActivityProbe {
    private let calendar: MeetingCalendar
    private(set) var isScreenLocked = false
    /// The call, slideshow and full-screen checks are slow (the microphone
    /// check asks Core Audio about every process that has used audio) and a due
    /// break asks every second, so their answers are reused for a few seconds.
    private var calls = CachedCheck<String?>(lifetime: .seconds(5))
    private var slideshows = CachedCheck<String?>(lifetime: .seconds(5))
    private var fullScreen = CachedCheck<String?>(lifetime: .seconds(5))

    private enum Hold: CaseIterable {
        case call, slideshow, fullScreen, meeting
    }
    /// What held the break last time. It's asked first, so a long hold, say
    /// for a film, doesn't keep running the slower checks before it.
    private var lastHold: Hold?

    init(calendar: MeetingCalendar) {
        self.calendar = calendar
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isScreenLocked = true }
        }
        center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isScreenLocked = false }
        }
        // Switching apps or Spaces (as entering and leaving full screen does)
        // changes what's on screen, so look again rather than reuse an answer.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.slideshows.reset()
                    self?.fullScreen.reset()
                }
            }
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
        let order = lastHold.map { last in [last] + Hold.allCases.filter { $0 != last } } ?? Hold.allCases
        for hold in order {
            if let reason = reason(for: hold) {
                lastHold = hold
                return reason
            }
        }
        lastHold = nil
        return nil
    }

    private func reason(for hold: Hold) -> String? {
        switch hold {
        case .call:
            guard Settings.holdDuringCalls else { return nil }
            return callReason()
        case .slideshow:
            guard Settings.holdDuringSlideshows, let app = slideshowApp() else { return nil }
            return String(localized: "\(app) slideshow")
        case .fullScreen:
            guard Settings.holdDuringFullScreen else { return nil }
            return fullScreenReason()
        case .meeting:
            guard Settings.holdDuringMeetings, let title = calendar.currentMeeting() else { return nil }
            let short = title.count > 30 ? String(title.prefix(29)) + "…" : title
            return String(localized: "meeting: \(short)")
        }
    }

    private func callReason() -> String? { calls.value { Activity.callInProgress() } }
    private func slideshowApp() -> String? { slideshows.value { Activity.slideshowApp() } }
    private func fullScreenReason() -> String? { fullScreen.value { Activity.fullScreenVideoOrGame() } }
}
