import SwiftUI
import Charts

/// Patterns in the history: strongest and weakest weekdays, time of day, the monthly trend and habits that slip together.
struct InsightsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var range = InsightRange.quarter
    @State private var selected: UUID?
    @State private var summary: InsightsSummary?
    @State private var pairs: [InsightsSummary.LapsePair] = []
    enum InsightRange: CaseIterable { case month, quarter, year, all
        var title: String { switch self { case .month: "30 Days"; case .quarter: "90 Days"; case .year: "Year"; case .all: "All" } }
        func from(_ today: Day) -> Day { switch self { case .month: today.adding(-29); case .quarter: today.adding(-89); case .year: today.adding(-364); case .all: Habit.earliestStart } }
    }
    private var accent: Color { store.habit(selected ?? UUID()).map { BuddyStyle.color($0.color) } ?? BuddyStyle.purple }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HabitFilterBar(habits: store.data.active, selection: $selected)
                SegmentedChoice(selection: $range, options: InsightRange.allCases.map { ($0, $0.title) })
                if store.data.active.isEmpty { ContentUnavailableView("No habits yet", systemImage: "sparkles", description: Text("Insights appear once you've tracked a few days.")) }
                else if let summary { content(summary) }
                else { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(BuddyStyle.canvas(scheme)).toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { PageBar(title: "Insights") { dismiss() } }
        .task(id: "\(range)-\(selected?.uuidString ?? "all")") { await refresh() }
        .onChange(of: store.data) { _, _ in Task { await refresh() } }
    }
    private func refresh() async {
        let data = store.data, ids = selected.map { [$0] }, from = range.from(Day()), today = Day(), selected = selected
        let result = await Task.detached(priority: .userInitiated) { () -> (InsightsSummary, [InsightsSummary.LapsePair]) in
            let summary = InsightsSummary(data: data, habitIDs: ids, from: from, today: today)
            guard let selected else { return (summary, summary.pairs) }
            // A single habit can still slip together with others, so pairs always look across every habit.
            let all = InsightsSummary(data: data, from: from, today: today, maxPairs: 100)
            return (summary, Array(all.pairs.filter { $0.first == selected || $0.second == selected }.prefix(3)))
        }.value
        summary = result.0; pairs = result.1
    }
    @ViewBuilder private func content(_ s: InsightsSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(percent(s.total.rate))").font(BuddyFont.text(44, .heavy)).foregroundStyle(BuddyStyle.text(scheme)).monospacedDigit()
            Text(s.total.eligible == 0 ? "No tracked days in this range yet." : "\(s.total.done) of \(s.total.eligible) tracked days kept").font(BuddyFont.text(14)).foregroundStyle(BuddyStyle.secondaryText(scheme))
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).surface(padding: 0, radius: 20, tint: accent)
        weekdays(s)
        timeOfDay(s)
        trend(s)
        slipTogether()
    }
    private func weekdays(_ s: InsightsSummary) -> some View {
        let names = Calendar.current.weekdaySymbols, order = (0..<7).map { (store.data.settings.weekStart - 1 + $0) % 7 + 1 }
        let detail: String = {
            guard let best = s.bestWeekday else { return "Track a couple of weeks to see your strongest and weakest days." }
            // Within five points, naming a best and worst day would read more into the data than is there.
            if spread(s) < 0.05 { let rates = s.weekdays.filter { $0.eligible >= 2 }.map(\.rate); return "Your weekdays are about even: \(percent(rates.min() ?? 0))–\(percent(rates.max() ?? 0)) kept on each." }
            var text = "You're most consistent on \(names[best - 1])s (\(percent(s.weekdays[best - 1].rate)))."
            if let worst = s.worstWeekday, s.weekdays[worst - 1].rate < s.weekdays[best - 1].rate { text += " \(names[worst - 1])s are hardest (\(percent(s.weekdays[worst - 1].rate)))." }
            return text
        }()
        return ExploreSection(title: "Weekdays", detail: detail) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(order, id: \.self) { weekday in
                    let rate = s.weekdays[weekday - 1], even = spread(s) < 0.05, best = !even && weekday == s.bestWeekday, worst = !even && weekday == s.worstWeekday && s.worstWeekday != nil
                    VStack(spacing: 6) {
                        Text(rate.eligible == 0 ? "–" : "\(Int((rate.rate * 100).rounded()))").font(BuddyFont.mono(10)).foregroundStyle(BuddyStyle.tertiaryText(scheme))
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(best ? accent : worst ? BuddyStyle.color("coral") : accent.opacity(0.35))
                            .frame(height: max(6, 96 * rate.rate))
                        Text(String(Calendar.current.shortWeekdaySymbols[weekday - 1].prefix(2))).font(BuddyFont.mono(11, best || worst ? .semibold : .regular)).foregroundStyle(best || worst ? BuddyStyle.text(scheme) : BuddyStyle.secondaryText(scheme))
                    }.frame(maxWidth: .infinity, maxHeight: 140, alignment: .bottom)
                    .accessibilityElement(children: .ignore).accessibilityLabel("\(names[weekday - 1]), \(rate.eligible == 0 ? "no tracked days" : "\(percent(rate.rate)) kept")")
                }
            }.frame(height: 140)
        }
    }
    private func timeOfDay(_ s: InsightsSummary) -> some View {
        let buckets: [(String, String, [Int])] = [("Morning", "sunrise", Array(5...11)), ("Afternoon", "sun", Array(12...16)), ("Evening", "sunset", Array(17...21)), ("Night", "moon", [22, 23, 0, 1, 2, 3, 4])]
        let counts = buckets.map { $0.2.reduce(0) { $0 + s.hours[$1] } }, total = counts.reduce(0, +)
        let top = counts.indices.max { counts[$0] < counts[$1] } ?? 0
        return ExploreSection(title: "Time of Day", detail: total == 0 ? "Completion times appear once you check in on the day." : "Most check-ins happen in the \(buckets[top].0.lowercased()) (\(percent(Double(counts[top]) / Double(total))))." ) {
            VStack(spacing: 10) {
                ForEach(buckets.indices, id: \.self) { i in
                    HStack(spacing: 10) {
                        LucideIcon(buckets[i].1, size: 18).foregroundStyle(i == top && total > 0 ? accent : BuddyStyle.secondaryText(scheme))
                        Text(buckets[i].0).font(BuddyFont.text(14)).foregroundStyle(BuddyStyle.text(scheme)).frame(width: 82, alignment: .leading)
                        GeometryReader { proxy in
                            Capsule().fill(BuddyStyle.border(scheme, 0.08))
                                .overlay(alignment: .leading) { Capsule().fill(accent.opacity(i == top ? 1 : 0.45)).frame(width: counts[i] == 0 ? 0 : max(6, proxy.size.width * Double(counts[i]) / Double(total))) }
                        }.frame(height: 8)
                        Text("\(counts[i])").font(BuddyFont.mono(12)).foregroundStyle(BuddyStyle.secondaryText(scheme)).frame(width: 34, alignment: .trailing)
                    }.accessibilityElement(children: .ignore).accessibilityLabel("\(buckets[i].0), \(counts[i]) check-ins")
                }
            }
        }
    }
    private func trend(_ s: InsightsSummary) -> some View {
        let points = s.months.filter { $0.rate.eligible > 0 }
        let detail: String = {
            guard let last = points.last else { return "Your monthly trend appears after the first tracked month." }
            let name = Calendar.current.monthSymbols[Int(last.month.rawValue.dropFirst(5).prefix(2))! - 1]
            guard points.count > 1 else { return "\(name): \(percent(last.rate.rate)) kept." }
            let change = Int(((last.rate.rate - points[points.count - 2].rate.rate) * 100).rounded())
            return "\(name): \(percent(last.rate.rate)) kept, \(change == 0 ? "the same as" : change > 0 ? "up \(change) points from" : "down \(-change) points from") the month before."
        }()
        return ExploreSection(title: "Monthly Trend", detail: detail) {
            // Months are categories: civil month keys must not shift with the device's time zone.
            Chart(points, id: \.month) { point in
                let month = Day.shortMonth.string(from: point.month.date)
                AreaMark(x: .value("Month", month), y: .value("Kept", point.rate.rate * 100)).foregroundStyle(accent.opacity(0.18)).interpolationMethod(.monotone)
                LineMark(x: .value("Month", month), y: .value("Kept", point.rate.rate * 100)).foregroundStyle(accent).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.monotone)
                PointMark(x: .value("Month", month), y: .value("Kept", point.rate.rate * 100)).foregroundStyle(accent).symbolSize(16)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(values: [0, 50, 100]) { value in AxisGridLine().foregroundStyle(BuddyStyle.border(scheme, 0.08)); AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)%").font(BuddyFont.mono(9)) } } } }
            .chartXAxis { AxisMarks { _ in AxisValueLabel().font(BuddyFont.mono(9)) } }
            .frame(height: 150)
            .accessibilityLabel("Kept days by month for the last twelve months")
        }
    }
    private func slipTogether() -> some View {
        ExploreSection(title: "Slip Together", detail: pairs.isEmpty ? "No two habits tend to slip on the same days. Missing one doesn't drag the others down." : "These habits are often missed on the same days. Pairing them up, or giving the first one a reminder, can protect both.") {
            ForEach(pairs, id: \.first) { pair in
                if let a = store.habit(pair.first), let b = store.habit(pair.second) {
                    HStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) { HabitIcon(habit: a, size: 34); HabitIcon(habit: b, size: 26).background(BuddyStyle.panel(scheme), in: RoundedRectangle(cornerRadius: 8)).offset(x: 10, y: 8) }.padding(.trailing, 8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(a.name) & \(b.name)").font(BuddyFont.text(15, .semibold)).foregroundStyle(BuddyStyle.text(scheme)).lineLimit(1)
                            Text("Missed together on \(pair.together) of \(pair.either) days").font(BuddyFont.text(12.5)).foregroundStyle(BuddyStyle.secondaryText(scheme))
                        }
                        Spacer(minLength: 4)
                        Text(percent(pair.share)).font(BuddyFont.mono(12, .semibold)).foregroundStyle(BuddyStyle.color("coral")).padding(.horizontal, 9).frame(height: 26).background(BuddyStyle.color("coral").opacity(0.13), in: Capsule())
                    }.padding(.vertical, 4).accessibilityElement(children: .combine)
                }
            }
        }
    }
    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    private func spread(_ s: InsightsSummary) -> Double { let rates = s.weekdays.filter { $0.eligible >= 2 }.map(\.rate); return (rates.max() ?? 0) - (rates.min() ?? 0) }
}
