import CoreGraphics

/// Tells from window and display bounds alone whether an app fills a display,
/// as full-screen videos, games and slideshows do. Bounds are in the global
/// coordinates that `CGWindowListCopyWindowInfo` and `CGDisplayBounds` share:
/// the origin at the top left of the main display, y growing down.
public enum DisplayFill {
    /// The tallest band native full screen leaves at the top of a display: a
    /// menu bar (30 pt on macOS 26), or a MacBook's camera housing (33 pt at
    /// the default resolution, a little more at "More Space").
    static let maxBand: CGFloat = 50

    /// Whether one of `windows`, the on-screen windows of one app, fills one
    /// of `displays`.
    ///
    /// Either a window covers the whole display, or the app is in native full
    /// screen below a band at the top: the camera housing, or a menu bar set
    /// to stay visible in full screen. The app then also has a window across
    /// that band, the one its menu bar and toolbar slide into, which a window
    /// zoomed to fill the same space doesn't have.
    public static func fillsDisplay(windows: [CGRect], displays: [CGRect]) -> Bool {
        displays.contains { display in
            windows.contains { window in
                if matches(window, display) { return true }
                let band = window.minY - display.minY
                guard band >= 1, band <= maxBand else { return false }
                var below = display
                below.origin.y += band
                below.size.height -= band
                var strip = display
                strip.size.height = band
                return matches(window, below) && windows.contains { matches($0, strip) }
            }
        }
    }

    /// Equal to within a point, which also covers rounding in the bounds.
    private static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1
            && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
    }
}
