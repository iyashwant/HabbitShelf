import SwiftUI

/// Streaks, stats and milestones per habit. The app's store owns a caching instance that keeps each habit's
/// results until that habit or its days change; widgets and previews use the default, which computes on request.
/// Use the caching instance only with the store's current snapshot, from the main thread.
final class HabitSummaries: @unchecked Sendable {
    private let caching: Bool
    private var day: Day?
    private var entries: [UUID: Entry] = [:]
    private struct Entry {
        let habit: Habit
        let weekStart: Int
        var history: HabitHistory?
        var streak: StreakSummary?
    }
    init(caching: Bool) { self.caching = caching }
    /// The environment's default, created once.
    static let direct = HabitSummaries(caching: false)
    /// Called when a snapshot may have changed any habit.
    func reset() { entries.removeAll(keepingCapacity: true) }
    /// Called when a snapshot changed only these habits or their days.
    func invalidate(_ habits: Set<UUID>) { for id in habits { entries[id] = nil } }
    func history(_ habit: Habit, data: BuddyData, today: Day = Day()) -> HabitHistory {
        guard caching else { return Engine.history(habit, data: data, today: today) }
        if let history = entry(habit, data, today).history { return history }
        let history = Engine.history(habit, data: data, today: today)
        entries[habit.id]?.history = history
        return history
    }
    func stats(_ habit: Habit, data: BuddyData, today: Day = Day()) -> HabitStats { history(habit, data: data, today: today).stats }
    func milestones(_ habit: Habit, data: BuddyData, today: Day = Day()) -> Milestones { Milestones(history(habit, data: data, today: today)) }
    func streak(_ habit: Habit, data: BuddyData, today: Day = Day()) -> StreakSummary {
        guard caching else { return Engine.streak(habit, data: data, today: today) }
        if let streak = entry(habit, data, today).streak { return streak }
        let streak = Engine.streak(habit, data: data, today: today, history: history(habit, data: data, today: today))
        entries[habit.id]?.streak = streak
        return streak
    }
    /// The habit's entry, started again when the day, the habit or the week start differs from when it was cached.
    private func entry(_ habit: Habit, _ data: BuddyData, _ today: Day) -> Entry {
        if day != today { entries.removeAll(keepingCapacity: true); day = today }
        if let entry = entries[habit.id], entry.weekStart == data.settings.weekStart, entry.habit == habit { return entry }
        let entry = Entry(habit: habit, weekStart: data.settings.weekStart)
        entries[habit.id] = entry
        return entry
    }
}

/// How many times the app's store has changed a habit or its days (`habit`), or possibly every habit (`all`).
/// A view given one redraws only when it differs, not each time another habit is logged.
struct HabitVersion: Equatable {
    var all = 0
    var habit = 0
}

extension EnvironmentValues {
    /// The store's cache in the app; computes directly in widgets.
    @Entry var summaries = HabitSummaries.direct
}
