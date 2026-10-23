import AppKit
import EyeRestCore
import SwiftUI

/// A small pill at the top of the screen in the seconds before a break. It
/// never takes keyboard focus, so typing carries on into the user's app.
@MainActor
final class HeadsUp {
    var onStartNow: (() -> Void)?
    var onPostpone: (() -> Void)?

    private var panel: NSPanel?
    private let size = NSSize(width: 410, height: 48)

    var isShown: Bool { panel != nil }

    func show(scheduler: BreakScheduler) {
        guard panel == nil, let screen = NSScreen.underMouse else { return }

        let visible = screen.visibleFrame
        let frame = NSRect(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 10,
            width: size.width,
            height: size.height)

        let panel = HeadsUpPanel(contentRect: frame)
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        // A mask image, unlike a layer corner radius, also shapes the window shadow.
        let radius = size.height / 2
        background.maskImage = NSImage(size: size, flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }

        let view = HeadsUpView(
            scheduler: scheduler,
            onStartNow: { [weak self] in self?.onStartNow?() },
            onPostpone: { [weak self] in self?.onPostpone?() })
        let hosting = FirstClickHostingView(rootView: view)
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)

        panel.contentView = background
        panel.fadeIn(duration: 0.3)
        panel.invalidateShadow()
        self.panel = panel
    }

    func hide() {
        panel?.fadeOut(duration: 0.2)
        panel = nil
    }
}

private final class HeadsUpPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    // Never steal keystrokes from the app the user is typing in.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets a click on a button work straight away, although the panel is never key.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct HeadsUpView: View {
    @ObservedObject var scheduler: BreakScheduler
    let onStartNow: () -> Void
    let onPostpone: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("Start Now", action: onStartNow)
            Button("+\(Settings.postponeSeconds / 60) min", action: onPostpone)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var message: String {
        if scheduler.state == .waitingForTyping { return String(localized: "Break when you pause typing") }
        let seconds = Int(scheduler.remaining.rounded(.up))
        return scheduler.nextBreakIsLong
            ? String(localized: "Long break in \(seconds)s")
            : String(localized: "Eye break in \(seconds)s")
    }
}
