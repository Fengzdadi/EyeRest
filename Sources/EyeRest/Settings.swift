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
