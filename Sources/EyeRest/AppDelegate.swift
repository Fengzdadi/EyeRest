import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var scheduler: BreakScheduler!
    private var statusMenu: StatusMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        scheduler = BreakScheduler()
        statusMenu = StatusMenu(scheduler: scheduler)
        scheduler.onUpdate = { [weak self] in self?.statusMenu.refresh() }
        scheduler.start()
    }
}
