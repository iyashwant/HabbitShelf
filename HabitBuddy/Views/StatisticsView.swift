import SwiftUI
import Charts

struct StatisticsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID?
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var review = false
    private var habits: [Habit] { store.data.habits.filter { selected == nil || $0.id == selected! } }
    private var start: Day { Day(rawValue: "\(year)-01-01")! }
    private var end: Day { min(Day(), Day(rawValue: "\(year)-12-31")!) }
    private var days: [Day] { Day.range(start, end) }
    private var completions: Int { habits.reduce(0) { sum, h in sum + days.filter { h.goal(on: $0).mode == .build && Engine.progress(h, day: $0, data: store.data).success }.count } }
    private var eligible: Int { habits.reduce(0) { sum, h in sum + days.filter { h.goal(on: $0).mode == .build && h.available(on: $0, today: Day()) && ($0 < Day() || Engine.progress(h, day: $0, data: store.data).success) }.count } }
    private var accent: Color { BuddyStyle.color(habits.first?.color ?? "mint") }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { Button("All Habits") { selected = nil }.buttonStyle(.bordered).tint(selected == nil ? accent : .secondary)
                            ForEach(store.data.habits) { h in Button { selected = h.id } label: { HabitIcon(habit: h, size: 34) }.buttonStyle(.plain).accessibilityLabel(h.name).accessibilityAddTraits(selected == h.id ? .isSelected : []) }
                        }
                    }
                    HStack { Button { year -= 1 } label: { Image(systemName: "chevron.left") }.disabled(year <= 1970); Spacer(); Text(String(year)).font(.headline); Spacer(); Button { year += 1 } label: { Image(systemName: "chevron.right") }.disabled(year >= Calendar.current.component(.year, from: Date())) }.surface()
                    if let h = habits.first { Heatmap(habit: visualHabit(h), data: aggregateHeatmap(h), weeks: 53, end: end).surface() }
                    HStack { metric("Completions", "\(completions)", "number"); metric("Completion Rate", "\(eligible == 0 ? 0 : Int(Double(completions) / Double(eligible) * 100))%", "percent") }
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Completions / Month").font(.headline)
                        Chart(1...12, id: \.self) { month in
                            let count = monthlyCount(month)
                            AreaMark(x: .value("Month", month), y: .value("Completions", count)).foregroundStyle(accent.opacity(0.2)).interpolationMethod(.monotone)
                            LineMark(x: .value("Month", month), y: .value("Completions", count)).foregroundStyle(accent).interpolationMethod(.monotone)
                        }.chartXAxis { AxisMarks(values: Array(1...12)) { value in AxisValueLabel { if let month = value.as(Int.self) { Text(Calendar.current.shortMonthSymbols[month - 1]).font(.caption2) } } } }.frame(height: 190)
                            .accessibilityLabel("Monthly habit completions for \(year)")
                    }.surface()
                    HStack { metric("Current Streak", "\(habits.map { Engine.stats($0, data: store.data).currentStreak }.max() ?? 0)", "flame.fill"); metric("Best Streak", "\(habits.map { Engine.stats($0, data: store.data).bestStreak }.max() ?? 0)", "flame") }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Completion Time").font(.headline)
                        Chart(0..<24, id: \.self) { hour in
                            BarMark(x: .value("Hour", hour), y: .value("Completions", hourlyCount(hour))).foregroundStyle(accent)
                        }.frame(height: 150).chartXAxis { AxisMarks(values: [0, 6, 12, 18]) { value in AxisValueLabel { if let hour = value.as(Int.self) { Text("\(hour):00").font(.caption2) } } } }
                        Text("Uses the local hour recorded when a build day first reaches its goal. Backfilled days use the time they were entered.").font(.caption2).foregroundStyle(.secondary)
                    }.surface()
                    Text("Rate counts tracked build days through yesterday, plus today when completed. Quit habits are excluded from completion totals. Aggregate streak is the longest selected habit streak and includes quit habits.").font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Monthly totals") { ForEach(1...12, id: \.self) { m in HStack { Text(Calendar.current.monthSymbols[m - 1]); Spacer(); Text("\(monthlyCount(m))").monospacedDigit() }.font(.caption).padding(.vertical, 3) } }
                }.padding(20)
            }.navigationTitle("Statistics").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Share Year", systemImage: "square.and.arrow.up") { review = true } }; ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(isPresented: $review) { YearReviewView(year: year, habits: habits) }
        }
    }
    private func monthlyCount(_ month: Int) -> Int {
        let prefix = String(format: "%04d-%02d", year, month)
        return habits.reduce(0) { sum, h in sum + days.filter { $0.month == prefix && h.goal(on: $0).mode == .build && Engine.progress(h, day: $0, data: store.data).success }.count }
    }
    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 13) { HStack { Spacer(); Image(systemName: icon).foregroundStyle(accent).padding(7).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8)) }; Text(value).font(.title.bold()).monospacedDigit(); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).surface()
    }
    private func aggregateHeatmap(_ sample: Habit) -> BuddyData {
        guard selected == nil else { return store.data }
        var result = store.data
        result.records = result.records.filter { $0.value.habitID != sample.id }
        for day in days {
            var record = Record(habitID: sample.id, day: day)
            record.amount = habits.contains { $0.goal(on: day).mode == .build && Engine.progress($0, day: day, data: store.data).success } ? 1_000 : 0
            result.records[record.key] = record
        }
        return result
    }
    private func visualHabit(_ sample: Habit) -> Habit {
        guard selected == nil else { return sample }
        var h = sample; h.created = start; h.archived = nil; h.pauses = []; h.goals = [Goal(from: start)]; return h
    }
    private func hourlyCount(_ hour: Int) -> Int {
        store.data.records.values.filter { record in
            guard record.day >= start, record.day <= end, record.completionHour == hour, let h = habits.first(where: { $0.id == record.habitID }) else { return false }
            return h.goal(on: record.day).mode == .build && Engine.progress(h, day: record.day, data: store.data).success
        }.count
    }
}
