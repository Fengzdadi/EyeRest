import AppKit

extension NSScreen {
    /// The screen the mouse pointer is on, else the main screen. Nil when no
    /// display is attached (e.g. a closed laptop kept awake).
    static var underMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(mouse) } ?? main ?? screens.first
    }
}

extension NSWindow {
    func fadeIn(duration: TimeInterval) {
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            animator().alphaValue = 1
        }
    }

    func fadeOut(duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}
