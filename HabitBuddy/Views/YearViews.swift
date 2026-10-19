import SwiftUI

/// Every year of a habit as a card of days, newest first, with its longest run and completion.
struct YearHistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let habitID: UUID
    var body: some View {
        Group {
            if let habit = store.habit(habitID) {
                let palette = WidgetPalette(.automatic, scheme: scheme, tint: BuddyStyle.color(habit.color)), today = Day()
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(years(habit, today), id: \.self) { year in
                            let stats = Engine.yearStats(habit, year: year, data: store.data, today: today)
                            VStack(alignment: .leading, spacing: 16) {
                                Text(String(year)).font(BuddyFont.text(28, .heavy)).foregroundStyle(BuddyStyle.text(scheme))
                                YearDots(habit: habit, data: store.data, year: year, today: today, palette: palette)
                                VStack(alignment: .leading, spacing: 8) {
                                    statRow("Longest streak", "\(stats.longestRun) \(stats.longestRun == 1 ? "day" : "days")")
                                    statRow("Completion", "\(Int((stats.rate * 100).rounded()))% (\(stats.completions) of \(stats.eligible) days)")
                                }
                            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).panel(radius: 20, border: 0.09)
                        }
                    }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
                }.scrollIndicators(.hidden)
                .topBar { PageBar(title: habit.name) { dismiss() } }
            } else { ContentUnavailableView("Habit unavailable", systemImage: "archivebox") }
        }.background(BuddyStyle.canvas(scheme)).toolbar(.hidden, for: .navigationBar)
    }
    private func statRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(title).foregroundStyle(BuddyStyle.secondaryText(scheme)).frame(width: 120, alignment: .leading)
            Text(value).font(BuddyFont.text(15, .semibold)).foregroundStyle(BuddyStyle.text(scheme))
        }.font(BuddyFont.text(15))
    }
    private func years(_ habit: Habit, _ today: Day) -> [Int] {
        let first = Int(habit.created.rawValue.prefix(4))!, last = Int(today.rawValue.prefix(4))!
        return first <= last ? Array((first...last).reversed()) : []
    }
}

/// A year of days in reading order, 21 to a row; the current year stops at today.
struct YearDots: View {
    let habit: Habit
    @ViewData var data: BuddyData
    let year: Int
    var today = Day()
    let palette: WidgetPalette
    private let columns = 21
    var body: some View {
        let first = Day(rawValue: String(format: "%04d-01-01", year))!, last = min(Day(rawValue: String(format: "%04d-12-31", year))!, today)
        let count = max(0, first.distance(to: last) + 1), rows = max(1, (count + columns - 1) / columns), gapRatio: CGFloat = 0.22
        let marks = (0..<count).map { DayMark(habit, first.adding($0), data, today: today) }
        Canvas { context, size in
            let cell = size.width / (CGFloat(columns) + CGFloat(columns - 1) * gapRatio), gap = cell * gapRatio
            for n in 0..<count {
                let mark = marks[n]
                let rect = CGRect(x: CGFloat(n % columns) * (cell + gap), y: CGFloat(n / columns) * (cell + gap), width: cell, height: cell)
                context.fill(Path(roundedRect: rect, cornerRadius: cell * 0.3), with: .color(mark == .inactive ? palette.outline.opacity(0.6) : mark.fill(palette)))
            }
        }
        .aspectRatio((CGFloat(columns) + CGFloat(columns - 1) * gapRatio) / (CGFloat(rows) + CGFloat(rows - 1) * gapRatio), contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(year): \(marks.filter { $0 == .done }.count) days done")
    }
}

/// Twelve months of one year on a single page, ready to share as an image.
struct YearCalendarView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let habitID: UUID
    @State private var year = Int(Day().rawValue.prefix(4))!
    @State private var export: SharedImage?
    @State private var message: String?
    @State private var rendering = false
    var body: some View {
        Group {
            if let habit = store.habit(habitID) {
                let firstYear = Int(habit.created.rawValue.prefix(4))!, thisYear = Int(Day().rawValue.prefix(4))!
                ScrollView {
                    VStack(spacing: 16) {
                        HStack {
                            MonthArrow(next: false) { year -= 1 }.disabled(year <= min(firstYear, thisYear))
                            Spacer()
                            Text(String(year)).font(BuddyFont.mono(15)).foregroundStyle(BuddyStyle.text(scheme))
                            Spacer()
                            MonthArrow(next: true) { year += 1 }.disabled(year >= thisYear)
                        }.accessibilityElement(children: .contain)
                        YearPoster(habit: habit, data: store.data, year: year, scheme: scheme)
                        if let message { Text(message).font(BuddyFont.text(13)).foregroundStyle(.red) }
                    }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
                }.scrollIndicators(.hidden)
                .topBar { PageBar(title: "Year Calendar", trailing: "share", trailingLabel: "Share Year Calendar", trailingAction: { share(habit) }) { dismiss() } }
            } else { ContentUnavailableView("Habit unavailable", systemImage: "archivebox") }
        }.background(BuddyStyle.canvas(scheme)).toolbar(.hidden, for: .navigationBar)
        .sheet(item: $export) { image in NativeShareSheet(items: [image.url]) }
    }
    @MainActor private func share(_ habit: Habit) {
        guard !rendering else { return }
        rendering = true; message = nil
        let poster = YearPoster(habit: habit, data: store.data, year: year, scheme: scheme).padding(16).background(BuddyStyle.canvas(scheme)).environment(\.colorScheme, scheme)
        Task {
            defer { rendering = false }
            do { export = SharedImage(url: try await ImageExport.png(poster, width: 420, scale: 3, name: "\(habit.name)-\(year).png")) }
            catch { message = error.localizedDescription }
        }
    }
}
struct SharedImage: Identifiable { let id = UUID(); let url: URL }

