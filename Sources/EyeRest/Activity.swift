import AppKit
import CoreAudio
import CoreGraphics
import CoreMediaIO
import EyeRestCore
import Foundation
import IOKit.pwr_mgt

/// Read-only checks on what the user and other apps are doing. None of these
/// need camera, microphone or accessibility permission.
enum Activity {
    /// Seconds since the last keyboard, mouse or trackpad event.
    static func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// Seconds since the last key press.
    static func secondsSinceKeyPress() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
    }

    /// The bundle identifier of the app in front. NSWorkspace keeps it up to
    /// date as apps activate, so asking every second is cheap.
    @MainActor
    static func frontmostApp() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// True when some app (usually a video player) is keeping the display awake.
    static func isDisplayHeldAwake() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let dict = status?.takeRetainedValue() as? [String: Int] else { return false }
        return (dict["PreventUserIdleDisplaySleep"] ?? 0) > 0
    }

    /// A short reason when a call looks to be in progress, otherwise nil. It
    /// names the app using the microphone, so one that keeps it open is easy to
    /// spot; macOS doesn't say which app is using the camera.
    @MainActor
    static func callInProgress() -> String? {
        if isCameraInUse() { return String(localized: "camera in use") }
        guard let pid = microphoneUser() else { return nil }
        if let app = appName(of: pid) { return String(localized: "microphone in use by \(app)") }
        return String(localized: "microphone in use")
    }

    // MARK: Slideshows

    private static let slideshowApps = [
        "com.apple.iWork.Keynote": "Keynote",
        "com.microsoft.Powerpoint": "PowerPoint",
    ]

    /// The name of a presentation app that is showing a slideshow, otherwise nil.
    ///
    /// A slideshow is a window from one of these apps that fills a display
    /// (Keynote plays above normal windows, PowerPoint at the normal level).
    /// Editing a deck in native full screen looks the same, so it counts too.
    @MainActor
    static func slideshowApp() -> String? {
        let apps = NSWorkspace.shared.runningApplications.filter { slideshowApps[$0.bundleIdentifier ?? ""] != nil }
        guard !apps.isEmpty else { return nil }
        let windows = onScreenWindows()
        let displays = displayBounds()
        let showing = apps.first { app in
            DisplayFill.fillsDisplay(windows: windows[Int(app.processIdentifier)] ?? [], displays: displays)
        }
        return showing.flatMap { slideshowApps[$0.bundleIdentifier ?? ""] }
    }

    // MARK: Full-screen videos and games

    /// Apps that call themselves games but aren't one: the Games app that
    /// comes with macOS 26 is a library and launcher.
    private static let notGames: Set<String> = ["com.apple.games"]

    /// Display assertions taken for something other than a video: a web page
    /// keeping the screen on (Screen Wake Lock) and a keep-awake extension in
    /// Chrome, and OBS while it records or streams.
    private static let notVideos: Set<String> = ["Blink Wake Lock", "PowerAPI", "OBS Video/audio"]

    /// A short reason when the app in front fills a display and is playing a
    /// video or is a game, otherwise nil. Keynote and PowerPoint are left to the
    /// slideshow check, which has its own setting.
    @MainActor
    static func fullScreenVideoOrGame() -> String? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              slideshowApps[front.bundleIdentifier ?? ""] == nil else { return nil }
        let pid = front.processIdentifier
        let name = front.localizedName ?? front.bundleIdentifier ?? ""
        // The cheap checks first, so most of the time no window list is read.
        if isGame(front) {
            return fillsDisplay(pid: pid) ? String(localized: "playing \(name) in full screen") : nil
        }
        if keepsDisplayAwake(pid: pid), fillsDisplay(pid: pid) {
            return String(localized: "full-screen video in \(name)")
        }
        return nil
    }

    /// Whether the app calls itself a game in its Info.plist: the games
    /// category or one of its kinds, such as board games. macOS goes by the same
    /// category to turn on Game Mode. The Info.plist is read afresh each time,
    /// since `Bundle` keeps the first one it read until EyeRest quits.
    private static func isGame(_ app: NSRunningApplication) -> Bool {
        guard let url = app.bundleURL, !notGames.contains(app.bundleIdentifier ?? ""),
              let info = CFBundleCopyInfoDictionaryInDirectory(url as CFURL) as? [String: Any],
              let category = info["LSApplicationCategoryType"] as? String
        else { return false }
        return category == "public.app-category.games"
            || (category.hasPrefix("public.app-category.") && category.hasSuffix("-games"))
    }

    /// Whether the process keeps the display awake, as video players and
    /// browsers do while a video plays, itself or through a system service
    /// acting for it. Unlike `isDisplayHeldAwake()`, a tool like `caffeinate`
    /// or a video playing in another app doesn't count.
    private static func keepsDisplayAwake(pid: pid_t) -> Bool {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
              let processes = byProcess?.takeRetainedValue() as? [Int: [[String: Any]]] else { return false }
        return processes.contains { owner, assertions in
            assertions.contains { assertion in
                // AssertionTrueType gives an old type, such as NoDisplaySleepAssertion,
                // its current name.
                (assertion["AssertionTrueType"] ?? assertion["AssertType"]) as? String == "PreventUserIdleDisplaySleep"
                    && assertion["AssertLevel"] as? Int == Int(kIOPMAssertionLevelOn)
                    && !notVideos.contains(assertion["AssertName"] as? String ?? "")
                    && (owner == Int(pid) || assertion["AssertionOnBehalfOfPID"] as? Int == Int(pid))
            }
        }
    }

    /// Whether one of the process's windows fills a display (see `DisplayFill`).
    private static func fillsDisplay(pid: pid_t) -> Bool {
        DisplayFill.fillsDisplay(windows: onScreenWindows()[Int(pid)] ?? [], displays: displayBounds())
    }

    /// The bounds of the windows on screen, by the process that owns them.
    /// Bounds and owners can be read without screen recording access.
    private static func onScreenWindows() -> [Int: [CGRect]] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [:] }
        var windows: [Int: [CGRect]] = [:]
        for window in list {
            guard let owner = window[kCGWindowOwnerPID as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { continue }
            windows[owner, default: []].append(rect)
        }
        return windows
    }

    /// The bounds of each display, in the window list's coordinates.
    private static func displayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return displays.prefix(Int(count)).map(CGDisplayBounds)
    }

    // MARK: Camera

    static func isCameraInUse() -> Bool {
        var address = cmioAddress(kCMIOHardwarePropertyDevices)
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return false }

        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else { return false }

        return devices.contains { device in
            var running: UInt32 = 0
            var address = cmioAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
            let status = CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running)
            return status == noErr && running != 0
        }
    }

    private static func cmioAddress(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    // MARK: Microphone

    /// The process recording from the microphone, if any. Asking Core Audio per
    /// process (rather than per device) avoids false positives from headsets
    /// like AirPods, which are one device for both playback and recording.
    static func microphoneUser() -> pid_t? {
        var address = audioAddress(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }

        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return nil }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        return processes.lazy
            .filter { audioProperty($0, kAudioProcessPropertyIsRunningInput, default: UInt32(0)) != 0 }
            .map { audioProperty($0, kAudioProcessPropertyPID, default: pid_t(0)) }
            .first { $0 != ownPID }
    }

    /// What to call the app a process belongs to. Core Audio often sees a
    /// helper, such as a browser's audio service, which is named after the app
    /// bundle it ships in; a WebKit media process is named after the app it
    /// works for ("Mail Graphics and Media").
    @MainActor
    static func appName(of pid: pid_t) -> String? {
        if let path = processString(size: 4 * Int(MAXPATHLEN), { proc_pidpath(pid, $0, $1) }),
           let app = outermostApp(in: path) {
            let running = NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == app.path }
            return running?.localizedName ?? app.deletingPathExtension().lastPathComponent
        }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
            ?? processString(size: 256) { proc_name(pid, $0, $1) }
    }

    /// The outermost app bundle in `path`, if any.
    private static func outermostApp(in path: String) -> URL? {
        let components = URL(fileURLWithPath: path).pathComponents
        guard let end = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: Array(components[...end])))
    }

    /// A string that a libproc call writes into a buffer, or nil if it fails.
    private static func processString(size: Int, _ call: (UnsafeMutablePointer<CChar>, UInt32) -> Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: size)
        return buffer.withUnsafeMutableBufferPointer { buffer in
            call(buffer.baseAddress!, UInt32(buffer.count)) > 0 ? String(cString: buffer.baseAddress!) : nil
        }
    }

    private static func audioAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static func audioProperty<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, default fallback: T) -> T {
        var address = audioAddress(selector)
        var value = fallback
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : fallback
    }
}
