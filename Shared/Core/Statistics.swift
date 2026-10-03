import Foundation

/// A single calculation shared by all statistics widgets on a screen.
public struct StatisticsSummary: Equatable, Sendable {
    public var completions = 0
    public var eligible = 0
    public var monthly = Array(repeating: 0, count: 12)
    public var hourly = Array(repeating: 0, count: 24)
    public var currentStreak = 0
    public var bestStreak = 0
    /// Days on which at least one of the habits kept a build goal, for the all-habits grid.
    public var keptDays = Set<Day>()
    public init() {}
    /// A cancelled task stops early with partial figures.
    public init(data: BuddyData, habitIDs: [UUID]? = nil, year: Int, today: Day = Day()) {
        let start = Day(rawValue: String(format: "%04d-01-01", year))!
        let end = min(today, Day(rawValue: String(format: "%04d-12-31", year))!)
        let days = Day.range(start, end), chosen = habitIDs.map(Set.init)
        for habit in data.habits where chosen?.contains(habit.id) ?? true {
            if Task.isCancelled { return }
            let stats = Engine.stats(habit, data: data, today: today)
            currentStreak = max(currentStreak, stats.currentStreak)
            bestStreak = max(bestStreak, stats.bestStreak)
            let prefix = Record.keyPrefix(habit.id)
            for day in days where habit.goal(on: day).mode == .build {
                let progress = Engine.progress(habit, day: day, data: data, today: today, prefix: prefix)
                if progress.available && (day < today || progress.success) { eligible += 1 }
                guard progress.success else { continue }
                completions += 1; keptDays.insert(day)
                monthly[day.monthNumber % 12] += 1
                if let hour = data.records[prefix + day.rawValue]?.completionHour, (0..<24).contains(hour) { hourly[hour] += 1 }
            }
        }
    }
}
