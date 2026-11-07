import CoreGraphics
import Testing
@testable import EyeRestCore

// Window and display bounds measured on a MacBook Pro with two external
// displays, on macOS 26.
private let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
private let external = CGRect(x: 845, y: -1200, width: 1920, height: 1200)
private let other = CGRect(x: -1715, y: -1440, width: 2560, height: 1440)
private let displays = [builtIn, external, other]

private func fills(_ windows: [CGRect]) -> Bool {
    DisplayFill.fillsDisplay(windows: windows, displays: displays)
}

struct FillingADisplay {
    @Test func aWindowCoveringADisplayFillsIt() {
        // A borderless game or a slideshow.
        #expect(fills([other]))
        // Native full screen on an external display: a window the size of the
        // display, and one for the title bar just above it.
        #expect(fills([CGRect(x: 845, y: -1232, width: 1920, height: 32), external]))
    }

    @Test func fullScreenBelowTheCameraHousingFillsTheDisplay() {
        #expect(fills([
            CGRect(x: 0, y: 0, width: 1512, height: 33),  // the band the menu bar slides into
            CGRect(x: 0, y: 33, width: 1512, height: 32),
            CGRect(x: 0, y: 33, width: 1512, height: 949),
        ]))
    }

    @Test func fullScreenBelowAMenuBarThatStaysFillsTheDisplay() {
        #expect(fills([
            CGRect(x: 845, y: -1200, width: 1920, height: 30),
            CGRect(x: 845, y: -1170, width: 1920, height: 32),
            CGRect(x: 845, y: -1170, width: 1920, height: 1170),
        ]))
    }

    @Test func aZoomedWindowDoesNot() {
        // The same size as full screen when the Dock is on another display.
        #expect(!fills([CGRect(x: 0, y: 33, width: 1512, height: 949)]))
        #expect(!fills([CGRect(x: 845, y: -1170, width: 1920, height: 1170)]))
    }

    @Test func aWindowTheSizeOfAnotherDisplayDoesNot() {
        #expect(!fills([CGRect(x: 965, y: -1029, width: 1512, height: 949)]))
        #expect(!fills([CGRect(x: -1500, y: -1300, width: 1920, height: 1200)]))
    }

    @Test func theBandMustBeShortAndCoveredOnTheSameDisplay() {
        // A band on another display doesn't count.
        #expect(!fills([
            CGRect(x: 845, y: -1200, width: 1920, height: 33),
            CGRect(x: 0, y: 33, width: 1512, height: 949),
        ]))
        // Nor does a window stacked under a tall one.
        #expect(!fills([
            CGRect(x: 0, y: 0, width: 1512, height: 100),
            CGRect(x: 0, y: 100, width: 1512, height: 882),
        ]))
    }

    @Test func aWindowLargerThanTheDisplayDoesNot() {
        #expect(!fills([CGRect(x: 0, y: 0, width: 2357, height: 982)]))
        #expect(!fills([]))
    }
}
