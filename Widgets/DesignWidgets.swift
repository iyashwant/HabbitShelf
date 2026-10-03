import AppIntents
import SwiftUI
import WidgetKit

/// Home-screen versions of the goal ring, stats, year, next badge, quick check, week and routine designs.
/// Each is drawn by `DashboardHomeWidget` at the family's size, so it matches the dashboard.

struct RoutineWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BuddyEntry { loadEntry() }
    func snapshot(for configuration: ChooseRoutineWidgetIntent, in context: Context) async -> BuddyEntry { loadEntry(routineID: configuration.routine?.id, theme: configuration.theme) }
    func timeline(for configuration: ChooseRoutineWidgetIntent, in context: Context) async -> Timeline<BuddyEntry> {
        Timeline(entries: [loadEntry(routineID: configuration.routine?.id, theme: configuration.theme)], policy: .after(nextRefresh()))
    }
}

struct GoalRingHomeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "GoalRing", intent: ChooseHabitIntent.self, provider: BuddyProvider()) { DashboardHomeWidget(entry: $0, kind: .ring) }
            .configurationDisplayName("Goal Ring").description("Today's progress toward a habit's goal, with a quick check-in.").supportedFamilies([.systemSmall]).contentMarginsDisabled()
    }
}
struct StatsHomeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HabitStats", intent: ChooseHabitIntent.self, provider: BuddyProvider()) { DashboardHomeWidget(entry: $0, kind: .stats) }
            .configurationDisplayName("Habit Stats").description("How much of the last 30 days you kept, with your streak, best run and total.").supportedFamilies([.systemSmall, .systemMedium]).contentMarginsDisabled()
    }
}
struct YearHomeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HabitYear", intent: ChooseHabitIntent.self, provider: BuddyProvider()) { DashboardHomeWidget(entry: $0, kind: .year) }
            .configurationDisplayName("This Year").description("A habit's year day by day: weeks in medium, twelve months in large.").supportedFamilies([.systemMedium, .systemLarge]).contentMarginsDisabled()
    }
}
struct BadgeHomeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NextBadge", intent: ChooseHabitIntent.self, provider: BuddyProvider()) { DashboardHomeWidget(entry: $0, kind: .badge) }
            .configurationDisplayName("Next Badge").description("How close a habit is to its next milestone badge.").supportedFamilies([.systemSmall]).contentMarginsDisabled()
    }
}
struct QuickCheckHomeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "QuickCheck", intent: ChooseCompactHabitsIntent.self, provider: CompactBuddyProvider()) { DashboardHomeWidget(entry: $0, kind: .checks) }
            .configurationDisplayName("Quick Check").description("Check off several habits with one tap each: 4 in small, 8 in medium, 16 in large.").supportedFamilies([.systemSmall, .systemMedium, .systemLarge]).contentMarginsDisabled()
    }
}
struct WeekHomeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ThisWeek", intent: ChooseCompactHabitsIntent.self, provider: CompactBuddyProvider()) { DashboardHomeWidget(entry: $0, kind: .week) }
            .configurationDisplayName("This Week").description("How much of each day you kept this week, compared with last week.").supportedFamilies([.systemMedium]).contentMarginsDisabled()
    }
}
struct RoutineHomeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "RoutineWidget", intent: ChooseRoutineWidgetIntent.self, provider: RoutineWidgetProvider()) { DashboardHomeWidget(entry: $0, kind: .routine) }
            .configurationDisplayName("Routine").description("A routine's progress with Complete All; the medium size checks off habits one by one.").supportedFamilies([.systemSmall, .systemMedium]).contentMarginsDisabled()
    }
}

struct DesignWidgetBundle: WidgetBundle {
    var body: some Widget {
        GoalRingHomeWidget()
        StatsHomeWidget()
        YearHomeWidget()
        BadgeHomeWidget()
        QuickCheckHomeWidget()
        WeekHomeWidget()
        RoutineHomeWidget()
    }
}
