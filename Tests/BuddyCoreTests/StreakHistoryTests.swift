import Foundation
import Testing
@testable import BuddyCore

struct StreakHistoryTests {
    let today = Day(rawValue: "2026-10-18")!

    func fixture(days: Int = 12) throws -> BuddyData {
        var data = BuddyData()
        var habit = Habit(name: "Streak regression", created: today.adding(-days))
        habit.goals[0].cadence = .none
        data.habits = [habit]
        for day in Day.range(habit.created, today.adding(-1)) {
            try Engine.complete(habit.id, day: day, data: &data, today: today)
        }
        return data
    }

    func enableDaily(_ data: inout BuddyData, on day: Day? = nil) throws {
        var habit = data.habits[0]
        habit.goals[habit.goals.count - 1].cadence = .daily
        try Engine.saveHabit(habit, data: &data, today: day ?? today)
    }

    @Test func newHabitsUseDailyStreaks() {
        #expect(Habit(name: "New habit").currentGoal.cadence == .daily)
    }

    @Test(arguments: [10, 12]) func enablingDailyIncludesSavedSuccesses(days: Int) throws {
        var data = try fixture(days: days)
        let records = data.records, oldGoals = data.habits[0].goals
        #expect(Engine.stats(data.habits[0], data: data, today: today).currentStreak == 0)
        try enableDaily(&data)
        let habit = data.habits[0]
        #expect(data.records == records)
        #expect(Array(habit.goals.dropLast()) == oldGoals)
        #expect(habit.currentGoal.from == today)
        let stats = Engine.stats(habit, data: data, today: today)
        #expect(stats.currentStreak == days)
        #expect(stats.bestStreak == days)
        #expect(stats.completions == days)
        #expect(Engine.streak(habit, data: data, today: today) == StreakSummary(value: days, unit: .days))
        #expect(Milestones(habit, data: data, today: today).currentStreak == days)
        #expect(StatisticsSummary(data: data, year: 2026, today: today).currentStreak == days)
        try DataValidation.validate(data, today: today)

        try Engine.complete(habit.id, day: today, data: &data, today: today)
        #expect(Engine.stats(habit, data: data, today: today).currentStreak == days + 1)
    }

    @Test func alreadyEnabledHabitsRecoverAfterLoadingWithoutRewritingData() throws {
        var data = try fixture()
        // This is the goal history saved by the older app, with Daily enabled two days ago.
        var daily = data.habits[0].currentGoal
        daily.from = today.adding(-2); daily.cadence = .daily
        data.habits[0].goals.append(daily)
        let bytes = try DataValidation.encode(data)
        let loaded = try DataValidation.decode(bytes, today: today)
        #expect(Engine.stats(loaded.habits[0], data: loaded, today: today).currentStreak == 12)
        #expect(loaded == data)
    }

    @Test func missedDaysStillSeparateCurrentAndBestRuns() throws {
        var data = try fixture()
        let id = data.habits[0].id
        try Engine.setAmount(0, habitID: id, day: today.adding(-4), data: &data, today: today)
        try enableDaily(&data)
        let stats = Engine.stats(data.habits[0], data: data, today: today)
        #expect(stats.currentStreak == 3)
        #expect(stats.bestStreak == 8)
        #expect(stats.completions == 11)
        try Engine.setAmount(0, habitID: id, day: today.adding(-1), data: &data, today: today)
        #expect(Engine.stats(data.habits[0], data: data, today: today).currentStreak == 0)
    }

    @Test func historyUsesEachDaysOriginalNumericTarget() throws {
        var data = try fixture()
        var habit = data.habits[0]
        habit.goals[0].tracking = .count; habit.goals[0].target = 2_000
        var later = habit.goals[0]
        later.from = today.adding(-6); later.target = 5_000
        habit.goals.append(later); data.habits[0] = habit
        for day in Day.range(habit.created, today.adding(-1)) {
            try Engine.complete(habit.id, day: day, data: &data, today: today)
        }
        let records = data.records, oldGoals = habit.goals
        habit.goals[1].cadence = .daily; habit.goals[1].target = 8_000
        try Engine.saveHabit(habit, data: &data, today: today)
        #expect(Engine.stats(data.habits[0], data: data, today: today).currentStreak == 12)
        #expect(Array(data.habits[0].goals.dropLast()) == oldGoals)
        #expect(data.records == records)
        try DataValidation.validate(data, today: today)
    }

    @Test func enablingDailyDoesNotRewriteWhatAnEarlierDateReported() throws {
        var data = try fixture()
        try enableDaily(&data)
        #expect(Engine.stats(data.habits[0], data: data, today: today.adding(-1)).currentStreak == 0)
        #expect(Engine.stats(data.habits[0], data: data, today: today).currentStreak == 12)
    }

    @Test func turningStreaksOffStillShowsZeroAndReenablingIncludesTheGap() throws {
        var data = try fixture()
        data.habits[0].goals[0].cadence = .daily
        var off = data.habits[0].currentGoal
        off.from = today.adding(-5); off.cadence = .none
        data.habits[0].goals.append(off)
        #expect(Engine.stats(data.habits[0], data: data, today: today).currentStreak == 0)
        try enableDaily(&data)
        #expect(Engine.stats(data.habits[0], data: data, today: today).currentStreak == 12)
    }

    @Test func existingNoneChoiceSurvivesDecoding() throws {
        let data = try fixture()
        let loaded = try DataValidation.decode(DataValidation.encode(data), today: today)
        #expect(loaded.habits[0].currentGoal.cadence == .none)
        #expect(Engine.stats(loaded.habits[0], data: loaded, today: today).currentStreak == 0)
    }

    @Test func changingBuildQuitModeStillStartsANewRun() throws {
        var data = try fixture()
        var habit = data.habits[0]
        habit.goals[0].mode = .quit; habit.goals[0].cadence = .daily
        try Engine.saveHabit(habit, data: &data, today: today)
        #expect(Engine.stats(data.habits[0], data: data, today: today).currentStreak == 1)
    }

    @Test func dailyHistoryDoesNotCrossAWeeklyBoundary() throws {
        var data = try fixture()
        data.habits[0].goals[0].cadence = .weekly
        data.habits[0].goals[0].days = 3
        var off = data.habits[0].currentGoal
        off.from = today.adding(-5); off.cadence = .none; off.days = 1
        data.habits[0].goals.append(off)
        try enableDaily(&data)
        #expect(Engine.stats(data.habits[0], data: data, today: today).currentStreak == 5)
    }

    @Test func pauseAndNextDayStillBreakTheRecoveredDailyRun() throws {
        var data = try fixture()
        data.habits[0].pauses = [Pause(from: today.adding(-4), through: today.adding(-3))]
        // Paused days cannot carry records in a valid stored snapshot.
        for offset in [-4, -3] { data.records[Record.key(data.habits[0].id, today.adding(offset))] = nil }
        try enableDaily(&data)
        try DataValidation.validate(data, today: today)
        #expect(Engine.stats(data.habits[0], data: data, today: today).currentStreak == 2)
        #expect(Engine.stats(data.habits[0], data: data, today: today.adding(1)).currentStreak == 0)
    }
}
