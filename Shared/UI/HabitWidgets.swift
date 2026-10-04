import SwiftUI
import AppIntents

/// Colors for one widget style. Tinted widgets wash the habit color over the base surface.
struct WidgetPalette: Equatable {
    let base: Color
    let wash: Double
    let dark: Bool
    let tint: Color
    init(_ style: WidgetStyle, scheme: ColorScheme, tint: Color) {
        dark = style == .dark || (style != .light && scheme == .dark)
        self.tint = tint
        switch style {
        case .dark: base = .black; wash = 0
        case .light: base = .white; wash = 0
        case .automatic: base = BuddyStyle.surface(scheme); wash = 0
        case .tinted: base = scheme == .dark ? BuddyStyle.surface(.dark) : .white; wash = scheme == .dark ? 0.16 : 0.13
        }
    }
    var primary: Color { Color(hex: dark ? 0xF2F2F4 : 0x1C1C1E) }
    var secondary: Color { Color(hex: dark ? 0x8E8E93 : 0x86868B) }
    var missed: Color { tint.opacity(dark ? 0.26 : 0.2) }
    var outline: Color { (dark ? Color.white : Color.black).opacity(dark ? 0.16 : 0.1) }
    func background(_ shape: some Shape) -> some View { shape.fill(base).overlay { shape.fill(tint.opacity(wash)) } }
}

/// How a single day reads in the dashboard designs.
enum DayMark {
    case done, missed, pending, future, inactive, frozen
    init(_ habit: Habit, _ day: Day, _ data: BuddyData, today: Day) {
        if day > today { self = .future; return }
        let p = Engine.progress(habit, day: day, data: data, today: today)
        self = p.success ? .done : !p.available ? .inactive : p.frozen ? .frozen : day == today ? .pending : .missed
    }
    func fill(_ palette: WidgetPalette) -> Color {
        switch self { case .done: palette.tint; case .missed, .pending: palette.missed; case .inactive: palette.outline.opacity(0.5); case .future: .clear; case .frozen: BuddyStyle.freeze.opacity(0.45) }
    }
}

/// Streak count with a flame and its unit, e.g. "48 DAYS".
struct StreakBadge: View {
    let summary: StreakSummary
    let palette: WidgetPalette
    var size: CGFloat = 34
    var unit = true
    var trailing = false
    var body: some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 2) {
                Text("\(summary.value)").font(BuddyFont.text(size, .heavy)).monospacedDigit().foregroundStyle(palette.primary).lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText(value: Double(summary.value)))
                Image(systemName: "flame.fill").font(.system(size: size * 0.52)).foregroundStyle(palette.tint)
            }
            if unit { Text(summary.unit.rawValue.uppercased()).font(BuddyFont.text(max(9, size * 0.34), .medium)).tracking(0.5).foregroundStyle(palette.secondary) }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("Streak \(summary.value) \(summary.unit.rawValue)")
    }
}

/// Today's check. In the app it runs `onTap`; on the home screen it logs through the widget intent,
/// or opens the app where a numeric total needs editing.
struct HabitCheck: View {
    let habit: Habit
    let data: BuddyData
    var today = Day()
    var size: CGFloat = 44
    let palette: WidgetPalette
    var onTap: (() -> Void)?
    /// Shows the habit's icon in place of the check, for the quick check grid.
    var icon = false
    var body: some View {
        let p = Engine.progress(habit, day: today, data: data, today: today), g = habit.goal(on: today)
        let label = ZStack {
            Circle().fill(p.success ? palette.tint : palette.missed)
            if !p.success && p.fraction > 0 { Circle().trim(from: 0, to: p.fraction).stroke(palette.tint, style: StrokeStyle(lineWidth: max(2, size * 0.07), lineCap: .round)).rotationEffect(.degrees(-90)).padding(size * 0.035) }
            if icon { BuddyGlyph(symbol: habit.symbol, size: size * 0.44).foregroundStyle(p.success ? Color.white : palette.tint) }
            else { Image(systemName: p.slip ? "xmark" : g.tracking != .yesNo && !p.success ? "plus" : "checkmark").font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(p.success ? Color.white : palette.tint) }
        }.frame(width: size, height: size).contentShape(Circle())
        Group {
            if let onTap { Button(action: onTap) { label }.buttonStyle(FlatButtonStyle()) }
            else if g.tracking != .yesNo && (g.mode == .quit || g.tap == .enterTotal || p.success) { Link(destination: URL(string: "habitbuddy://\(habit.id.uuidString)?day=\(today.rawValue)")!) { label } }
            else { Button(intent: WidgetLogIntent(habit.id, day: today)) { label }.buttonStyle(.plain) }
        }
        .accessibilityLabel(habit.currentGoal.mode == .quit ? "Log or clear a slip for \(habit.name)" : "Log progress for \(habit.name)")
        .accessibilityValue(p.success ? "Done" : "Not done")
    }
}

