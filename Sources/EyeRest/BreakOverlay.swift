import AppKit
import SwiftUI
import os

private let log = Logger(subsystem: "io.github.fengzdadi.EyeRest", category: "overlay")

/// Full-screen break screen on every display.
@MainActor
final class BreakOverlay {
    var onSkip: (() -> Void)?
    var onPostpone: (() -> Void)?

    private var panels: [OverlayPanel] = []
    private var keyPanel: OverlayPanel?
    private var focusTimer: Timer?

    func show(scheduler: BreakScheduler) {
        guard panels.isEmpty else { return }

        for screen in NSScreen.screens {
            let panel = OverlayPanel(screen: screen)
            panel.onCancel = { [weak self] in self?.onSkip?() }

            let blur = NSVisualEffectView()
            blur.material = .fullScreenUI
            blur.blendingMode = .behindWindow
            blur.state = .active

            let view = BreakView(
                scheduler: scheduler,
                onSkip: { [weak self] in self?.onSkip?() },
                onPostpone: { [weak self] in self?.onPostpone?() })
            let hosting = NSHostingView(rootView: view)
            hosting.frame = blur.bounds
            hosting.autoresizingMask = [.width, .height]
            blur.addSubview(hosting)

            panel.contentView = blur
            panel.setFrame(screen.frame, display: false)
            panel.fadeIn(duration: 0.6)
            panels.append(panel)
        }

        // Take keyboard focus (for Esc) on the screen the mouse is on, without
        // activating the app, so focus returns to the user's app afterwards.
        let screen = NSScreen.underMouse
        keyPanel = panels.first { $0.frame == screen?.frame } ?? panels.first
        focusWhenTypingPauses()
    }

    func hide() {
        focusTimer?.invalidate()
        focusTimer = nil
        keyPanel = nil
        panels.forEach { $0.fadeOut(duration: 0.4) }
        panels = []
    }

    /// A break can start while the user is still typing (after the typing wait
    /// runs out). Taking focus then would swallow their keystrokes, so wait for
    /// a one-second pause; until then keys keep going to their app.
    private func focusWhenTypingPauses() {
        guard Activity.secondsSinceKeyPress() < 1 else {
            keyPanel?.makeKey()
            log.notice("break screen took keyboard focus")
            return
        }
        guard focusTimer == nil else { return }
        focusTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Activity.secondsSinceKeyPress() >= 1 else { return }
                self.focusTimer?.invalidate()
                self.focusTimer = nil
                self.keyPanel?.makeKey()
                log.notice("break screen took keyboard focus after typing paused")
            }
        }
    }
}

/// A borderless panel above everything, including full-screen apps, that can
/// take key focus without activating EyeRest.
private final class OverlayPanel: NSPanel {
    var onCancel: (() -> Void)?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private struct BreakView: View {
    @ObservedObject var scheduler: BreakScheduler
    let onSkip: () -> Void
    let onPostpone: () -> Void

    var body: some View {
        let total = max(1, scheduler.breakLength)
        let left = max(0, scheduler.remaining)
        let seconds = Int(left.rounded(.up))

        ZStack {
            Color.black.opacity(0.35)

            VStack(spacing: 32) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.15), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: left / total)
                        .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: left)
                    // Long breaks count down in minutes and seconds.
                    Text(verbatim: total >= 60 ? String(format: "%d:%02d", seconds / 60, seconds % 60) : "\(seconds)")
                        .font(.system(size: total >= 60 ? 52 : 64, weight: .light, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 180, height: 180)

                VStack(spacing: 10) {
                    (scheduler.isLongBreak ? Text("Time to stand up") : Text("Look at something 20 feet away"))
                        .font(.system(size: 30, weight: .semibold))
                    (scheduler.isLongBreak ? Text("Stretch, walk around and rest your eyes.") : Text("About 6 metres. Let your eyes relax."))
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }

                HStack(spacing: 12) {
                    // Not focusable, so a stray Space or Return can't press them.
                    Button("Postpone \(Settings.postponeSeconds / 60) min", action: onPostpone)
                        .focusable(false)
                    Button("Skip", action: onSkip)
                        .keyboardShortcut(.cancelAction)
                        .focusable(false)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Text("Press Esc to skip")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .foregroundStyle(.white)
        }
        .ignoresSafeArea()
    }
}
