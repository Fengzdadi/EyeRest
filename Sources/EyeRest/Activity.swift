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

    /// True when some app (usually a video player) is keeping the display awake.
    static func isDisplayHeldAwake() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let dict = status?.takeRetainedValue() as? [String: Int] else { return false }
        return (dict["PreventUserIdleDisplaySleep"] ?? 0) > 0
    }

    /// A short reason when a call looks to be in progress, otherwise nil.
    static func callInProgress() -> String? {
        if isCameraInUse() { return "camera in use" }
        if isMicrophoneInUse() { return "microphone in use" }
        return nil
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

    /// Asks Core Audio which processes are currently recording. Checking per
    /// process (rather than per device) avoids false positives from headsets like
    /// AirPods, which are one device for both playback and recording.
    static func isMicrophoneInUse() -> Bool {
        var address = audioAddress(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return false }

        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return false }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        return processes.contains { process in
            audioProperty(process, kAudioProcessPropertyIsRunningInput, default: UInt32(0)) != 0
                && audioProperty(process, kAudioProcessPropertyPID, default: pid_t(0)) != ownPID
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
