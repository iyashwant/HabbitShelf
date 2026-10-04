import SwiftUI

/// Streaks, stats and milestones per habit. The app's store owns a caching instance; widgets and previews use the
/// default, which computes on request. Use the caching instance only with the store's current snapshot, from the
/// main thread.
///
/// The store works results out off the main thread (`compute`) and hands them over: at launch (`fill`, or with the
/// data when the first screen shows streaks), and after a change to several habits, a new day or any change that
/// may touch every habit (`reset`, then `install`). Until then the previous results stay on screen. A change to one habit instead drops its result, and the habit is
/// worked out again when next drawn: about a millisecond for ten years of daily days, less than drawing its card a
/// second time when a background result arrives.
final class HabitSummaries: @unchecked Sendable {
    private let caching: Bool
    private var day: Day?
    private var entries: [UUID: Entry] = [:]
    /// Habits whose entries come from an older snapshot or day, shown until fresh results are installed.
    private var stale = Set<UUID>()
    /// Asked to bring stale habits up to date; the store refreshes them in the background.
    var onStale: (() -> Void)?
    private struct Entry {
        let habit: Habit
        let weekStart: Int
        var history: HabitHistory?
        var streak: StreakSummary?
    }
    /// One habit's results, worked out off the main thread.
    struct Result: Sendable {
        let habit: Habit
        let weekStart: Int
        let history: HabitHistory
        let streak: StreakSummary
    }
    init(caching: Bool) { self.caching = caching }
    /// The environment's default, created once.
    static let direct = HabitSummaries(caching: false)
    /// Called when a snapshot may have changed any habit.
    func reset() { stale.formUnion(entries.keys) }
    /// Called when a snapshot changed only these habits or their days.
    func invalidate(_ habits: Set<UUID>) {
        if habits.count == 1 { for id in habits { entries[id] = nil; stale.remove(id) } }
        else { stale.formUnion(habits.filter { entries[$0] != nil }) }
    }
    /// The habits waiting for fresh results.
    var staleHabits: Set<UUID> { stale }
    /// Works out the results for `habits` from a snapshot. Safe off the main thread.
    static func compute(_ habits: Set<UUID>, data: BuddyData, today: Day) -> [UUID: Result] {
        var results: [UUID: Result] = [:]
        for habit in data.habits where habits.contains(habit.id) {
            let history = Engine.history(habit, data: data, today: today)
            results[habit.id] = Result(habit: habit, weekStart: data.settings.weekStart, history: history, streak: Engine.streak(habit, data: data, today: today, history: history))
        }
        return results
    }
    /// Whether the overview shows streaks as it opens: the streak and list layouts, and cards with streak chips.
    static func firstScreenReads(_ data: BuddyData) -> Bool {
        switch data.settings.layout {
        case .streaks, .list: true
        case .cards: data.active.contains { $0.cardAppearance(data.settings).streak && $0.currentGoal.cadence != .none }
        default: false
        }
    }
    /// Keeps results for habits that have none yet, which no view has shown, so nothing needs to redraw.
    func fill(_ results: [UUID: Result], today: Day) {
        guard caching, day == nil || day == today else { return }
        day = today
        for (id, result) in results where entries[id] == nil && !stale.contains(id) {
            entries[id] = Entry(habit: result.habit, weekStart: result.weekStart, history: result.history, streak: result.streak)
        }
    }
    /// Takes results worked out from the store's current snapshot. Stale habits that no longer exist are dropped.
    func install(_ results: [UUID: Result], for habits: Set<UUID>, today: Day) {
        if day != today { stale.formUnion(entries.keys); day = today }
        for id in habits {
            if let result = results[id] { entries[id] = Entry(habit: result.habit, weekStart: result.weekStart, history: result.history, streak: result.streak) }
            else { entries[id] = nil }
            stale.remove(id)
        }
    }
    func history(_ habit: Habit, data: BuddyData, today: Day = Day()) -> HabitHistory {
        guard caching else { return Engine.history(habit, data: data, today: today) }
        switch entry(habit, data, today) {
        case .current(let entry), .previous(let entry): if let history = entry.history { return history }
        case .other: return Engine.history(habit, data: data, today: today)
        case .none: break
        }
        let history = Engine.history(habit, data: data, today: today)
        entries[habit.id] = Entry(habit: habit, weekStart: data.settings.weekStart, history: history)
        return history
    }
    func stats(_ habit: Habit, data: BuddyData, today: Day = Day()) -> HabitStats { history(habit, data: data, today: today).stats }
    func milestones(_ habit: Habit, data: BuddyData, today: Day = Day()) -> Milestones { Milestones(history(habit, data: data, today: today)) }
    func streak(_ habit: Habit, data: BuddyData, today: Day = Day()) -> StreakSummary {
        guard caching else { return Engine.streak(habit, data: data, today: today) }
        switch entry(habit, data, today) {
        case .current(let entry):
            if let streak = entry.streak { return streak }
            let streak = Engine.streak(habit, data: data, today: today, history: history(habit, data: data, today: today))
            entries[habit.id]?.streak = streak
            return streak
        case .previous(let entry): if let streak = entry.streak { return streak }
        case .other: return Engine.streak(habit, data: data, today: today)
        case .none: break
        }
        return Engine.streak(habit, data: data, today: today, history: history(habit, data: data, today: today))
    }
    private enum Lookup { case current(Entry), previous(Entry), other, none }
    /// The habit's entry: current, from an older snapshot (`previous`, shown while the store refreshes it), or kept
    /// for a different version of the habit or week start than the caller's (`other`, such as an editor's preview).
    private func entry(_ habit: Habit, _ data: BuddyData, _ today: Day) -> Lookup {
        if day != today {
            if day != nil { stale.formUnion(entries.keys); onStale?() }
            day = today
        }
        guard let entry = entries[habit.id] else { return .none }
        if stale.contains(habit.id) { onStale?(); return .previous(entry) }
        return entry.habit == habit && entry.weekStart == data.settings.weekStart ? .current(entry) : .other
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
