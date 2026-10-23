import AppKit
import EyeRestCore
import ServiceManagement

/// The menu bar icon, countdown and menu.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let scheduler: BreakScheduler
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var isMenuOpen = false
    /// What the menu bar button shows now, to skip redraws when nothing changed.
    private var shownSymbol = ""
    private var shownTitle = ""

    /// Launch at login and the language setting only work when running from a
    /// real .app bundle.
    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    init(scheduler: BreakScheduler) {
        self.scheduler = scheduler
        super.init()
        statusLine.isEnabled = false
        menu.delegate = self
        item.menu = menu
        item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        refresh()
    }

    /// Called every second. The countdown usually shows whole minutes, so most
    /// calls change nothing; updating the button anyway costs a menu bar redraw
    /// (on macOS 26, a round trip to Control Center, which draws status items).
    func refresh() {
        if isMenuOpen { statusLine.title = statusText() }

        guard let button = item.button else { return }
        let symbol: String
        var title = ""
        switch scheduler.state {
        case .paused: symbol = "eye.slash"
        case .onBreak: symbol = "eye.fill"
        case .waitingForTyping: symbol = "eye"
        case .waiting: symbol = "eye.trianglebadge.exclamationmark"
        case .working, .away:
            symbol = "eye"
            if Settings.showTimer { title = " " + shortTime(scheduler.remaining) }
        }
        if symbol != shownSymbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "EyeRest")
            shownSymbol = symbol
        }
        if title != shownTitle {
            button.title = title
            shownTitle = title
        }
    }

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) { isMenuOpen = true }
    func menuDidClose(_ menu: NSMenu) { isMenuOpen = false }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        statusLine.title = statusText()
        menu.addItem(statusLine)
        menu.addItem(.separator())

        if case .paused = scheduler.state {
            menu.addItem(actionItem(String(localized: "Resume"), #selector(resume)))
        } else {
            menu.addItem(actionItem(String(localized: "Take a Break Now"), #selector(takeBreakNow)))
            let pause = NSMenuItem(title: String(localized: "Pause"), action: nil, keyEquivalent: "")
            pause.submenu = NSMenu()
            pause.submenu?.addItem(actionItem(String(localized: "For 30 Minutes"), #selector(pauseFor(_:)), tag: 30 * 60))
            pause.submenu?.addItem(actionItem(String(localized: "For 1 Hour"), #selector(pauseFor(_:)), tag: 60 * 60))
            pause.submenu?.addItem(actionItem(String(localized: "Until I Resume"), #selector(pauseFor(_:)), tag: 0))
            menu.addItem(pause)
        }

        menu.addItem(.separator())
        menu.addItem(choiceMenu(
            String(localized: "Break Every"),
            options: [20 * 60, 30 * 60, 45 * 60, 60 * 60],
            current: Settings.workSeconds,
            label: { String(localized: "\($0 / 60) minutes") },
            action: #selector(setWorkInterval(_:))))
        menu.addItem(choiceMenu(
            String(localized: "Break Length"),
            options: [20, 30, 60],
            current: Settings.breakSeconds,
            label: { String(localized: "\($0) seconds") },
            action: #selector(setBreakLength(_:))))
        menu.addItem(longBreakMenu())
        menu.addItem(holdMenu())

        menu.addItem(.separator())
        menu.addItem(toggleItem(String(localized: "Show Timer in Menu Bar"), Settings.showTimer, #selector(toggleShowTimer)))
        menu.addItem(toggleItem(String(localized: "Sound When a Break Ends"), Settings.playSound, #selector(togglePlaySound)))
        menu.addItem(languageMenu())
        let login = toggleItem(String(localized: "Launch at Login"), SMAppService.mainApp.status == .enabled, #selector(toggleLaunchAtLogin))
        if !isBundled { disable(login) }
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(actionItem(String(localized: "Quit EyeRest"), #selector(quit), key: "q"))
    }

    private func statusText() -> String {
        switch scheduler.state {
        case .working:
            let time = clockTime(scheduler.remaining)
            return scheduler.nextBreakIsLong
                ? String(localized: "Next long break in \(time)")
                : String(localized: "Next break in \(time)")
        case .waiting(let reason): return String(localized: "Break due, waiting (\(reason))")
        case .away: return String(localized: "Away, timer restarts when you're back")
        case .waitingForTyping: return String(localized: "Break when you pause typing")
        case .onBreak:
            return scheduler.isLongBreak ? String(localized: "On a long break") : String(localized: "On a break")
        case .paused(nil): return String(localized: "Paused")
        case .paused(let until?):
            let time = until.formatted(date: .omitted, time: .shortened)
            return String(localized: "Paused until \(time)")
        }
    }

    // MARK: Actions

    @objc private func takeBreakNow() { scheduler.takeBreakNow() }
    @objc private func resume() { scheduler.resume() }

    @objc private func pauseFor(_ sender: NSMenuItem) {
        scheduler.pause(for: sender.tag == 0 ? nil : TimeInterval(sender.tag))
    }

    @objc private func setWorkInterval(_ sender: NSMenuItem) {
        Settings.workSeconds = sender.tag
        scheduler.restartWorkTimer()
    }

    @objc private func setBreakLength(_ sender: NSMenuItem) {
        Settings.breakSeconds = sender.tag
    }

    @objc private func setLongBreakEvery(_ sender: NSMenuItem) {
        Settings.longBreakEvery = sender.tag
    }

    @objc private func setLongBreakLength(_ sender: NSMenuItem) {
        Settings.longBreakSeconds = sender.tag
    }

    @objc private func toggleHoldDuringCalls() {
        Settings.holdDuringCalls.toggle()
    }

    @objc private func toggleHoldDuringSlideshows() {
        Settings.holdDuringSlideshows.toggle()
    }

    /// Turning this on asks for calendar access the first time.
    @objc private func toggleHoldDuringMeetings() {
        if Settings.holdDuringMeetings {
            Settings.holdDuringMeetings = false
            return
        }
        let calendar = scheduler.calendar
        if calendar.hasAccess {
            Settings.holdDuringMeetings = true
            return
        }
        Task {
            if await calendar.requestAccess() {
                Settings.holdDuringMeetings = true
            } else {
                let alert = NSAlert()
                alert.messageText = String(localized: "EyeRest can't read your calendar")
                alert.informativeText = String(localized: "Allow access in System Settings > Privacy & Security > Calendars, then turn this on again.")
                alert.runModal()
            }
        }
    }

    @objc private func toggleShowTimer() {
        Settings.showTimer.toggle()
        refresh()
    }

    @objc private func togglePlaySound() {
        Settings.playSound.toggle()
    }

    /// The menu item's tag indexes `languages`.
    @objc private func setLanguage(_ sender: NSMenuItem) {
        let code = Self.languages[sender.tag].code
        guard code != Settings.language else { return }
        Settings.language = code
        relaunch()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    /// The language is read at launch, so start a fresh copy of the app once
    /// this one has quit.
    private func relaunch() {
        let reopen = Process()
        reopen.executableURL = URL(fileURLWithPath: "/bin/sh")
        reopen.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? reopen.run()
        NSApp.terminate(nil)
    }

    // MARK: Submenus

    /// "Hold Breaks During" submenu: the things that make a due break wait.
    private func holdMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: String(localized: "Hold Breaks During"), action: nil, keyEquivalent: "")
        parent.submenu = NSMenu()
        parent.submenu?.addItem(toggleItem(String(localized: "Calls (Camera or Mic in Use)"), Settings.holdDuringCalls, #selector(toggleHoldDuringCalls)))
        parent.submenu?.addItem(toggleItem(String(localized: "Keynote and PowerPoint Slideshows"), Settings.holdDuringSlideshows, #selector(toggleHoldDuringSlideshows)))
        let meetings = toggleItem(
            String(localized: "Calendar Meetings"),
            Settings.holdDuringMeetings && scheduler.calendar.hasAccess,
            #selector(toggleHoldDuringMeetings))
        if !scheduler.calendar.canRequestAccess { disable(meetings) }
        parent.submenu?.addItem(meetings)
        return parent
    }

    /// How often long breaks come (shown in minutes, stored as every Nth break)
    /// and how long they last.
    private func longBreakMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: String(localized: "Long Breaks"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let workMinutes = Settings.workSeconds / 60
        let every = Settings.longBreakEvery
        let everyOptions = [0, 2, 3, 4]
        for n in everyOptions.contains(every) ? everyOptions : (everyOptions + [every]).sorted() {
            let title = n == 0 ? String(localized: "Off") : String(localized: "Every \(n * workMinutes) Minutes")
            let item = actionItem(title, #selector(setLongBreakEvery(_:)), tag: n)
            item.state = n == every ? .on : .off
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let length = Settings.longBreakSeconds
        let lengthOptions = [5 * 60, 10 * 60]
        for seconds in lengthOptions.contains(length) ? lengthOptions : (lengthOptions + [length]).sorted() {
            let item = actionItem(String(localized: "Lasting \(seconds / 60) Minutes"), #selector(setLongBreakLength(_:)), tag: seconds)
            item.state = seconds == length ? .on : .off
            if every == 0 { item.action = nil }
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    /// Language names are shown in their own language, as macOS does.
    private static let languages: [(code: String?, name: String)] = [
        (nil, String(localized: "System Default")),
        ("en", "English"),
        ("zh-Hans", "简体中文"),
    ]

    private func languageMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: String(localized: "Language"), action: nil, keyEquivalent: "")
        parent.submenu = NSMenu()
        for (index, language) in Self.languages.enumerated() {
            let item = actionItem(language.name, #selector(setLanguage(_:)), tag: index)
            item.state = language.code == Settings.language ? .on : .off
            parent.submenu?.addItem(item)
        }
        if !isBundled { disable(parent) }
        return parent
    }

    // MARK: Helpers

    private func actionItem(_ title: String, _ action: Selector, tag: Int = 0, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.tag = tag
        return item
    }

    private func toggleItem(_ title: String, _ isOn: Bool, _ action: Selector) -> NSMenuItem {
        let item = actionItem(title, action)
        item.state = isOn ? .on : .off
        return item
    }

    private func disable(_ item: NSMenuItem) {
        item.action = nil
        item.submenu = nil
        item.toolTip = String(localized: "Build the .app with `make app` to enable this.")
    }

    /// A submenu of checkable options. A custom value set from the command line
    /// is listed too, so the current setting is always visible.
    private func choiceMenu(_ title: String, options: [Int], current: Int, label: (Int) -> String, action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = NSMenu()
        let values = options.contains(current) ? options : (options + [current]).sorted()
        for value in values {
            let item = actionItem(label(value), action, tag: value)
            item.state = value == current ? .on : .off
            parent.submenu?.addItem(item)
        }
        return parent
    }

    /// "18m", or "45s" in the last minute.
    private func shortTime(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return s >= 60 ? "\((s + 59) / 60)m" : "\(s)s"
    }

    /// "18:32"
    private func clockTime(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