struct YearPoster: View {
    let habit: Habit
    @ViewData var data: BuddyData
    let year: Int
    let scheme: ColorScheme
    var body: some View {
        let today = Day(), tint = BuddyStyle.color(habit.color), palette = WidgetPalette(.automatic, scheme: scheme, tint: tint)
        let stats = Engine.yearStats(habit, year: year, data: data, today: today), shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name).font(BuddyFont.text(30, .heavy)).foregroundStyle(palette.primary).lineLimit(2).minimumScaleFactor(0.7)
                    Text(String(year)).font(BuddyFont.text(22, .bold)).foregroundStyle(tint)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(stats.completions) of \(stats.eligible) days • \(Int((stats.rate * 100).rounded()))%")
                    Text("\(stats.longestRun) days: longest streak")
                    Text("HabitShelf").foregroundStyle(palette.secondary)
                }.font(BuddyFont.text(12, .medium)).foregroundStyle(palette.primary).multilineTextAlignment(.trailing)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 3), alignment: .leading, spacing: 20) {
                ForEach(1...12, id: \.self) { m in
                    let month = Day(rawValue: String(format: "%04d-%02d-01", year, m))!
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Day.shortMonth.string(from: month.date)).font(BuddyFont.text(16, .semibold)).foregroundStyle(palette.primary)
                        MonthDots(habit: habit, data: data, month: month, today: today, palette: palette, gap: 2.5).frame(height: 70, alignment: .topLeading)
                    }
                }
            }
        }
        .padding(20).background(palette.background(shape)).overlay { shape.strokeBorder(BuddyStyle.border(scheme, 0.08), lineWidth: 1) }
    }
}

/// Back control with a centered title, and an optional trailing action.
struct PageBar: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    var trailing: String?
    var trailingLabel = ""
    var trailingAction: (() -> Void)?
    var back: () -> Void
    var body: some View {
        ZStack {
            Text(title).font(BuddyFont.text(18, .bold)).foregroundStyle(BuddyStyle.text(scheme)).lineLimit(1).padding(.horizontal, 56)
            GlassGroup(spacing: 8) {
                HStack {
                    CircleControl(symbol: "chevron-left", label: "Back", size: 38, glyph: 12.5, action: back)
                    Spacer()
                    if let trailing, let trailingAction { CircleControl(symbol: trailing, label: trailingLabel, size: 38, glyph: 17, action: trailingAction) }
                }
            }
        }.padding(.horizontal, 12).padding(.top, 8.8).padding(.bottom, 8)
    }
}
