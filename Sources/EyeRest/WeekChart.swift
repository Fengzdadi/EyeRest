import AppKit
import SwiftUI

/// The "Last 7 Days" chart: time at the screen and breaks for each day, under
/// the numbers for the day under the pointer, or today's.
struct WeekChart: View {
    /// One day's totals.
    struct Day: Equatable {
        /// A moment in the day, for its name.
        var date: Date
        var screenSeconds: TimeInterval
        var breaksFinished: Int
        var breaksSkipped: Int

        /// "41m", "6h 2m"; "6小时2分钟" in Chinese.
        var screenTime: String { Self.format(screenSeconds, width: .narrow) }
        /// "6 hours, 2 minutes", for VoiceOver, which may read "2m" as 2 metres.
        var spokenScreenTime: String { Self.format(screenSeconds, width: .wide) }

        private static func format(_ seconds: TimeInterval, width: Duration.UnitsFormatStyle.UnitWidth) -> String {
            Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: width, fractionalPart: .hide(rounded: .down)))
        }
    }

    /// What the chart shows. The menu updates it every second while it's open.
    @MainActor
    final class Model: ObservableObject {
        /// Oldest first, ending with today; at most `WeekChart.slots`.
        @Published var days: [Day] = []
        /// Index in `days` of the day under the pointer.
        @Published var pointed: Int?

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
        }
        .monospacedDigit()
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 10)
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
        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .topLeading)
        // The day labels say the same to VoiceOver, one day at a time.
        .accessibilityHidden(true)
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
        model.point(atX: convert(event.locationInWindow, from: nil).x)
    }

    override func mouseExited(with event: NSEvent) {
        model.point(atX: nil)
    }
}