/// The current week as lettered squares, with "done / 7".
struct WeekStrip: View {
    let habit: Habit
    let data: BuddyData
    var today = Day()
    let palette: WidgetPalette
    var cell: CGFloat = 15
    var count = true
    var body: some View {
        let start = today.startOfWeek(data.settings.weekStart), days = (0..<7).map { start.adding($0) }
        let marks = days.map { DayMark(habit, $0, data, today: today) }, done = marks.filter { $0 == .done }.count
        HStack(spacing: cell * 0.2) {
            ForEach(0..<7, id: \.self) { i in
                let mark = marks[i], shape = RoundedRectangle(cornerRadius: cell * 0.28, style: .continuous)
                Text(Calendar.current.veryShortWeekdaySymbols[days[i].weekday - 1]).font(.system(size: cell * 0.6, weight: .bold, design: .rounded))
                    .foregroundStyle(mark == .done ? Color.white : mark == .frozen ? palette.primary : mark == .future || mark == .inactive ? palette.secondary.opacity(0.7) : palette.tint)
                    .frame(width: cell, height: cell).background(mark.fill(palette), in: shape)
                    .overlay { if mark == .future || mark == .inactive { shape.strokeBorder(palette.outline, lineWidth: 1) } }
            }
            if count { Text("\(done)/7").font(BuddyFont.text(cell * 0.82)).monospacedDigit().foregroundStyle(palette.secondary).padding(.leading, cell * 0.3).fixedSize().contentTransition(.numericText(value: Double(done))) }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("This week, \(done) of 7 days done")
    }
}

/// One month as a seven-column grid that fits its frame.
struct MonthDots: View {
    let habit: Habit
    let data: BuddyData
    let month: Day
    var today = Day()
    let palette: WidgetPalette
    var gap: CGFloat = 3
    var body: some View {
        let first = month.startOfMonth, offset = (first.weekday - data.settings.weekStart + 7) % 7
        let count = first.distance(to: first.endOfMonth) + 1, rows = (offset + count + 6) / 7
        // Read once for both the drawing and the VoiceOver label.
        let marks = (0..<count).map { DayMark(habit, first.adding($0), data, today: today) }
        GeometryReader { proxy in
            let cell = min((proxy.size.width - 6 * gap) / 7, (proxy.size.height - CGFloat(rows - 1) * gap) / CGFloat(rows))
            Canvas { context, _ in
                for n in 0..<count {
                    let slot = offset + n, mark = marks[n]
                    let rect = CGRect(x: CGFloat(slot % 7) * (cell + gap), y: CGFloat(slot / 7) * (cell + gap), width: cell, height: cell)
                    let path = Path(roundedRect: rect, cornerRadius: cell * 0.28)
                    if mark == .future { context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: cell * 0.28), with: .color(palette.outline), lineWidth: 1) }
                    else { context.fill(path, with: .color(mark.fill(palette))) }
                }
            }
        }
        .aspectRatio(7 / CGFloat(rows) * 0.999, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Day.monthYear.string(from: first.date)), \(marks.filter { $0 == .done }.count) days done")
    }
}

