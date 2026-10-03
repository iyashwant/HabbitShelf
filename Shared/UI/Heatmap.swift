import SwiftUI

extension Day {
    /// Display formatters are costly to create, so tiles and rows share these.
    static let shortMonth = utcFormatter("MMM")
    static let monthYear = utcFormatter("MMM yyyy")
    static let longDay = utcFormatter("EEE, MMM d, yyyy")
    private static func utcFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter(); f.locale = .autoupdatingCurrent; f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = format
        return f
    }
}

/// Tile shades for one grid style: full color for success, `empty` inside the tracked range, `inactive` outside it.
struct TileShade {
    var empty = BuddyStyle.emptyTile
    var inactive = BuddyStyle.inactiveTile
    /// The detail history uses brighter empty tiles than the overview cards.
    static let detail = TileShade(empty: 0.18, inactive: 0.12)
    func alpha(_ p: Progress) -> Double { !p.available ? inactive : p.success ? 1 : p.slip ? empty + 0.04 : empty + p.fraction * (0.75 - empty) }
}

struct Heatmap: View {
    let habit: Habit
    let data: BuddyData
    var weeks = 24
    var end: Day = Day()
    var labels = true
    var monthLabels = true
    var weekdayLabels = true
    /// Fixed tile pitch; when nil the tiles stretch to fill the width.
    var pitch: CGFloat?
    /// With a fixed pitch, show only the latest weeks that fit the width.
    var fit = false
    var shade = TileShade()
    private let gap: CGFloat = 3
    private var top: CGFloat { labels && monthLabels ? 18 : 0 }
    var body: some View {
        GeometryReader { proxy in
            let labelWidth: CGFloat = labels && weekdayLabels ? 26 : 0
            let weeks = fit && pitch != nil ? max(1, Int((proxy.size.width - labelWidth + gap) / pitch!)) : self.weeks
            let first = end.startOfWeek(data.settings.weekStart).adding(-(weeks - 1) * 7)
            let step = pitch ?? max(5, (proxy.size.width - labelWidth + gap) / CGFloat(weeks))
            let tile = step - gap
            Canvas { context, _ in
                let today = Day(), color = BuddyStyle.color(habit.color)
                for col in 0..<weeks {
                    let weekStart = first.adding(col * 7)
                    for row in 0..<7 {
                        let day = weekStart.adding(row)
                        let progress = Engine.progress(habit, day: day, data: data, today: today)
                        let rect = CGRect(x: labelWidth + CGFloat(col) * step, y: top + CGFloat(row) * step, width: tile, height: tile)
                        context.fill(Path(roundedRect: rect, cornerRadius: tile * 0.3), with: .color(progress.frozen ? BuddyStyle.freeze.opacity(0.5) : color.opacity(shade.alpha(progress))))
                    }
                    // A month is labelled at the first week that starts inside it.
                    if labels && monthLabels && Int(weekStart.rawValue.suffix(2))! <= 7 {
                        let text = Text(Day.shortMonth.string(from: weekStart.date)).font(BuddyFont.mono(10)).foregroundStyle(Color(hex: 0x73737C))
                        context.draw(text, at: CGPoint(x: labelWidth + CGFloat(col) * step, y: 6), anchor: .leading)
                    }
                }
                if labels && weekdayLabels {
                    for row in [1, 3, 5] {
                        context.draw(Text(Self.weekday(data.settings.weekStart, row)).font(BuddyFont.mono(10)).foregroundStyle(Color(hex: 0x73737C)), at: CGPoint(x: 0, y: top + CGFloat(row) * step + tile / 2), anchor: .leading)
                    }
                }
            }
        }
        .frame(height: top + 7 * (pitch ?? 13))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(habit.name), contribution grid, last \(weeks) weeks. Open the calendar to edit individual days.")
    }
    static func weekday(_ start: Int, _ row: Int) -> String { Calendar.current.shortWeekdaySymbols[(start - 1 + row) % 7] }
}

