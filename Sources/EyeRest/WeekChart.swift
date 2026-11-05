import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The "Last 7 Days" chart: time at the screen and breaks for each day, under
/// the numbers for the day under the pointer, or today's, and over the apps
/// used most that day if apps are recorded.
struct WeekChart: View {
    /// One day's totals.
    struct Day: Equatable {
        /// A moment in the day, for its name.
        var date: Date
        var screenSeconds: TimeInterval
        var breaksFinished: Int
        var breaksSkipped: Int
        /// The apps used most, most first, if apps were recorded.
        var apps: [App] = []

        /// An app's time at the screen that day.
        struct App: Equatable {
            var bundleID: String
            var seconds: TimeInterval
        }

        /// "41m", "6h 2m"; "6小时2分钟" in Chinese.
        var screenTime: String { WeekChart.duration(screenSeconds) }
        /// "6 hours, 2 minutes", for VoiceOver, which may read "2m" as 2 metres.
        var spokenScreenTime: String { WeekChart.duration(screenSeconds, width: .wide) }
    }

    /// What the chart shows. The menu updates it every second while it's open.
    @MainActor
    final class Model: ObservableObject {
        /// Oldest first, ending with today; at most `WeekChart.slots`.
        @Published var days: [Day] = []
        /// Index in `days` of the day under the pointer.
        @Published var pointed: Int?
        /// Whether the apps used most show under the plots.
        @Published var showsApps = false

        /// Points at the day under `x`, in the chart's coordinates, or at none.
        func point(atX x: CGFloat?) {
            let slot = x.map { Int((($0 - WeekChart.inset - WeekChart.gutter) / WeekChart.slotWidth).rounded(.down)) }
            let index = slot.flatMap { (0..<WeekChart.slots).contains($0) ? $0 - (WeekChart.slots - days.count) : nil }
            let pointed = index.flatMap { days.indices.contains($0) ? $0 : nil }
            if pointed != self.pointed { self.pointed = pointed }
        }
    }

    /// A slot per day, today's last; days before the log begins stay empty.
    static let slots = 7
    static let width: CGFloat = 300
    private static let inset: CGFloat = 14
    /// Room for the gridlines' labels, left of the bars.
    private static let gutter: CGFloat = 34
    private static var slotWidth: CGFloat { (width - 2 * inset - gutter) / CGFloat(slots) }
    private static let screenHeight: CGFloat = 84
    private static let breaksHeight: CGFloat = 56
    private static let padding: CGFloat = 10
    private static let readoutHeight: CGFloat = 34
    /// How many apps a day shows.
    static let appRows = 5
    private static let appRowHeight: CGFloat = 20
    /// The apps used most, from the gap above them to the last row's bottom.
    private static let appsHeight: CGFloat = 152
    private static let appNameWidth: CGFloat = 96
    /// Room for an app's bar and the time at its tip: what the icon and the
    /// name leave.
    private static var barRoom: CGFloat { width - 2 * inset - (16 + 6) - (appNameWidth + 8) }

    /// How far the plots are from the top, and from the bottom, which is
    /// where the pointer picks a day.
    static let plotsTop = padding + readoutHeight
    static func plotsBottom(showsApps: Bool) -> CGFloat { padding + (showsApps ? appsHeight : 0) }