/// The last weeks as columns, with lettered weekday squares on the leading edge.
struct WeekColumns: View {
    let habit: Habit
    let data: BuddyData
    var weeks = 20
    var today = Day()
    let palette: WidgetPalette
    var gap: CGFloat = 3
    var body: some View {
        GeometryReader { proxy in
            let cell = min((proxy.size.height - 6 * gap) / 7, (proxy.size.width - CGFloat(weeks) * gap) / CGFloat(weeks + 1))
            let first = today.startOfWeek(data.settings.weekStart).adding(-(weeks - 1) * 7)
            Canvas { context, _ in
                for row in 0..<7 {
                    let y = CGFloat(row) * (cell + gap)
                    let letter = CGRect(x: 0, y: y, width: cell, height: cell)
                    context.fill(Path(roundedRect: letter, cornerRadius: cell * 0.28), with: .color(palette.outline.opacity(0.7)))
                    let symbol = Calendar.current.veryShortWeekdaySymbols[(data.settings.weekStart - 1 + row) % 7]
                    context.draw(Text(symbol).font(.system(size: cell * 0.55, weight: .bold, design: .rounded)).foregroundStyle(palette.secondary), at: CGPoint(x: letter.midX, y: letter.midY))
                    for col in 0..<weeks {
                        let day = first.adding(col * 7 + row), mark = DayMark(habit, day, data, today: today)
                        let rect = CGRect(x: CGFloat(col + 1) * (cell + gap), y: y, width: cell, height: cell)
                        if mark == .future { context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: cell * 0.28), with: .color(palette.outline), lineWidth: 1) }
                        else { context.fill(Path(roundedRect: rect, cornerRadius: cell * 0.28), with: .color(mark.fill(palette))) }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("\(habit.name), last \(weeks) weeks")
    }
}

/// The content of one dashboard or home-screen widget, without its background.
struct HabitWidgetContent: View {
    /// The app's cache of streaks and milestones; widgets compute them directly.
    @Environment(\.summaries) var summaries
    let kind: DashboardKind
    /// One of the design's sizes; nil uses its default.
    var size: WidgetSize?
    let habit: Habit?
    let data: BuddyData
    /// The habits a multi-habit design shows.
    var habits: [Habit] = []
    var routine: Routine?
    /// A heading in place of the design's default.
    var title: String?
    var today = Day()
    let palette: WidgetPalette
    /// In the app, the store's versions of every habit shown, including a routine's. With them the design redraws
    /// only when one of those habits or its own options change, not each time another habit is logged.
    var versions: [HabitVersion]?
    /// Logs today in the app; nil on the home screen, where the check runs an intent.
    var onCheck: ((Habit) -> Void)?
    /// Completes a routine in the app; nil on the home screen, where the button runs an intent.
    var onRoutine: ((Routine) -> Void)?
    var resolvedSize: WidgetSize { size.flatMap { kind.sizes.contains($0) ? $0 : nil } ?? kind.sizes[0] }
    var body: some View {
        switch kind {
        case .list: list
        case .today: todayTile
        case .checks: checksTile
        case .week: weekTile
        case .routine:
            if let routine { routineTile(routine) } else { placeholder("Choose a routine for this widget.") }
        default:
            if let habit { single(habit) } else { placeholder("Choose a habit for this widget.") }
        }
    }
    @ViewBuilder private func single(_ habit: Habit) -> some View {
        switch kind {
        case .streak: streakTile(habit, summaries.streak(habit, data: data, today: today))
        case .month: if resolvedSize == .large { monthLarge(habit) } else { month(habit, summaries.streak(habit, data: data, today: today)) }
        case .weeks: weeksTile(habit, summaries.streak(habit, data: data, today: today))
        case .months: months(habit, summaries.streak(habit, data: data, today: today))
        case .ring: ringTile(habit)
        case .stats: statsTile(habit)
        case .year: yearTile(habit)
        case .badge: badgeTile(habit)
        default: EmptyView()
        }
    }
    func placeholder(_ text: String) -> some View {
        Text(text).font(BuddyFont.text(13)).foregroundStyle(palette.secondary).multilineTextAlignment(.center).padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    func check(_ habit: Habit, _ size: CGFloat) -> HabitCheck {
        HabitCheck(habit: habit, data: data, today: today, size: size, palette: palette, onTap: onCheck.map { action in { action(habit) } })
    }
    private func streakTile(_ habit: Habit, _ streak: StreakSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) { StreakBadge(summary: streak, palette: palette); Spacer(minLength: 4); check(habit, 44) }
            Spacer(minLength: 6)
            Text(habit.name).font(BuddyFont.text(18, .semibold)).foregroundStyle(palette.primary).lineLimit(1).minimumScaleFactor(0.8).padding(.bottom, 8)
            WeekStrip(habit: habit, data: data, today: today, palette: palette, cell: 15)
        }.padding(14)
    }
    private func month(_ habit: Habit, _ streak: StreakSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name).font(BuddyFont.text(16, .semibold)).foregroundStyle(palette.primary).lineLimit(1)
                    StreakBadge(summary: streak, palette: palette, size: 14, unit: false)
                }
                Spacer(minLength: 4); check(habit, 34)
            }
            MonthDots(habit: habit, data: data, month: today.startOfMonth, today: today, palette: palette).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.padding(14)
    }
    private func weeksTile(_ habit: Habit, _ streak: StreakSummary) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                check(habit, 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(habit.name).font(BuddyFont.text(17, .semibold)).foregroundStyle(palette.primary).lineLimit(1)
                    Text("LAST 20 WEEKS").font(BuddyFont.text(10.5, .medium)).tracking(0.5).foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 4)
                StreakBadge(summary: streak, palette: palette, size: 20, trailing: true)
            }
            WeekColumns(habit: habit, data: data, today: today, palette: palette).frame(maxHeight: .infinity)
        }.padding(14)
    }
    private func months(_ habit: Habit, _ streak: StreakSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                check(habit, 34)
                Text(habit.name).font(BuddyFont.text(22, .semibold)).foregroundStyle(palette.primary).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                StreakBadge(summary: streak, palette: palette, size: 20, trailing: true)
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(0..<3, id: \.self) { n in
                    let month = today.startOfMonth.addingMonths(n - 2)
                    if n > 0 { palette.outline.frame(width: 1).padding(.horizontal, 8) }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(Text(Day.shortMonth.string(from: month.date)).font(BuddyFont.text(12, .semibold)).foregroundStyle(palette.primary))\(Text(" '" + String(month.rawValue.prefix(4).suffix(2))).font(BuddyFont.text(12)).foregroundStyle(palette.secondary))")
                        MonthDots(habit: habit, data: data, month: month, today: today, palette: palette, gap: 2.5)
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }.frame(maxHeight: .infinity, alignment: .top)
        }.padding(14)
    }
    /// Today's habits as a ring of colored segments, one per habit, filled when done. The medium size lists what's still open.
    private var todayTile: some View {
        let done = habits.filter { Engine.progress($0, day: today, data: data, today: today).success }
        let ring = TodayRing(habits: habits, data: data, today: today, palette: palette)
            .overlay {
                VStack(spacing: 0) {
                    Text("\(done.count)/\(habits.count)").font(BuddyFont.text(26, .heavy)).monospacedDigit().foregroundStyle(palette.primary).minimumScaleFactor(0.6).lineLimit(1)
                    Text(habits.isEmpty ? "NO HABITS" : done.count == habits.count ? "ALL DONE" : "DONE").font(BuddyFont.text(9.5, .semibold)).tracking(0.6).foregroundStyle(palette.secondary)
                }.padding(.horizontal, 18)
            }
        let header = HStack(alignment: .firstTextBaseline) {
            Text(heading("Today")).font(BuddyFont.text(17, .bold)).foregroundStyle(palette.primary).lineLimit(1)
            Spacer(minLength: 4)
            Text(Day.shortWeekday.string(from: today.date).uppercased()).font(BuddyFont.text(10.5, .semibold)).tracking(0.5).foregroundStyle(palette.secondary)
        }
        return Group {
            if resolvedSize == .medium {
                let open = habits.filter { h in !done.contains { $0.id == h.id } }, shown = open.prefix(3)
                HStack(spacing: 16) {
                    ring.frame(maxHeight: .infinity)
                    VStack(alignment: .leading, spacing: 7) {
                        header.padding(.bottom, 1)
                        if habits.isEmpty { Text("Create habits in Habit Buddy.").font(BuddyFont.text(13)).foregroundStyle(palette.secondary) }
                        else if open.isEmpty { Label("Everything's done", systemImage: "checkmark.circle.fill").font(BuddyFont.text(13.5, .medium)).foregroundStyle(palette.primary) }
                        ForEach(shown) { habit in
                            HStack(spacing: 8) {
                                HabitCheck(habit: habit, data: data, today: today, size: 24, palette: rowPalette(habit), onTap: onCheck.map { action in { action(habit) } })
                                Text(habit.name).font(BuddyFont.text(13.5, .medium)).foregroundStyle(palette.primary).lineLimit(1)
                            }
                        }
                        if open.count > shown.count { Text("+\(open.count - shown.count) more to go").font(BuddyFont.text(12)).foregroundStyle(palette.secondary).padding(.leading, 2) }
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(14)
            } else {
                VStack(alignment: .leading, spacing: 8) { header; ring.frame(maxWidth: .infinity, maxHeight: .infinity) }.padding(14)
            }
        }
        .accessibilityElement(children: resolvedSize == .medium ? .contain : .ignore).accessibilityLabel("\(heading("Today")), \(done.count) of \(habits.count) habits done")
    }
    private var list: some View {
        let medium = resolvedSize == .medium
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(heading("Today")).font(BuddyFont.text(medium ? 19 : 22, .heavy)).foregroundStyle(palette.primary).lineLimit(1)
                Spacer()
                Text(Day.longDay.string(from: today.date)).font(BuddyFont.text(11, .medium)).foregroundStyle(palette.secondary).lineLimit(1)
            }.padding(.bottom, medium ? 4 : 8)
            if habits.isEmpty { Text("Create habits in Habit Buddy.").font(BuddyFont.text(13)).foregroundStyle(palette.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
            ForEach(habits.prefix(medium ? 3 : 6)) { habit in
                let streak = summaries.streak(habit, data: data, today: today), rowPalette = rowPalette(habit)
                HStack(spacing: 10) {
                    HabitCheck(habit: habit, data: data, today: today, size: medium ? 28 : 30, palette: rowPalette, onTap: onCheck.map { action in { action(habit) } })
                    VStack(alignment: .leading, spacing: medium ? 3 : 4) {
                        Text(habit.name).font(BuddyFont.text(14, .semibold)).foregroundStyle(palette.primary).lineLimit(1)
                        WeekStrip(habit: habit, data: data, today: today, palette: rowPalette, cell: medium ? 11 : 12)
                    }
                    Spacer(minLength: 4)
                    StreakBadge(summary: streak, palette: rowPalette, size: medium ? 15 : 17, trailing: true)
                }.frame(maxHeight: .infinity)
            }
        }.padding(14)
    }
    /// The widget's own title, or the design's default.
    func heading(_ fallback: String) -> String {
        guard let text = title?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return fallback }
        return text
    }
    /// Each habit keeps its own color inside multi-habit designs.
    func rowPalette(_ habit: Habit) -> WidgetPalette { WidgetPalette(palette.dark ? .dark : .light, scheme: palette.dark ? .dark : .light, tint: BuddyStyle.color(habit.color)) }
}

