import SwiftUI

extension Day {
    var yearNumber: Int { Int(rawValue.prefix(4))! }
}

extension CalendarLayout {
    var title: String {
        switch self { case .grid: "Compact Grid"; case .month: "Monthly Calendars"; case .year: "Yearly Calendars" }
    }
    var detail: String {
        switch self {
        case .grid: "Small month cards, three across"
        case .month: "A full month for each habit"
        case .year: "Twelve months for each habit"
        }
    }
    var symbol: String {
        switch self { case .grid: "layout-grid"; case .month: "calendar-days"; case .year: "grid-3x3" }
    }
}

/// The Month page keeps its own choice, so returning from another bottom-bar page restores it.
struct CalendarLayoutPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Calendar Layout")
            VStack(spacing: 8) {
                ForEach(CalendarLayout.allCases, id: \.self) { layout in
                    let selected = (store.settings.calendarLayout ?? .grid) == layout
                    Button {
                        store.change { $0.settings.calendarLayout = layout == .grid ? nil : layout }
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            LucideIcon(layout.symbol, size: 22).foregroundStyle(selected ? accent.color : BuddyStyle.secondaryText(scheme))
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(layout.title).font(BuddyFont.text(16, .semibold)).foregroundStyle(BuddyStyle.text(scheme))
                                Text(layout.detail).font(BuddyFont.text(12.5)).foregroundStyle(BuddyStyle.secondaryText(scheme))
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if selected { LucideIcon("check", size: 20).foregroundStyle(accent.color) }
                        }.padding(14).frame(maxWidth: .infinity, minHeight: 70)
                            .background(BuddyStyle.field(scheme), in: RoundedRectangle(cornerRadius: 16))
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(FlatButtonStyle())
                        .accessibilityElement(children: .ignore).accessibilityLabel(layout.title)
                        .accessibilityValue(selected ? "Selected" : "")
                        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityIdentifier("calendar-layout-\(layout.rawValue)")
                }
            }.padding(.horizontal, 16)
            Spacer(minLength: 16)
        }
        .presentationDetents([.height(365), .large])
        .buddySheet(partial: true)
    }
}

/// Numbered, full-width month cards, as in the owner's video. Day taps use the shared day editor.
struct CalendarMonthCard: View, Equatable {
    @Environment(\.colorScheme) private var scheme
    let habit: Habit
    @ViewData var data: BuddyData
    let version: HabitVersion
    let month: Day
    var today = Day()
    var onOpen: () -> Void
    var onEdit: (Day) -> Void
    var body: some View {
        let first = month.startOfWeek(data.settings.weekStart), tint = BuddyStyle.color(habit.color)
        VStack(spacing: 14) {
            Button(action: onOpen) {
                HStack(spacing: 9) {
                    BuddyGlyph(symbol: habit.symbol, size: 19)
                    Text(habit.name).font(BuddyFont.text(19, .bold)).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }.foregroundStyle(tint).contentShape(Rectangle())
            }.buttonStyle(FlatButtonStyle()).accessibilityLabel("Open \(habit.name)")
            Text(Day.fullMonthYear.string(from: month.date)).font(BuddyFont.text(17, .semibold))
                .foregroundStyle(BuddyStyle.text(scheme))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(0..<7, id: \.self) { column in
                    Text(Heatmap.weekday(data.settings.weekStart, column)).font(BuddyFont.text(11, .medium))
                        .foregroundStyle(BuddyStyle.secondaryText(scheme)).frame(maxWidth: .infinity).frame(height: 24)
                        .accessibilityHidden(true)
                }
                ForEach(Day.range(first, first.adding(41))) { day in
                    Button { onEdit(day) } label: {
                        CalendarDay(habit: habit, day: day, data: data, inMonth: day.month == month.month)
                            .opacity(day.month == month.month ? 1 : 0.3)
                            .contentShape(Rectangle())
                    }.buttonStyle(FlatButtonStyle())
                        .disabled(!habit.loggable(on: day, today: today))
                        .accessibilityLabel("\(habit.name), \(day.rawValue)")
                        .accessibilityValue(dayValue(day))
                        .accessibilityHint("Edit amount and note")
                        .accessibilityIdentifier("calendar-day-\(habit.id)-\(day.rawValue)")
                }
            }
        }.padding(16).frame(maxWidth: .infinity).panel(radius: 22, border: 0.06)
            .accessibilityIdentifier("calendar-month-card")
    }
    private func dayValue(_ day: Day) -> String {
        let progress = Engine.progress(habit, day: day, data: data, today: today)
        return progress.success ? "Complete" : progress.slip ? "Slip" : progress.frozen ? "Frozen" : "Incomplete"
    }
    static func == (a: Self, b: Self) -> Bool {
        a.version == b.version && a.habit == b.habit && a.month == b.month && a.today == b.today
    }
}

/// A scrollable card per habit, with the twelve month grids and the selected year's actual statistics.
struct CalendarYearCard: View, Equatable {
    @Environment(\.colorScheme) private var scheme
    let habit: Habit
    @ViewData var data: BuddyData
    let version: HabitVersion
    let year: Int
    var today = Day()
    var onOpen: () -> Void
    var body: some View {
        let palette = WidgetPalette(.automatic, scheme: scheme, tint: BuddyStyle.color(habit.color))
        let stats = Engine.yearStats(habit, year: year, data: data, today: today)
        VStack(alignment: .leading, spacing: 18) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(habit.name).font(BuddyFont.text(19, .bold)).foregroundStyle(palette.primary).lineLimit(2)
                        Text(String(year)).font(BuddyFont.text(14, .semibold)).foregroundStyle(palette.tint)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(stats.completions) of \(stats.eligible) days · \(Int((stats.rate * 100).rounded()))%")
                        Text("\(stats.longestRun) \(stats.longestRun == 1 ? "day" : "days"): longest streak")
                    }.font(BuddyFont.text(10.5, .medium)).foregroundStyle(palette.secondary).multilineTextAlignment(.trailing)
                }.contentShape(Rectangle())
            }.buttonStyle(FlatButtonStyle()).accessibilityLabel("Open \(habit.name), \(year)")
            BuddyStyle.border(scheme, 0.08).frame(height: 1)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), alignment: .leading, spacing: 20) {
                ForEach(1...12, id: \.self) { number in
                    let month = Day(rawValue: String(format: "%04d-%02d-01", year, number))!
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Day.shortMonth.string(from: month.date)).font(BuddyFont.text(12, .semibold))
                            .foregroundStyle(month.month == today.month ? palette.primary : palette.secondary)
                        MonthDots(habit: habit, data: data, month: month, today: today, palette: palette, gap: 2.5, outlineToday: true)
                            .frame(height: 78, alignment: .topLeading)
                    }
                }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).panel(radius: 22, border: 0.06)
            .accessibilityIdentifier("calendar-year-card")
    }
    static func == (a: Self, b: Self) -> Bool {
        a.version == b.version && a.habit == b.habit && a.year == b.year && a.today == b.today
    }
}
