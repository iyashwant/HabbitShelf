import Foundation

public struct Progress: Equatable, Sendable {
    public var available: Bool
    public var success: Bool
    public var amount: Int64
    public var target: Int64
    public var fraction: Double
    public var slip: Bool
}
public struct HabitStats: Equatable, Sendable {
    public var completions = 0
    public var eligibleDays = 0
    public var currentStreak = 0
    public var bestStreak = 0
    public var rate: Double { eligibleDays == 0 ? 0 : Double(completions) / Double(eligibleDays) }
}
public enum Engine {
    public static func progress(_ habit: Habit, day: Day, data: BuddyData, today: Day = Day()) -> Progress {
        let rule = habit.goal(on: day), amount = data.record(habit.id, day).amount
        let available = habit.available(on: day, today: today)
        let success = available && (rule.mode == .quit ? amount < rule.target : amount >= rule.target)
        return Progress(available: available, success: success, amount: amount, target: rule.target,
                        fraction: success ? 1 : min(1, Double(amount) / Double(max(1, rule.target))),
                        slip: available && rule.mode == .quit && !success)
    }
    /// Cadence changes start a new streak segment. Period targets are capped to tracked days.
    public static func stats(_ habit: Habit, data: BuddyData, today: Day = Day(), weekStart: Int? = nil) -> HabitStats {
        let end = min(today, habit.archived ?? today)
        guard habit.created <= end else { return HabitStats() }
        let days = Day.range(habit.created, end)
        var result = HabitStats()
        for day in days where habit.goal(on: day).mode == .build && habit.available(on: day, today: today) {
            // An incomplete today is excluded from the rate until completed.
            let success = progress(habit, day: day, data: data, today: today).success
            if day < today || success { result.eligibleDays += 1 }
            if success { result.completions += 1 }
        }
        var run = 0, best = 0
        for (index, rule) in habit.goals.enumerated() {
            let next = index + 1 < habit.goals.count ? habit.goals[index + 1].from.adding(-1) : end
            let segmentEnd = min(end, next)
            guard rule.from <= segmentEnd else { continue }
            if index > 0, rule.cadence != habit.goals[index - 1].cadence || rule.mode != habit.goals[index - 1].mode {
                run = 0
            }
            if rule.cadence == .none { run = 0; continue }
            // Daily rules can span target edits; period rules are processed once across adjacent versions.
            if rule.cadence == .daily || rule.mode == .quit {
                for day in Day.range(rule.from, segmentEnd) {
                    if progress(habit, day: day, data: data, today: today).success { run += 1 }
                    else if day < today { run = 0 }
                    best = max(best, run)
                }
            } else {
                // Split at each version; a changed cadence target applies only from its effective day.
                var cursor = rule.from
                while cursor <= segmentEnd {
                    let periodEnd = rule.cadence == .weekly ? cursor.startOfWeek(weekStart ?? data.settings.weekStart).adding(6) : cursor.endOfMonth
                    let closedEnd = min(periodEnd, next)
                    let visibleEnd = min(segmentEnd, closedEnd)
                    let successes = Day.range(cursor, visibleEnd).filter { progress(habit, day: $0, data: data, today: today).success }.count
                    let target = min(rule.days, cursor.distance(to: closedEnd) + 1)
                    if successes >= target { run += successes; best = max(best, run) }
                    else if closedEnd < today || successes + today.distance(to: closedEnd) + (progress(habit, day: today, data: data, today: today).success ? 0 : 1) < target { run = 0 }
                    else { best = max(best, run + successes); run += successes }
                    cursor = closedEnd.adding(1)
                }
            }
        }
        result.currentStreak = run; result.bestStreak = best
        return result
    }
    public static func setAmount(_ value: Int64, habitID: UUID, day: Day, data: inout BuddyData, today: Day = Day(), now: Date = Date()) throws {
        guard let habit = data.habits.first(where: { $0.id == habitID }), habit.archived == nil else { throw BuddyError.unavailable }
        guard habit.available(on: day, today: today) else { throw BuddyError.future }
        let goal = habit.goal(on: day)
        guard goal.mode == habit.currentGoal.mode else { throw BuddyError.locked }
        guard value >= 0, value <= Amount.maximum, goal.tracking == .measure || value % 1_000 == 0,
              goal.tracking != .yesNo || value == 0 || value == 1_000 else { throw BuddyError.invalidAmount }
        var record = data.record(habitID, day)
        if goal.mode == .build && value >= goal.target && record.amount < goal.target {
            record.completedAt = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970))
            record.completionHour = Calendar.current.component(.hour, from: now)
        } else if value < goal.target {
            record.completedAt = nil; record.completionHour = nil
        }
        record.amount = value; record.updated = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970))
        data.records[record.key] = record
    }
    public static func increment(_ amount: Int64 = 1_000, habitID: UUID, day: Day, data: inout BuddyData, today: Day = Day()) throws {
        let old = data.record(habitID, day).amount
        guard amount >= 0, amount <= Amount.maximum - old else { throw BuddyError.invalidAmount }
        try setAmount(old + amount, habitID: habitID, day: day, data: &data, today: today)
    }
    public static func complete(_ id: UUID, day: Day, data: inout BuddyData, today: Day = Day()) throws {
        guard let h = data.habits.first(where: { $0.id == id }) else { throw BuddyError.unavailable }
        let g = h.goal(on: day)
        let value = g.mode == .quit ? Int64(0) : max(data.record(id, day).amount, g.target)
        try setAmount(value, habitID: id, day: day, data: &data, today: today)
    }
    public static func note(_ text: String, append: Bool = false, habitID: UUID, day: Day, data: inout BuddyData, today: Day = Day()) throws {
        guard let habit = data.habits.first(where: { $0.id == habitID }), habit.archived == nil else { throw BuddyError.unavailable }
        guard habit.available(on: day, today: today), text.count <= 20_000 else { throw BuddyError.future }
        var r = data.record(habitID, day)
        r.note = append && !r.note.isEmpty ? r.note + "\n" + text : text
        r.updated = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)); data.records[r.key] = r
    }
    public static func saveHabit(_ habit: Habit, data: inout BuddyData, today: Day = Day()) throws {
        guard !habit.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BuddyError.invalidData("a habit needs a name") }
        if let index = data.habits.firstIndex(where: { $0.id == habit.id }) {
            let old = data.habits[index]
            var updated = habit
            var goal = habit.currentGoal; goal.from = today
            updated.created = old.created
            updated.goals = old.goals.filter { $0.from < today } + [goal]
            if old.currentGoal.mode != goal.mode || old.currentGoal.tracking != goal.tracking {
                var record = data.record(habit.id, today); record.amount = 0; record.completedAt = nil; record.completionHour = nil; data.records[record.key] = record
            }
            data.habits[index] = updated
        } else {
            var updated = habit; updated.order = data.habits.count
            data.habits.append(updated)
        }
    }
    public static func deleteCategory(_ id: UUID, data: inout BuddyData) {
        data.categories.removeAll { $0.id == id }
        for i in data.habits.indices { data.habits[i].categories.removeAll { $0 == id } }
    }
}