extension HabitWidgetContent: Equatable {
    /// Without versions every update redraws the design. Actions are left out: they act on the same habits.
    static func == (a: HabitWidgetContent, b: HabitWidgetContent) -> Bool {
        guard let versions = a.versions, versions == b.versions else { return false }
        return a.kind == b.kind && a.size == b.size && a.habit == b.habit && a.habits == b.habits && a.routine == b.routine
            && a.title == b.title && a.today == b.today && a.palette == b.palette
    }
}

/// One arc per habit around a ring, in the habit's color: solid when done, faint when open.
struct TodayRing: View {
    let habits: [Habit]
    let data: BuddyData
    var today = Day()
    let palette: WidgetPalette
    var line: CGFloat = 9
    var body: some View {
        let done = habits.map { Engine.progress($0, day: today, data: data, today: today).success }
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2 - line / 2, center = CGPoint(x: size.width / 2, y: size.height / 2)
            guard radius > 0 else { return }
            let count = max(1, habits.count), segment = 2 * Double.pi / Double(count)
            // Round caps reach past each arc's end, so the gap covers both caps plus a little air.
            let gap = count == 1 ? 0 : min(segment * 0.5, Double(line * 1.6 / radius))
            for i in 0..<count {
                let start = -Double.pi / 2 + Double(i) * segment + gap / 2
                var arc = Path(); arc.addArc(center: center, radius: radius, startAngle: .radians(start), endAngle: .radians(start + segment - gap), clockwise: false)
                let color = habits.isEmpty ? palette.outline : BuddyStyle.color(habits[i].color).opacity(done[i] ? 1 : palette.dark ? 0.24 : 0.2)
                context.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: line, lineCap: count == 1 ? .butt : .round))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

extension Day {
    static let shortWeekday: DateFormatter = { let f = DateFormatter(); f.locale = .autoupdatingCurrent; f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "EEE"; return f }()
}
extension DashboardKind {
    var title: String {
        switch self {
        case .streak: "Streak"; case .month: "This Month"; case .today: "Today Ring"; case .weeks: "20 Weeks"; case .months: "Three Months"; case .list: "Today List"
        case .ring: "Goal Ring"; case .stats: "Stats"; case .year: "This Year"; case .badge: "Next Badge"; case .checks: "Quick Check"; case .week: "This Week"; case .routine: "Routine"
        }
    }
    var symbol: String {
        switch self {
        case .streak: "flame"; case .month: "calendar"; case .today: "circle-check"; case .weeks: "grid-3x3"; case .months: "calendar-range"; case .list: "list-checks"
        case .ring: "circle-gauge"; case .stats: "chart-no-axes-column"; case .year: "calendar-days"; case .badge: "trophy"; case .checks: "layout-grid"; case .week: "chart-column"; case .routine: "list-todo"
        }
    }
    /// The heading a multi-habit design shows unless the widget has its own title.
    var defaultTitle: String { self == .week ? "This Week" : "Today" }
    /// Whether the design at this size shows a heading the widget's title can replace.
    func showsTitle(_ size: WidgetSize) -> Bool { self == .today || self == .list || self == .week || (self == .checks && size == .large) }
    /// Whether the widget's color shows beyond a tinted background; multi-habit designs keep each habit's color.
    var usesAccent: Bool { !(self == .today || self == .list || self == .checks) }
}
extension WidgetStyle {
    var title: String { switch self { case .automatic: "Auto"; case .light: "Light"; case .dark: "Dark"; case .tinted: "Tinted" } }
}
extension WidgetSize {
    var title: String { switch self { case .small: "Small"; case .medium: "Medium"; case .large: "Large" } }
}
extension DashboardKind {
    /// The design's sizes from small to large, for pickers.
    var sizesInOrder: [WidgetSize] { WidgetSize.allCases.filter(sizes.contains) }
}
