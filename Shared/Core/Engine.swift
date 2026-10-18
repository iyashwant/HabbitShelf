import Foundation

public struct Progress: Equatable, Sendable {
    public var available: Bool
    public var success: Bool
    public var amount: Int64
    public var target: Int64
    public var fraction: Double
    public var slip: Bool
    /// A missed day protected by a streak freeze.
    public var frozen = false
}
public struct HabitStats: Equatable, Sendable {
    public var completions = 0
    public var eligibleDays = 0
    public var currentStreak = 0
    public var bestStreak = 0
    public var rate: Double { eligibleDays == 0 ? 0 : Double(completions) / Double(eligibleDays) }
}
public enum StreakUnit: String, Sendable { case days, weeks, months }
public struct StreakSummary: Equatable, Sendable {
    public var value: Int
    public var unit: StreakUnit
}
/// Totals within one calendar year: successful days, tracked days so far, and the longest run of successful days.
public struct YearStats: Equatable, Sendable {
    public var completions = 0
    public var eligible = 0
    public var longestRun = 0
    public var rate: Double { eligible == 0 ? 0 : Double(completions) / Double(eligible) }
}
/// A habit's whole history in one pass: the stats, plus its successful days for milestones.
public struct HabitHistory: Equatable, Sendable {
    public var stats = HabitStats()
    /// Successful days, build or quit.
    public var total = 0
    /// The day each milestone total was reached.
    public var totalReached: [Int: Day] = [:]
}
public enum Engine {
    public static func progress(_ habit: Habit, day: Day, data: BuddyData, today: Day = Day()) -> Progress {
        progress(habit, day: day, data: data, today: today, prefix: Record.keyPrefix(habit.id))
    }
    /// Loops over many days pass the habit's key prefix, built once with `Record.keyPrefix`.
    static func progress(_ habit: Habit, day: Day, data: BuddyData, today: Day, prefix: String) -> Progress {
        progress(habit, rule: habit.goal(on: day), day: day, record: data.records[prefix + day.rawValue], today: today)
    }
    private static func progress(_ habit: Habit, rule: Goal, day: Day, record: Record?, today: Day) -> Progress {
        let amount = record?.amount ?? 0, available = habit.available(on: day, today: today)
        let success = available && (rule.mode == .quit ? amount < rule.target : amount >= rule.target)
        return Progress(available: available, success: success, amount: amount, target: rule.target,
                        fraction: success ? 1 : min(1, Double(amount) / Double(max(1, rule.target))),
                        slip: available && rule.mode == .quit && !success,
                        frozen: available && !success && record?.frozen == true)
    }
    static func frozen(_ habit: Habit, _ day: Day, _ data: BuddyData) -> Bool { data.records[Record.key(habit.id, day)]?.frozen == true }
    /// Enabling Daily includes preceding no-goal history. Other cadence changes start a new segment.
    /// Period targets are capped to tracked days.
    public static func stats(_ habit: Habit, data: BuddyData, today: Day = Day(), weekStart: Int? = nil) -> HabitStats {
        history(habit, data: data, today: today, weekStart: weekStart).stats
    }
    /// Reads each day once; the streak rules then reuse the recorded successes.
    public static func history(_ habit: Habit, data: BuddyData, today: Day = Day(), weekStart: Int? = nil) -> HabitHistory {
        let end = min(today, habit.archived ?? today)
        guard habit.created <= end, !habit.goals.isEmpty else { return HabitHistory() }
        var result = HabitHistory()
        let start = habit.created, count = start.distance(to: end) + 1, prefix = Record.keyPrefix(habit.id)
        var succeeded = [Bool](repeating: false, count: count), frozenDays = [Bool](repeating: false, count: count)
        var goal = 0
        for offset in 0..<count {
            let day = start.adding(offset)
            // Goals are ordered by date and the first starts with the habit, so this matches `goal(on:)`.
            while goal + 1 < habit.goals.count && habit.goals[goal + 1].from <= day { goal += 1 }
            let rule = habit.goals[goal], record = data.records[prefix + day.rawValue]
            let p = progress(habit, rule: rule, day: day, record: record, today: today)
            succeeded[offset] = p.success; frozenDays[offset] = record?.frozen == true
            if p.success {
                result.total += 1
                if Milestones.totalSteps.contains(result.total) { result.totalReached[result.total] = day }
            }
            // An incomplete today is excluded from the rate until completed.
            if rule.mode == .build && p.available {
                if day < today || p.success { result.stats.eligibleDays += 1 }
                if p.success { result.stats.completions += 1 }
            }
        }
        func success(_ day: Day) -> Bool { day >= start && day <= end && succeeded[start.distance(to: day)] }
        func countSuccesses(_ from: Day, _ through: Day) -> Int {
            let first = max(from, start), last = min(through, end)
            return first > last ? 0 : (start.distance(to: first)...start.distance(to: last)).reduce(0) { $0 + (succeeded[$1] ? 1 : 0) }
        }
        // None disables the counter, not the saved check-ins. Once Daily is enabled, include preceding
        // no-goal versions in that daily run without changing their dates, modes or completion targets.
        // Resolve backwards so multiple no-goal edits are included, but never cross another cadence,
        // a mode change, or a goal that hasn't taken effect at the end of this history.
        var cadences = habit.goals.map(\.cadence)
        for index in habit.goals.indices.reversed() where index + 1 < habit.goals.count {
            let rule = habit.goals[index], next = habit.goals[index + 1]
            if rule.cadence == .none, next.from <= end, rule.mode == next.mode, cadences[index + 1] == .daily {
                cadences[index] = .daily
            }
        }
        var run = 0, best = 0
        for (index, rule) in habit.goals.enumerated() {
            let cadence = cadences[index]
            let next = index + 1 < habit.goals.count ? habit.goals[index + 1].from.adding(-1) : end
            let segmentEnd = min(end, next)
            guard max(rule.from, start) <= segmentEnd else { continue }
            if index > 0, cadence != cadences[index - 1] || rule.mode != habit.goals[index - 1].mode {
                run = 0
            }
            if cadence == .none { run = 0; continue }
            // Daily rules can span target edits; period rules are processed once across adjacent versions.
            if cadence == .daily || rule.mode == .quit {
                for offset in start.distance(to: max(rule.from, start))...start.distance(to: segmentEnd) {
                    if succeeded[offset] { run += 1 }
                    else if start.adding(offset) < today && !frozenDays[offset] { run = 0 }
                    best = max(best, run)
                }
            } else {
                // Split at each version; a changed cadence target applies only from its effective day.
                var cursor = rule.from
                while cursor <= segmentEnd {
                    let periodEnd = rule.cadence == .weekly ? cursor.startOfWeek(weekStart ?? data.settings.weekStart).adding(6) : cursor.endOfMonth
                    let closedEnd = min(periodEnd, next)
                    let visibleEnd = min(segmentEnd, closedEnd)
                    let successes = countSuccesses(cursor, visibleEnd)
                    let target = min(rule.days, cursor.distance(to: closedEnd) + 1)
                    if successes >= target { run += successes; best = max(best, run) }
                    else if closedEnd < today || successes + today.distance(to: closedEnd) + (success(today) ? 0 : 1) < target { run = 0 }
                    else { best = max(best, run + successes); run += successes }
                    cursor = closedEnd.adding(1)
                }
            }
        }
        result.stats.currentStreak = run; result.stats.bestStreak = best
        return result
    }
    /// Weekly and monthly goals count consecutive successful periods; other habits count days like `stats`.
    /// The current period adds one once its target is met and keeps the streak while still reachable.
    /// A change of cadence or mode starts a new streak, and a first partial period needs only its tracked days.
    /// `history`, when already read for this snapshot, supplies the day streak.
    public static func streak(_ habit: Habit, data: BuddyData, today: Day = Day(), history: HabitHistory? = nil) -> StreakSummary {
        let end = min(today, habit.archived ?? today)
        let rule = habit.goal(on: end)
        guard habit.created <= end, rule.mode == .build, rule.cadence == .weekly || rule.cadence == .monthly else {
            return StreakSummary(value: (history?.stats ?? stats(habit, data: data, today: today)).currentStreak, unit: .days)
        }
        let weekly = rule.cadence == .weekly, weekStart = data.settings.weekStart
        var segmentStart = habit.created
        for (i, goal) in habit.goals.enumerated() where i > 0 && goal.from <= end {
            if goal.cadence != habit.goals[i - 1].cadence || goal.mode != habit.goals[i - 1].mode { segmentStart = goal.from }
        }
        func periodStart(_ day: Day) -> Day { weekly ? day.startOfWeek(weekStart) : day.startOfMonth }
        func success(_ day: Day) -> Bool { progress(habit, day: day, data: data, today: today).success }
        var count = 0, cursor = periodStart(end)
        while true {
            let first = max(cursor, segmentStart), last = weekly ? cursor.adding(6) : cursor.endOfMonth
            let successes = Day.range(first, min(last, end)).filter(success).count
            let target = min(habit.goal(on: first).days, first.distance(to: last) + 1)
            if successes >= target { count += 1 }
            else if last < today || end < today || successes + today.distance(to: last) + (success(today) ? 0 : 1) < target { break }
            if first <= segmentStart { break }
            cursor = periodStart(cursor.adding(-1))
        }
        return StreakSummary(value: count, unit: weekly ? .weeks : .months)
    }
    public static func yearStats(_ habit: Habit, year: Int, data: BuddyData, today: Day = Day()) -> YearStats {
        guard let first = Day(rawValue: String(format: "%04d-01-01", year)), let last = Day(rawValue: String(format: "%04d-12-31", year)), first <= today else { return YearStats() }
        var result = YearStats(), run = 0
        let prefix = Record.keyPrefix(habit.id)
        for day in Day.range(first, min(last, today)) {
            let p = progress(habit, day: day, data: data, today: today, prefix: prefix)
            if p.available && (day < today || p.success) { result.eligible += 1 }
            if p.success { result.completions += 1; run += 1; result.longestRun = max(result.longestRun, run) }
            else if day < today && !p.frozen { run = 0 }
        }
        return result
    }
    public static func setAmount(_ value: Int64, habitID: UUID, day: Day, data: inout BuddyData, today: Day = Day(), now: Date = Date()) throws {
        guard let index = data.habits.firstIndex(where: { $0.id == habitID }), data.habits[index].archived == nil else { throw BuddyError.unavailable }
        let habit = data.habits[index]
        guard habit.loggable(on: day, today: today) else { throw BuddyError.future }
        let goal = habit.goal(on: day)
        guard goal.mode == habit.currentGoal.mode else { throw BuddyError.locked }
        guard value >= 0, value <= Amount.maximum, goal.tracking == .measure || value % 1_000 == 0,
              goal.tracking != .yesNo || value == 0 || value == 1_000 else { throw BuddyError.invalidAmount }
        if day < habit.created {
            // An empty build day records nothing; a quit day marks where clean days begin.
            guard value > 0 || goal.mode == .quit else { return }
            moveStart(index, to: day, data: &data)
        }
        var record = data.record(habitID, day)
        if goal.mode == .build && value >= goal.target && record.amount < goal.target {
            record.completedAt = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970))
            record.completionHour = Calendar.current.component(.hour, from: now)
        } else if value < goal.target {
            record.completedAt = nil; record.completionHour = nil
        }
        // A day that now succeeds no longer needs its freeze.
        if goal.mode == .build && value >= goal.target { record.frozen = nil }
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
        guard let index = data.habits.firstIndex(where: { $0.id == habitID }), data.habits[index].archived == nil else { throw BuddyError.unavailable }
        guard data.habits[index].loggable(on: day, today: today), text.count <= 20_000 else { throw BuddyError.future }
        if day < data.habits[index].created {
            guard !text.isEmpty else { return }
            moveStart(index, to: day, data: &data)
        }
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
    /// Backfilling before the start extends the habit's history; the first goal version covers the new days.
    private static func moveStart(_ index: Int, to day: Day, data: inout BuddyData) {
        data.habits[index].created = day
        data.habits[index].goals[0].from = day
    }
    /// Freezes or unfreezes a missed past day of a daily build goal. Freezing uses the month's allowance.
    public static func setFreeze(_ on: Bool, habitID: UUID, day: Day, data: inout BuddyData, today: Day = Day()) throws {
        guard let habit = data.activeHabit(habitID) else { throw BuddyError.unavailable }
        if on {
            guard canFreeze(habit, day: day, data: data, today: today) else { throw BuddyError.notFreezable }
            guard freezesUsed(habit, month: day, data: data) < data.settings.freezesPerMonth else { throw BuddyError.noFreezesLeft }
        }
        var record = data.record(habitID, day)
        guard (record.frozen == true) != on else { return }
        record.frozen = on ? true : nil
        record.updated = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        data.records[record.key] = record
    }
    public static func canFreeze(_ habit: Habit, day: Day, data: BuddyData, today: Day = Day()) -> Bool {
        let goal = habit.goal(on: day)
        return day < today && goal.mode == .build && goal.cadence == .daily && habit.available(on: day, today: today) && !progress(habit, day: day, data: data, today: today).success
    }
    public static func freezesUsed(_ habit: Habit, month: Day, data: BuddyData) -> Int {
        let prefix = Record.keyPrefix(habit.id)
        return Day.range(month.startOfMonth, month.endOfMonth).filter { data.records[prefix + $0.rawValue]?.frozen == true }.count
    }
    /// Completes every build habit in a routine that is still open on `day`. Quit habits are left alone.
    @discardableResult public static func completeRoutine(_ id: UUID, day: Day, data: inout BuddyData, today: Day = Day()) throws -> Int {
        guard let routine = data.routines.first(where: { $0.id == id }) else { throw BuddyError.unavailable }
        var completed = 0
        for habitID in routine.habitIDs {
            guard let habit = data.activeHabit(habitID), habit.available(on: day, today: today),
                  habit.goal(on: day).mode == .build, habit.currentGoal.mode == .build,
                  !progress(habit, day: day, data: data, today: today).success else { continue }
            try complete(habitID, day: day, data: &data, today: today); completed += 1
        }
        return completed
    }
    /// Successful habits of a routine on `day`, out of the active habits it contains.
    public static func routineProgress(_ routine: Routine, data: BuddyData, day: Day = Day(), today: Day = Day()) -> (done: Int, total: Int) {
        let habits = routine.habitIDs.compactMap { data.activeHabit($0) }
        return (habits.filter { progress($0, day: day, data: data, today: today).success }.count, habits.count)
    }
    /// Logs a finished timer: elapsed time in the goal's time unit, or a completion for yes/no goals.
    /// Returns the amount added (thousandths), or nil when the habit doesn't take timers.
    @discardableResult public static func logTimer(seconds: Double, habitID: UUID, day: Day, data: inout BuddyData, today: Day = Day()) throws -> Int64? {
        guard let habit = data.activeHabit(habitID) else { throw BuddyError.unavailable }
        let goal = habit.goal(on: day)
        guard let unit = TimerUnit(goal) else { return nil }
        if unit == .completion { try complete(habitID, day: day, data: &data, today: today); return goal.target }
        let amount = unit.amount(seconds: seconds, whole: goal.tracking == .count)
        guard amount > 0 else { return 0 }
        try increment(amount, habitID: habitID, day: day, data: &data, today: today)
        return amount
    }
    /// Permanently removes a habit, its records and its routine memberships.
    public static func deleteHabit(_ id: UUID, data: inout BuddyData) {
        data.habits.removeAll { $0.id == id }
        data.records = data.records.filter { $0.value.habitID != id }
        for i in data.routines.indices { data.routines[i].habitIDs.removeAll { $0 == id } }
    }
    public static func deleteCategory(_ id: UUID, data: inout BuddyData) {
        data.categories.removeAll { $0.id == id }
        for i in data.habits.indices { data.habits[i].categories.removeAll { $0 == id } }
    }
}