    @ObservedObject var model: Model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            readout
            Text("Time at the screen")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
                .padding(.bottom, 4)
            plot(height: Self.screenHeight, scale: screenScale, label: hours) { index in
                let day = model.days[index]
                if day.screenSeconds > 0 {
                    bar(day.screenSeconds, of: screenScale, in: Self.screenHeight, blue)
                        .overlay(alignment: .top) {
                            Text(index == busiest ? day.screenTime : "")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                                .alignmentGuide(.top) { $0[.bottom] + 2 }  // just above the bar
                        }
                }
            }
            HStack(spacing: 12) {
                Text("Breaks")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                swatch(blue, "Finished")
                swatch(gray, "Skipped")
            }
            .padding(.top, 12)
            .padding(.bottom, 4)
            plot(height: Self.breaksHeight, scale: breaksScale, label: { "\(Int($0))" }) { index in
                // Skipped on top of finished, a 2 pt gap apart.
                let day = model.days[index]
                if day.breaksSkipped > 0 {
                    bar(Double(day.breaksSkipped), of: breaksScale, in: Self.breaksHeight, gray)
                }
                if day.breaksFinished > 0 {
                    bar(Double(day.breaksFinished), of: breaksScale, in: Self.breaksHeight, blue, rounded: day.breaksSkipped == 0)
                }
            }
            dayLabels
                .padding(.top, 5)
            if model.showsApps {
                mostUsed
            }
        }
        .monospacedDigit()
        .padding(.horizontal, Self.inset)
        .padding(.vertical, Self.padding)
        .frame(width: Self.width)
    }

    /// The name and numbers of the day under the pointer, or today's.
    private var readout: some View {
        let index = model.pointed ?? model.days.count - 1
        return VStack(alignment: .leading, spacing: 2) {
            if model.days.indices.contains(index) {
                let day = model.days[index]
                Text(name(index))
                    .font(.system(size: 13, weight: .semibold))
                Text("\(day.screenTime) at the screen · \(day.breaksFinished) finished · \(day.breaksSkipped) skipped")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, minHeight: Self.readoutHeight, maxHeight: Self.readoutHeight, alignment: .topLeading)
        // The day labels say the same to VoiceOver, one day at a time.
        .accessibilityHidden(true)
    }

    /// The apps used most on the day under the pointer, or today: a bar each
    /// from one baseline, the longest for the app used most, with the time at
    /// its tip.
    private var mostUsed: some View {
        let index = model.pointed ?? model.days.count - 1
        let apps = model.days.indices.contains(index) ? model.days[index].apps : []
        // The longest bar leaves room for the widest time beside it.
        let widest = apps.map { Self.textWidth(WeekChart.duration($0.seconds)) }.max() ?? 0
        let longest = Self.barRoom - 6 - widest
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Most used apps")
                    .font(.system(size: 12))
                Spacer()
                if model.days.indices.contains(index) {
                    Text(name(index))
                        .font(.system(size: 11))
                }
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 2)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if apps.isEmpty {
                Text("No apps recorded")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(height: Self.appRowHeight)
            }
            ForEach(apps, id: \.bundleID) { app in
                HStack(spacing: 0) {
                    Image(nsImage: AppInfo.icon(app.bundleID))
                        .resizable()
                        .frame(width: 16, height: 16)
                        .padding(.trailing, 6)
                    Text(AppInfo.name(app.bundleID))
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .frame(width: Self.appNameWidth, alignment: .leading)
                        .padding(.trailing, 8)
                    UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4)
                        .fill(blue)
                        .frame(width: max(2, longest * app.seconds / apps[0].seconds), height: 8)
                    Text(WeekChart.duration(app.seconds))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .padding(.leading, 4)
                    Spacer(minLength: 0)
                }
                .frame(height: Self.appRowHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityLabel(AppInfo.name(app.bundleID))
                .accessibilityValue(WeekChart.duration(app.seconds, width: .wide))
            }
        }
        .padding(.top, 14)
        .frame(height: Self.appsHeight, alignment: .top)
    }

    /// "Mon", "Tue" … "Today" under the slots. They're what VoiceOver reads:
    /// each day's name and numbers.
    private var dayLabels: some View {
        HStack(spacing: 0) {
            ForEach(0..<Self.slots, id: \.self) { slot in
                let index = slot - (Self.slots - model.days.count)
                if index >= 0 {
                    let isToday = index == model.days.count - 1
                    let day = model.days[index]
                    Text(isToday ? String(localized: "Today") : day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 11, weight: isToday ? .semibold : .regular))
                        .foregroundStyle(isToday ? .primary : .secondary)
                        .frame(width: Self.slotWidth)
                        .opacity(opacity(index))
                        .accessibilityLabel(name(index))
                        .accessibilityValue(String(localized: "\(day.spokenScreenTime) at the screen · \(day.breaksFinished) finished · \(day.breaksSkipped) skipped"))
                } else {
                    Color.clear.frame(width: Self.slotWidth, height: 1)
                }
            }
        }
        .padding(.leading, Self.gutter)
    }

    /// A plot `height` tall: gridlines labelled in the margin, under a column
    /// per slot built by `column` from an index in `days`.
    private func plot<Column: View>(height: CGFloat, scale: Scale, label: @escaping (Double) -> String,
                                    @ViewBuilder column: @escaping (Int) -> Column) -> some View {
        ZStack(alignment: .bottomLeading) {
            ForEach([0] + scale.lines, id: \.self) { value in
                HStack(spacing: 6) {
                    Text(value == 0 ? "0" : label(value))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: Self.gutter - 6, alignment: .trailing)
                    Rectangle()
                        .fill(.primary.opacity(value == 0 ? 0.25 : 0.1))
                        .frame(height: 1)
                }
                .frame(height: 12)
                .offset(y: 6 - height * value / scale.top)  // the row's middle on the line
            }
            HStack(spacing: 0) {
                ForEach(0..<Self.slots, id: \.self) { slot in
                    let index = slot - (Self.slots - model.days.count)
                    VStack(spacing: 2) {
                        Spacer(minLength: 0)
                        if index >= 0 { column(index) }
                    }
                    .frame(width: Self.slotWidth, height: height)
                    .opacity(opacity(index))
                }
            }
            .padding(.leading, Self.gutter)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// A bar for `value`, 20 pt wide with its top corners rounded, at least
    /// 2 pt tall so a small value still shows.
    private func bar(_ value: Double, of scale: Scale, in height: CGFloat, _ color: Color, rounded: Bool = true) -> some View {
        let barHeight = max(2, height * value / scale.top)
        let radius = rounded ? min(4, barHeight / 2) : 0
        return UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius)
            .fill(color)
            .frame(width: 20, height: barHeight)
    }

    private func swatch(_ color: Color, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 9, height: 9)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    /// Other days fade while the pointer is on one.
    private func opacity(_ index: Int) -> Double {
        model.pointed == nil || model.pointed == index ? 1 : 0.4
    }

    /// "Today", "Yesterday", then "Mon, Nov 2".
    private func name(_ index: Int) -> String {
        switch model.days.count - 1 - index {
        case 0: String(localized: "Today")
        case 1: String(localized: "Yesterday")
        default: model.days[index].date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
    }

    /// "4h"; "4小时" in Chinese.
    private func hours(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours], width: .narrow))
    }

    /// Hours and minutes, rounded down: "41m", "6h 2m", or with `.wide`
    /// "6 hours, 2 minutes".
    static func duration(_ seconds: TimeInterval, width: Duration.UnitsFormatStyle.UnitWidth = .narrow) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: width, fractionalPart: .hide(rounded: .down)))
    }

    /// How wide a time is in its font, which SwiftUI can't say before laying
    /// it out.
    private static func textWidth(_ text: String) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// The day with the most time at the screen, whose bar is labelled.
    private var busiest: Int? {
        model.days.indices.max { model.days[$0].screenSeconds < model.days[$1].screenSeconds }
            .flatMap { model.days[$0].screenSeconds > 0 ? $0 : nil }
    }

    // MARK: Scales

    /// The value at the top of a plot, and one or two gridlines: multiples of
    /// the smallest step that covers the largest value in three.
    private struct Scale {
        var top: Double
        var lines: [Double]

        /// `headroom` leaves space above the tallest bar, e.g. for a label.
        init(largest: Double, steps: [Double], headroom: Double) {
            let step = steps.first { largest <= 3 * $0 } ?? steps[steps.count - 1]
            let top = max(largest * headroom, step)
            self.top = top
            lines = [step, 2 * step].filter { $0 <= top }
        }
    }

    /// Whole hours, with room for the busiest day's label above its bar.
    private var screenScale: Scale {
        Scale(largest: model.days.map(\.screenSeconds).max() ?? 0, steps: [1, 2, 4, 8].map { $0 * 3600 },
              headroom: Double(Self.screenHeight) / Double(Self.screenHeight - 16))
    }

    private var breaksScale: Scale {
        Scale(largest: Double(model.days.map { $0.breaksFinished + $0.breaksSkipped }.max() ?? 0),
              steps: [1, 2, 5, 10, 20, 50], headroom: 1.1)
    }

    // MARK: Colors

    /// Time at the screen and finished breaks in blue, skipped breaks in gray:
    /// a pair that stays apart with color blindness, on light and dark menus.
    private var blue: Color {
        colorScheme == .dark
            ? Color(red: 0x39 / 255.0, green: 0x87 / 255.0, blue: 0xe5 / 255.0)
            : Color(red: 0x2a / 255.0, green: 0x78 / 255.0, blue: 0xd6 / 255.0)
    }

    private var gray: Color {
        colorScheme == .dark
            ? Color(red: 0x6b / 255.0, green: 0x6a / 255.0, blue: 0x65 / 255.0)
            : Color(red: 0x9a / 255.0, green: 0x99 / 255.0, blue: 0x93 / 255.0)
    }
}

