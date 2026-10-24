import AppKit
import CoreAudio
import CoreGraphics
import CoreMediaIO
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
    /// A slideshow is a window from one of these apps that covers a whole
    /// display (Keynote plays above normal windows, PowerPoint at the normal
    /// level). Editing a deck in native full screen looks the same, so it counts
    /// too. Window bounds and owners are readable without screen recording access.
    @MainActor
    static func slideshowApp() -> String? {
        let apps = NSWorkspace.shared.runningApplications.filter { slideshowApps[$0.bundleIdentifier ?? ""] != nil }
        guard !apps.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        let screenSizes = NSScreen.screens.map(\.frame.size)
        for app in apps {
            let pid = Int(app.processIdentifier)
            let coversScreen = windows.contains { window in
                guard window[kCGWindowOwnerPID as String] as? Int == pid,
                      let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                      let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
                return screenSizes.contains { abs($0.width - rect.width) < 1 && abs($0.height - rect.height) < 1 }
            }
            if coversScreen { return slideshowApps[app.bundleIdentifier ?? ""] }
        }
        return nil
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
