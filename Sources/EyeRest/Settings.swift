import EyeRestCore
import Foundation

/// User preferences, stored in UserDefaults.
///
/// Any value can be overridden for one run from the command line, e.g.
/// `EyeRest -workSeconds 15 -breakSeconds 5`.
enum Settings {
    private static let defaults = UserDefaults.standard

    static func registerDefaults() {
        defaults.register(defaults: [
            "workSeconds": 20 * 60,
            "breakSeconds": 20,
            "postponeSeconds": 5 * 60,
            "idleResetSeconds": 2 * 60,
            "graceSeconds": 60,
            "headsUpSeconds": 10,
            "typingPauseSeconds": 2.0,
            "maxTypingWaitSeconds": 30,
            "longBreakEvery": 3,
            "longBreakSeconds": 5 * 60,
            "playSound": true,
            "holdDuringCalls": true,
            "holdDuringSlideshows": true,
            "holdDuringMeetings": false,
            "showTimer": true,
        ])
    }

    /// Time between breaks.
    static var workSeconds: Int {
        get { defaults.integer(forKey: "workSeconds") }
        set { defaults.set(newValue, forKey: "workSeconds") }
    }

    /// Length of each break.
    static var breakSeconds: Int {
        get { defaults.integer(forKey: "breakSeconds") }
        set { defaults.set(newValue, forKey: "breakSeconds") }
    }

    /// How long "Postpone" pushes a break back.
    static var postponeSeconds: Int {
        defaults.integer(forKey: "postponeSeconds")
    }

    /// No input for this long counts as a natural break and resets the timer.
    static var idleResetSeconds: Int {
        defaults.integer(forKey: "idleResetSeconds")
    }

    /// After a held break is released (the call or meeting ended), wait this
    /// long before starting it.
    static var graceSeconds: Int {
        defaults.integer(forKey: "graceSeconds")
    }

    /// Show a small heads-up this many seconds before a break. 0 turns it off.
    static var headsUpSeconds: Int {
        defaults.integer(forKey: "headsUpSeconds")
    }

    /// A due break waits until there has been no key press for this long...
    static var typingPauseSeconds: TimeInterval {
        defaults.double(forKey: "typingPauseSeconds")
    }

    /// ...but starts anyway once it has waited this long.
    static var maxTypingWaitSeconds: Int {
        defaults.integer(forKey: "maxTypingWaitSeconds")
    }

    /// Every this many breaks, the break is a long one. 0 turns long breaks off.
    static var longBreakEvery: Int {
        get { defaults.integer(forKey: "longBreakEvery") }
        set { defaults.set(newValue, forKey: "longBreakEvery") }
    }

    static var longBreakSeconds: Int {
        get { defaults.integer(forKey: "longBreakSeconds") }
        set { defaults.set(newValue, forKey: "longBreakSeconds") }
    }

    /// Play a sound when a break ends.
    static var playSound: Bool {
        get { defaults.bool(forKey: "playSound") }
        set { defaults.set(newValue, forKey: "playSound") }
    }

    /// The app's own language ("en", "zh-Hans"), or nil to follow the system.
    /// macOS reads it at launch, so a change takes effect after a relaunch.
    static var language: String? {
        get {
            guard let id = Bundle.main.bundleIdentifier else { return nil }
            return (defaults.persistentDomain(forName: id)?["AppleLanguages"] as? [String])?.first
        }
        set {
            if let newValue {
                defaults.set([newValue], forKey: "AppleLanguages")
            } else {
                defaults.removeObject(forKey: "AppleLanguages")
            }
        }
    }

    /// Hold a due break while the camera or microphone is in use.
    static var holdDuringCalls: Bool {
        get { defaults.bool(forKey: "holdDuringCalls") }
        set { defaults.set(newValue, forKey: "holdDuringCalls") }
    }

    /// Hold a due break while Keynote or PowerPoint is showing a slideshow.
    static var holdDuringSlideshows: Bool {
        get { defaults.bool(forKey: "holdDuringSlideshows") }
        set { defaults.set(newValue, forKey: "holdDuringSlideshows") }
    }

    /// Hold a due break during calendar meetings. Needs calendar access.
    static var holdDuringMeetings: Bool {
        get { defaults.bool(forKey: "holdDuringMeetings") }
        set { defaults.set(newValue, forKey: "holdDuringMeetings") }
    }

    /// Show the countdown next to the menu bar icon.
    static var showTimer: Bool {
        get { defaults.bool(forKey: "showTimer") }
        set { defaults.set(newValue, forKey: "showTimer") }
    }
}

extension BreakTimer.Config {
    /// The timer's durations from the current settings.
    static var current: Self {
        var config = Self()
        config.workSeconds = TimeInterval(Settings.workSeconds)
        config.breakSeconds = TimeInterval(Settings.breakSeconds)
        config.postponeSeconds = TimeInterval(Settings.postponeSeconds)
        config.idleResetSeconds = TimeInterval(Settings.idleResetSeconds)
        config.graceSeconds = TimeInterval(Settings.graceSeconds)
        config.headsUpSeconds = TimeInterval(Settings.headsUpSeconds)
        config.typingPauseSeconds = Settings.typingPauseSeconds
        config.maxTypingWaitSeconds = TimeInterval(Settings.maxTypingWaitSeconds)
        config.longBreakEvery = Settings.longBreakEvery
        config.longBreakSeconds = TimeInterval(Settings.longBreakSeconds)
        return config
    }
}
