import AppKit
import SwiftUI

/// Full-screen break screen on every display.
@MainActor
final class BreakOverlay {
    var onSkip: (() -> Void)?
    var onPostpone: (() -> Void)?

    private var panels: [OverlayPanel] = []

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
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            panels.append(panel)
        }

        // Take keyboard focus (for Esc) on the screen the mouse is on, without
        // activating the app, so focus returns to the user's app afterwards.
        let mouse = NSEvent.mouseLocation
        let keyPanel = panels.first { $0.frame.contains(mouse) } ?? panels.first
        keyPanel?.makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.6
            panels.forEach { $0.animator().alphaValue = 1 }
        }
    }

    func hide() {
        let closing = panels
        panels = []
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            closing.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            closing.forEach { $0.orderOut(nil) }
        })
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
        let total = max(1, Double(Settings.breakSeconds))
        let left = max(0, scheduler.remaining)

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
                    Text("\(Int(left.rounded(.up)))")
                        .font(.system(size: 64, weight: .light, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 180, height: 180)

                VStack(spacing: 10) {
                    Text("Look at something 20 feet away")
                        .font(.system(size: 30, weight: .semibold))
                    Text("About 6 metres. Let your eyes relax.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }

                HStack(spacing: 12) {
                    Button("Postpone \(Settings.postponeSeconds / 60) min", action: onPostpone)
                    Button("Skip", action: onSkip)
                        .keyboardShortcut(.cancelAction)
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
