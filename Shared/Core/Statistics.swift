import Foundation

/// A single calculation shared by all statistics widgets on a screen.
public struct StatisticsSummary: Equatable, Sendable {
    public var completions = 0
    public var eligible = 0
    public var monthly = Array(repeating: 0, count: 12)
    public var hourly = Array(repeating: 0, count: 24)
    public var currentStreak = 0
    public var bestStreak = 0
    public init() {}
    public init(data: BuddyData, habitIDs: [UUID]? = nil, year: Int, today: Day = Day()) {
        let start = Day(rawValue: String(format: "%04d-01-01", year))!
        let end = min(today, Day(rawValue: String(format: "%04d-12-31", year))!)
        let days = Day.range(start, end)
        for habit in data.habits where habitIDs == nil || habitIDs!.contains(habit.id) {
            let stats = Engine.stats(habit, data: data, today: today)
            currentStreak = max(currentStreak, stats.currentStreak)
            bestStreak = max(bestStreak, stats.bestStreak)
            for day in days where habit.goal(on: day).mode == .build {
                let progress = Engine.progress(habit, day: day, data: data, today: today)
                if progress.available && (day < today || progress.success) { eligible += 1 }
                guard progress.success else { continue }
                completions += 1
                let month = Int(day.rawValue.dropFirst(5).prefix(2))!
                monthly[month - 1] += 1
                if let hour = data.record(habit.id, day).completionHour, (0..<24).contains(hour) { hourly[hour] += 1 }
            }
        }
    }
}
