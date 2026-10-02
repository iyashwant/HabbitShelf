import SwiftUI
import WidgetKit
import AppIntents

struct BuddyEntry: TimelineEntry {
    let date: Date
    let data: BuddyData
    let habitID: UUID?
    let error: String?
    var habit: Habit? { data.active.first { $0.id == habitID } ?? (habitID == nil ? data.active.first : nil) }
}
struct BuddyProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BuddyEntry { entry(nil) }
    func snapshot(for configuration: ChooseHabitIntent, in context: Context) async -> BuddyEntry { entry(configuration.habit?.id) }
    func timeline(for configuration: ChooseHabitIntent, in context: Context) async -> Timeline<BuddyEntry> {
        let current = entry(configuration.habit?.id)
        let midnight = Calendar.current.startOfDay(for: Date()).addingTimeInterval(25 * 3_600)
        let nextMidnight = Calendar.current.startOfDay(for: midnight)
        return Timeline(entries: [current], policy: .after(min(Date().addingTimeInterval(900), nextMidnight)))
    }
    private func entry(_ id: UUID?) -> BuddyEntry {
        guard AppEnvironment.hasSharedContainer else { return BuddyEntry(date: Date(), data: BuddyData(), habitID: id, error: "Configure App Group storage in Xcode.") }
        do { return BuddyEntry(date: Date(), data: try AppEnvironment.repository.load(), habitID: id, error: nil) }
        catch { return BuddyEntry(date: Date(), data: BuddyData(), habitID: id, error: "Open Habit Buddy to recover your data.") }
    }
}
struct SingleHabitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BuddyEntry
    var body: some View {
        if let habit = entry.habit {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HabitIcon(habit: habit, size: 28)
                    VStack(alignment: .leading) { Text(habit.name).font(.caption.weight(.semibold)).lineLimit(1); if family != .systemSmall && !habit.detail.isEmpty { Text(habit.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) } }
                    Spacer(minLength: 0)
                    WidgetHabitAction(habit: habit, day: Day(entry.date), data: entry.data)
                }
                Heatmap(habit: habit, data: entry.data, weeks: family == .systemSmall ? 12 : 25, labels: false).frame(maxHeight: .infinity)
            }.widgetURL(URL(string: "habitbuddy://\(habit.id.uuidString)"))
        } else { VStack(alignment: .leading, spacing: 8) { Image(systemName: "square.grid.3x3.fill").foregroundStyle(BuddyStyle.purple); Text(entry.error ?? "Create a habit, then choose it in Edit Widget.").font(.caption) }.widgetURL(URL(string: "habitbuddy://home")) }
    }
}
struct CompactHabitsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BuddyEntry
    var body: some View {
        let count = family == .systemLarge ? 8 : 3
        let days = family == .systemLarge ? 11 : 10
        if entry.data.active.isEmpty { Text(entry.error ?? "Create habits in Habit Buddy.").font(.caption).widgetURL(URL(string: "habitbuddy://home")) }
        else {
            VStack(spacing: 6) {
                ForEach(entry.data.active.prefix(count)) { habit in
                    HStack(spacing: 5) {
                        Link(destination: URL(string: "habitbuddy://\(habit.id.uuidString)")!) { HabitIcon(habit: habit, size: 23) }
                        ForEach(Day.range(Day(entry.date).adding(-(days - 1)), Day(entry.date))) { day in
                            WidgetHabitAction(habit: habit, day: day, data: entry.data, compact: true).disabled(!habit.available(on: day, today: Day()))
                        }
                    }.frame(maxHeight: .infinity)
                }
            }
        }
    }
}
struct WidgetHabitAction: View {
    let habit: Habit
    let day: Day
    let data: BuddyData
    var compact = false
    var body: some View {
        let goal = habit.goal(on: day), p = Engine.progress(habit, day: day, data: data)
        if goal.tracking != .yesNo && (goal.mode == .quit || goal.tap == .enterTotal || p.success) {
            Link(destination: URL(string: "habitbuddy://\(habit.id.uuidString)?day=\(day.rawValue)")!) { label }
        } else {
            Button(intent: WidgetLogIntent(habit.id, day: day)) { label }.buttonStyle(.plain)
        }
    }
    @ViewBuilder private var label: some View {
        if compact { DayTile(habit: habit, day: day, data: data, size: 22) }
        else { CompletionBadge(habit: habit, data: data, day: day, size: 28).accessibilityLabel("Log \(habit.name)") }
    }
}
struct SingleHabitWidget: Widget {
    let kind = "SingleHabit"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ChooseHabitIntent.self, provider: BuddyProvider()) { entry in SingleHabitWidgetView(entry: entry).containerBackground(for: .widget) { Color(white: 0.09) }.environment(\.colorScheme, .dark) }
            .configurationDisplayName("Habit Grid").description("Your habit’s contribution grid with a quick check-in.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
struct CompactHabitsWidget: Widget {
    let kind = "CompactHabits"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ChooseHabitIntent.self, provider: BuddyProvider()) { entry in CompactHabitsWidgetView(entry: entry).containerBackground(for: .widget) { Color(white: 0.09) }.environment(\.colorScheme, .dark) }
            .configurationDisplayName("Recent Habits").description("Check in across three or eight habits.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
@main struct HabitBuddyWidgetBundle: WidgetBundle {
    var body: some Widget { SingleHabitWidget(); CompactHabitsWidget() }
}
