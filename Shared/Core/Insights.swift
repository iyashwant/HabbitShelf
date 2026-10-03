import Foundation

/// Kept days out of tracked days. A day is tracked once it has passed, or today once it is kept or slipped.
public struct DayRate: Equatable, Sendable {
    public var done = 0
    public var eligible = 0
    public init(done: Int = 0, eligible: Int = 0) { self.done = done; self.eligible = eligible }
    public var rate: Double { eligible == 0 ? 0 : Double(done) / Double(eligible) }
    mutating func add(_ p: Progress, today: Bool) {
        guard p.available, !today || p.success || p.slip else { return }
        eligible += 1
        if p.success { done += 1 }
    }
    /// One habit over the last `days` days, through today.
    public init(_ habit: Habit, days: Int, data: BuddyData, today: Day = Day()) {
        self.init()
        let first = max(habit.created, today.adding(-(max(1, days) - 1)))
        guard first <= today else { return }
        for day in Day.range(first, today) { add(Engine.progress(habit, day: day, data: data, today: today), today: day == today) }
    }
}

/// Each day's kept share across some habits for one week, with the week before for comparison.
public struct WeekRates: Equatable, Sendable {
    public var start: Day
    public var days = Array(repeating: DayRate(), count: 7)
    public var total = DayRate()
    public var previous = DayRate()
    public init(habits: [Habit], data: BuddyData, week: Day, today: Day = Day()) {
        start = week.startOfWeek(data.settings.weekStart)
        for habit in habits {
            for offset in 0..<7 {
                let day = start.adding(offset), before = start.adding(offset - 7)
                if day <= today { days[offset].add(Engine.progress(habit, day: day, data: data, today: today), today: day == today) }
                if before <= today { previous.add(Engine.progress(habit, day: before, data: data, today: today), today: before == today) }
            }
        }
        for rate in days { total.done += rate.done; total.eligible += rate.eligible }
    }
}

/// Patterns across habits: weekdays, time of day, the monthly trend and habits that lapse on the same days.
/// Build days count when completed and quit days when clean, so both kinds of habit share one scale.
public struct InsightsSummary: Equatable, Sendable {
    public struct MonthRate: Equatable, Sendable { public var month: Day; public var rate: DayRate }
    /// Two habits missed (or slipped) on the same days, out of the days either lapsed while both were tracked.
    public struct LapsePair: Equatable, Sendable {
        public var first: UUID
        public var second: UUID
        public var together: Int
        public var either: Int
        public var share: Double { either == 0 ? 0 : Double(together) / Double(either) }
    }
    /// Index 0 is Sunday, matching `Day.weekday - 1`.
    public var weekdays = Array(repeating: DayRate(), count: 7)
    public var hours = Array(repeating: 0, count: 24)
    public var months: [MonthRate] = []
    public var total = DayRate()
    public var pairs: [LapsePair] = []
    public init() {}
    /// `from` bounds every figure except `months`, which always covers the last twelve months.
    /// Lapse pairs are found among the first `pairLimit` habits and the `maxPairs` strongest are kept.
    public init(data: BuddyData, habitIDs: [UUID]? = nil, from: Day, today: Day = Day(), pairLimit: Int = 30, maxPairs: Int = 3) {
        let habits = data.habits.filter { habitIDs == nil || habitIDs!.contains($0.id) }.sorted { $0.order < $1.order }
        let firstMonth = today.startOfMonth.addingMonths(-11)
        months = (0..<12).map { MonthRate(month: firstMonth.addingMonths($0), rate: DayRate()) }
        var tracked: [UUID: Set<Day>] = [:], lapses: [UUID: Set<Day>] = [:]
        for habit in habits {
            let end = min(today, habit.archived ?? today)
            let start = max(habit.created, min(from, firstMonth))
            guard start <= end else { continue }
            var seen = Set<Day>(), lapsed = Set<Day>()
            for day in Day.range(start, end) {
                let p = Engine.progress(habit, day: day, data: data, today: today), isToday = day == today
                if day >= firstMonth, let index = months.firstIndex(where: { $0.month.month == day.month }) { months[index].rate.add(p, today: isToday) }
                guard day >= from, p.available else { continue }
                weekdays[day.weekday - 1].add(p, today: isToday)
                total.add(p, today: isToday)
                if p.success, habit.goal(on: day).mode == .build, let hour = data.records[Record.key(habit.id, day)]?.completionHour, (0..<24).contains(hour) { hours[hour] += 1 }
                if day < today { seen.insert(day); if !p.success { lapsed.insert(day) } }
            }
            tracked[habit.id] = seen; lapses[habit.id] = lapsed
        }
        let candidates = habits.prefix(pairLimit)
        for (i, a) in candidates.enumerated() {
            for b in candidates.dropFirst(i + 1) {
                guard let seenA = tracked[a.id], let seenB = tracked[b.id] else { continue }
                let both = seenA.intersection(seenB)
                let lapseA = lapses[a.id, default: []].intersection(both), lapseB = lapses[b.id, default: []].intersection(both)
                let pair = LapsePair(first: a.id, second: b.id, together: lapseA.intersection(lapseB).count, either: lapseA.union(lapseB).count)
                if pair.together >= 3 && pair.share >= 0.4 { pairs.append(pair) }
            }
        }
        pairs.sort { $0.share == $1.share ? $0.together > $1.together : $0.share > $1.share }
        pairs = Array(pairs.prefix(maxPairs))
    }
    /// Weekdays (1 = Sunday) with the highest and lowest kept rate; nil until a weekday has been tracked twice.
    public var bestWeekday: Int? { rankedWeekdays.last }
    public var worstWeekday: Int? { let ranked = rankedWeekdays; return ranked.count > 1 ? ranked.first : nil }
    private var rankedWeekdays: [Int] {
        (1...7).filter { weekdays[$0 - 1].eligible >= 2 }.sorted { weekdays[$0 - 1].rate == weekdays[$1 - 1].rate ? $0 > $1 : weekdays[$0 - 1].rate < weekdays[$1 - 1].rate }
    }
}