struct DayTile: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    let habit: Habit
    let day: Day
    let data: BuddyData
    var size: CGFloat = 30
    var showNumber = false
    var body: some View {
        let today = Day(), p = Engine.progress(habit, day: day, data: data, today: today)
        let color = BuddyStyle.color(habit.color), shape = RoundedRectangle(cornerRadius: size * 0.3, style: .circular)
        shape.fill(p.frozen ? BuddyStyle.freeze.opacity(0.35) : color.opacity(TileShade().alpha(p)))
            .overlay {
                if p.frozen && !showNumber { LucideIcon("snowflake", size: size * 0.45).foregroundStyle(BuddyStyle.freeze) }
                else if showNumber { Text(String(Int(day.rawValue.suffix(2))!)).font(BuddyFont.mono(11)).foregroundStyle(p.success ? Color.black.opacity(0.8) : .secondary) }
                else if p.slip { LucideIcon("x", size: size * 0.4).foregroundStyle(color) }
                else if p.success && differentiate { LucideIcon("check", size: size * 0.4).foregroundStyle(Color.black.opacity(0.6)) }
                else if habit.goal(on: day).tracking != .yesNo && !p.success && p.fraction > 0 {
                    Circle().trim(from: 0, to: p.fraction).stroke(color, lineWidth: 2).rotationEffect(.degrees(-90)).padding(size * 0.18)
                }
            }
            .overlay(alignment: .bottom) { if data.settings.notes && !data.record(habit.id, day).note.isEmpty { Circle().fill(p.success ? Color.black.opacity(0.6) : Color.primary).frame(width: 3, height: 3).padding(.bottom, 3) } }
            .frame(width: size, height: size)
            .opacity(p.available || habit.loggable(on: day, today: today) ? 1 : 0.4)
            .accessibilityLabel("\(day.rawValue), \(p.success ? "complete" : p.slip ? "slip" : p.frozen ? "frozen" : "incomplete"), \(Amount.text(p.amount)) \(habit.goal(on: day).unit)")
    }
}

/// The whole history in a horizontal scroller that opens on the latest week, with the oldest visible weeks fading out.
struct ContributionHistory: View {
    @Environment(\.colorScheme) private var scheme
    let habit: Habit
    let data: BuddyData
    var start: Day?
    var end = Day()
    var monthLabels = true
    var weekdayLabels = true
    var shade = TileShade()
    var labelWidth: CGFloat = 26
    /// Width of the leading fade.
    var fade: CGFloat = 33
    /// Shade the leading edge with the canvas color instead of fading the tiles out (detail style).
    var shadeEdge = false
    private let pitch: CGFloat = 13
    private var weeks: Int { max(30, (start ?? habit.created).startOfWeek(data.settings.weekStart).distance(to: end.startOfWeek(data.settings.weekStart)) / 7 + 1) }
    private var top: CGFloat { monthLabels ? 18 : 0 }
    var body: some View {
        HStack(spacing: 0) {
            if weekdayLabels {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(row % 2 == 1 ? Heatmap.weekday(data.settings.weekStart, row) : "").font(BuddyFont.mono(10)).foregroundStyle(Color(hex: 0x73737C)).frame(height: pitch - 3).padding(.bottom, 3)
                    }
                }.padding(.top, top).frame(width: labelWidth, alignment: .leading).accessibilityHidden(true)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Heatmap(habit: habit, data: data, weeks: weeks, end: end, monthLabels: monthLabels, weekdayLabels: false, pitch: pitch, shade: shade)
                    .frame(width: CGFloat(weeks) * pitch)
            }
            .defaultScrollAnchor(.trailing)
            .mask(HStack(spacing: 0) { LinearGradient(colors: [shadeEdge ? .black : .clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: fade); Color.black })
            .overlay(alignment: .leading) { if shadeEdge { LinearGradient(colors: [BuddyStyle.canvas(scheme).opacity(0.7), BuddyStyle.canvas(scheme).opacity(0)], startPoint: .leading, endPoint: .trailing).frame(width: fade).allowsHitTesting(false) } }
        }
        .frame(height: top + 7 * pitch)
    }
}

/// One day in the detail calendar. Days of neighbouring months show at reduced opacity.
struct CalendarDay: View {
    @Environment(\.colorScheme) private var scheme
    let habit: Habit
    let day: Day
    let data: BuddyData
    var inMonth = true
    var body: some View {
        let today = Day(), p = Engine.progress(habit, day: day, data: data, today: today), c = BuddyStyle.color(habit.color)
        let shape = RoundedRectangle(cornerRadius: 12, style: .circular)
        let digit: Color = p.success || day == today ? BuddyStyle.text(scheme) : day > today ? BuddyStyle.text(scheme).opacity(0.18) : BuddyStyle.secondaryText(scheme)
        ZStack {
            shape.fill(c.opacity(p.success ? 0.15 : p.fraction * 0.1))
            Text(String(Int(day.rawValue.suffix(2))!)).font(BuddyFont.mono(14)).foregroundStyle(digit)
            if p.success || p.slip {
                Group { if p.slip { LucideIcon("x", size: 9) } else { Circle().frame(width: 5, height: 5) } }
                    .foregroundStyle(c).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, p.slip ? 1.5 : 3.5)
            } else if p.frozen {
                LucideIcon("snowflake", size: 9).foregroundStyle(BuddyStyle.freeze).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 1.5)
            }
            if day == today && data.settings.showToday { shape.strokeBorder(c, lineWidth: 1.5) }
        }
        .frame(maxWidth: .infinity).frame(height: 46)
        .opacity(inMonth || day > today ? 1 : 0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.rawValue), \(p.success ? "complete" : p.slip ? "slip" : p.frozen ? "frozen" : "incomplete"), \(Amount.text(p.amount))")
    }
}