/// The chart as a menu item's view. Its tracking area follows the pointer
/// even though the app isn't active, as it isn't while a menu bar menu is open.
final class WeekChartView: NSView {
    private let model: WeekChart.Model

    init(model: WeekChart.Model) {
        self.model = model
        let hosting = NSHostingView(rootView: WeekChart(model: model))
        super.init(frame: NSRect(origin: .zero, size: hosting.fittingSize))
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        // Only the plots pick a day. Above them, on the readout, and below, on
        // the apps, the day stays, so the pointer can go there to read it.
        guard bounds.height - location.y > WeekChart.plotsTop,
              location.y > WeekChart.plotsBottom(showsApps: model.showsApps) else { return }
        model.point(atX: location.x)
    }

    override func mouseExited(with event: NSEvent) {
        model.point(atX: nil)
    }
}

/// Apps' names and icons, by bundle identifier, as Finder shows them; looked
/// up once each.
@MainActor
private enum AppInfo {
    private static var known: [String: (name: String, icon: NSImage)] = [:]

    static func name(_ bundleID: String) -> String { info(bundleID).name }
    static func icon(_ bundleID: String) -> NSImage { info(bundleID).icon }

    /// An app that's no longer installed gets its bundle identifier and a
    /// plain app icon.
    private static func info(_ bundleID: String) -> (name: String, icon: NSImage) {
        if let info = known[bundleID] { return info }
        var info = (name: bundleID, icon: NSWorkspace.shared.icon(for: .applicationBundle))
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
            info = (name.hasSuffix(".app") ? String(name.dropLast(4)) : name, NSWorkspace.shared.icon(forFile: url.path))
        }
        known[bundleID] = info
        return info
    }
}