/// One week of every habit, with the week before for comparison.
public struct WeekRecap: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public var habitID: UUID
        public var rate = DayRate()
        /// Kept (true), lapsed (false) or not tracked (nil) for each day of the week.
        public var days: [Bool?] = Array(repeating: nil, count: 7)
    }
    public var start: Day
    public var end: Day { start.adding(6) }
    public var rows: [Row] = []
    public var total = DayRate()
    public var previous = DayRate()
    /// Days on which every tracked habit was kept.
    public var perfectDays = 0
    public var bestDay: Day?
    public var notes = 0
    public init(data: BuddyData, week: Day, today: Day = Day()) {
        start = week.startOfWeek(data.settings.weekStart)
        var kept = Array(repeating: 0, count: 7), trackedHabits = Array(repeating: 0, count: 7)
        for habit in data.habits.sorted(by: { $0.order < $1.order }) {
            var row = Row(habitID: habit.id)
            for offset in 0..<7 {
                let day = start.adding(offset)
                guard day <= today else { break }
                let p = Engine.progress(habit, day: day, data: data, today: today)
                row.rate.add(p, today: day == today)
                if p.available && (day < today || p.success || p.slip) { row.days[offset] = p.success; trackedHabits[offset] += 1; if p.success { kept[offset] += 1 } }
                if p.available && !data.record(habit.id, day).note.isEmpty { notes += 1 }
            }
            for offset in 0..<7 where start.adding(offset - 7) <= today {
                let day = start.adding(offset - 7)
                previous.add(Engine.progress(habit, day: day, data: data, today: today), today: day == today)
            }
            guard row.days.contains(where: { $0 != nil }) else { continue }
            total.done += row.rate.done; total.eligible += row.rate.eligible
            rows.append(row)
        }
        perfectDays = (0..<7).filter { trackedHabits[$0] > 0 && kept[$0] == trackedHabits[$0] }.count
        if let best = (0..<7).filter({ kept[$0] > 0 }).max(by: { kept[$0] == kept[$1] ? $0 > $1 : kept[$0] < kept[$1] }) { bestDay = start.adding(best) }
    }
}

/// Streak and total badges for one habit. Streaks count days, like the detail screen's flame.
public struct Milestones: Equatable, Sendable {
    public static let streakSteps = [3, 7, 14, 30, 50, 100, 180, 365]
    public static let totalSteps = [1, 10, 25, 50, 100, 250, 500, 1_000]
    public var currentStreak = 0
    public var bestStreak = 0
    public var total = 0
    /// The day each reached total step was reached.
    public var totalReached: [Int: Day] = [:]
    public init(_ habit: Habit, data: BuddyData, today: Day = Day()) {
        let stats = Engine.stats(habit, data: data, today: today)
        currentStreak = stats.currentStreak; bestStreak = stats.bestStreak
        let end = min(today, habit.archived ?? today)
        guard habit.created <= end else { return }
        for day in Day.range(habit.created, end) where Engine.progress(habit, day: day, data: data, today: today).success {
            total += 1
            if Self.totalSteps.contains(total) { totalReached[total] = day }
        }
    }
    public var nextStreak: Int? { Self.streakSteps.first { $0 > bestStreak } }
    public var nextTotal: Int? { Self.totalSteps.first { $0 > total } }
    public var earned: Int { Self.streakSteps.filter { $0 <= bestStreak }.count + Self.totalSteps.filter { $0 <= total }.count }
}

/// The time unit a habit's timer logs in. Only build goals in seconds, minutes or hours, and yes/no goals, take timers.
public enum TimerUnit: Equatable, Sendable {
    case seconds, minutes, hours, completion
    public init?(_ goal: Goal) {
        guard goal.mode == .build else { return nil }
        if goal.tracking == .yesNo { self = .completion; return }
        switch goal.unit.trimmingCharacters(in: .whitespaces).lowercased() {
        case "s", "sec", "secs", "second", "seconds": self = .seconds
        case "m", "min", "mins", "minute", "minutes": self = .minutes
        case "h", "hr", "hrs", "hour", "hours": self = .hours
        default: return nil
        }
    }
    private var seconds: Double { switch self { case .seconds: 1; case .minutes: 60; case .hours: 3_600; case .completion: 0 } }
    /// Elapsed time in thousandths of the unit; counts keep whole units only.
    public func amount(seconds elapsed: Double, whole: Bool) -> Int64 {
        guard self != .completion else { return 0 }
        let units = max(0, elapsed) / seconds
        return min(Amount.maximum, whole ? Int64(units.rounded(.down)) * 1_000 : Int64((units * 1_000).rounded()))
    }
    /// The goal's target as a countdown length in seconds.
    public func duration(target: Int64) -> Double? { self == .completion ? nil : Double(target) / 1_000 * seconds }
}
