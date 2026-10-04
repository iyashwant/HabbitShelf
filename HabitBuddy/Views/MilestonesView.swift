import SwiftUI

/// Streak and check-in badges: for one habit, or a list of every habit's progress.
struct MilestonesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let habitID: UUID?
    var body: some View {
        let today = Day()
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let id = habitID {
                    if let habit = store.habit(id) { detail(habit, store.summaries.milestones(habit, data: store.data, today: today), today) }
                    else { ContentUnavailableView("Habit unavailable", systemImage: "archivebox") }
                } else if store.visible.active.isEmpty {
                    ContentUnavailableView("No habits yet", systemImage: "trophy", description: Text("Badges appear as your streaks and check-ins grow."))
                } else {
                    ForEach(store.visible.active) { habit in row(habit, store.summaries.milestones(habit, data: store.data, today: today)) }
                }
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(BuddyStyle.canvas(scheme)).toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { PageBar(title: habitID.flatMap { store.habit($0)?.name } ?? "Milestones") { dismiss() } }
    }
    private func row(_ habit: Habit, _ m: Milestones) -> some View {
        NavigationLink(value: OverviewRoute.milestones(habit.id)) {
            HStack(spacing: 12) {
                HabitIcon(habit: habit, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(habit.name).font(BuddyFont.text(16, .semibold)).foregroundStyle(BuddyStyle.text(scheme)).lineLimit(1)
                    Text(next(m, short: true)).font(BuddyFont.text(12.5)).foregroundStyle(BuddyStyle.secondaryText(scheme)).lineLimit(2)
                }
                Spacer(minLength: 6)
                HStack(spacing: 4) { LucideIcon("trophy", size: 15); Text("\(m.earned)").font(BuddyFont.mono(13, .semibold)) }.foregroundStyle(BuddyStyle.color(habit.color))
                LucideIcon("chevron-right", size: 15).foregroundStyle(BuddyStyle.tertiaryText(scheme))
            }.padding(14).panel(radius: 18, border: 0.09).contentShape(Rectangle())
        }.buttonStyle(FlatButtonStyle())
    }
    private func next(_ m: Milestones, short: Bool = false) -> String {
        if let step = m.nextStreak {
            let left = step - m.currentStreak
            return short ? "\(left) \(left == 1 ? "day" : "days") to the \(step)-day badge" : "\(left) more \(left == 1 ? "day" : "days") in a row to a \(step)-day streak"
        }
        if let step = m.nextTotal { return "\(step - m.total) more check-ins to \(step)" }
        return "Every badge earned"
    }
    @ViewBuilder private func detail(_ habit: Habit, _ m: Milestones, _ today: Day) -> some View {
        let color = BuddyStyle.color(habit.color), total = Milestones.streakSteps.count + Milestones.totalSteps.count
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                HabitIcon(habit: habit, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(m.earned) of \(total) badges").font(BuddyFont.text(20, .heavy)).foregroundStyle(BuddyStyle.text(scheme))
                    Text(next(m)).font(BuddyFont.text(13)).foregroundStyle(BuddyStyle.secondaryText(scheme))
                }
            }
            HStack(spacing: 8) {
                MetricChip(symbol: "flame", text: "\(m.currentStreak) now", color: color)
                MetricChip(symbol: "trophy", text: "\(m.bestStreak) best", color: color)
                MetricChip(symbol: "check", text: "\(m.total) total", color: color)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).surface(padding: 0, radius: 22, tint: color)
        ExploreSection(title: "Streak", detail: habit.currentGoal.cadence == .none && habit.currentGoal.mode == .build ? "This habit has no streak goal, so only check-in badges grow." : nil) {
            grid(Milestones.streakSteps.map { step in (step, "DAYS", step <= m.bestStreak, Double(m.currentStreak) / Double(step), nil) }, color)
        }
        ExploreSection(title: habit.currentGoal.mode == .quit ? "Clean Days" : "Check-ins") {
            grid(Milestones.totalSteps.map { step in (step, step == 1 ? "FIRST" : "TOTAL", step <= m.total, Double(m.total) / Double(step), m.totalReached[step]) }, color)
        }
        if store.data.settings.freezesPerMonth > 0 && habit.currentGoal.mode == .build && habit.currentGoal.cadence == .daily {
            let used = Engine.freezesUsed(habit, month: today, data: store.data), left = max(0, store.data.settings.freezesPerMonth - used)
            HStack(spacing: 12) {
                LucideIcon("snowflake", size: 20).foregroundStyle(BuddyStyle.freeze).frame(width: 40, height: 40).background(BuddyStyle.freeze.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(left) streak \(left == 1 ? "freeze" : "freezes") left this month").font(BuddyFont.text(15, .semibold)).foregroundStyle(BuddyStyle.text(scheme))
                    Text("Press and hold a missed day in the calendar, then choose Edit Progress to freeze it.").font(BuddyFont.text(12.5)).foregroundStyle(BuddyStyle.secondaryText(scheme))
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).panel(radius: 18, border: 0.09)
        }
    }
    private func grid(_ badges: [(Int, String, Bool, Double, Day?)], _ color: Color) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
            ForEach(badges, id: \.0) { value, caption, earned, progress, day in
                MilestoneBadge(value: value, caption: caption, earned: earned, progress: progress, color: color, day: day)
            }
        }
    }
}

struct MilestoneBadge: View {
    @Environment(\.colorScheme) private var scheme
    let value: Int
    let caption: String
    let earned: Bool
    let progress: Double
    let color: Color
    var day: Day?
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(earned ? color.opacity(0.2) : BuddyStyle.border(scheme, 0.05))
                Circle().strokeBorder(earned ? color : BuddyStyle.border(scheme, 0.12), lineWidth: earned ? 2 : 1)
                if !earned && progress > 0 { Circle().trim(from: 0, to: min(1, progress)).stroke(color.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90)).padding(1) }
                VStack(spacing: 0) {
                    Text(value >= 1_000 ? "1K" : "\(value)").font(BuddyFont.text(19, .heavy)).monospacedDigit().foregroundStyle(earned ? BuddyStyle.text(scheme) : BuddyStyle.tertiaryText(scheme))
                    Text(caption).font(BuddyFont.text(7.5, .bold)).tracking(0.5).foregroundStyle(earned ? color : BuddyStyle.tertiaryText(scheme))
                }
            }.frame(width: 64, height: 64)
            Text(day.map { "\(Day.shortMonth.string(from: $0.date)) \(Int($0.rawValue.suffix(2))!)" } ?? (earned ? "Earned" : " ")).font(BuddyFont.mono(10)).foregroundStyle(BuddyStyle.tertiaryText(scheme))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(caption.lowercased()), \(earned ? "earned" : "\(Int((min(1, progress) * 100).rounded())) percent")")
    }
}
