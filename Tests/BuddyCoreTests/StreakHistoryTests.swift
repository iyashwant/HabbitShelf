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

    @Test func completionCountsAllSuccessesFromFirstEntryIncludingUnfinishedToday() throws {
        var data = BuddyData()
        let habit = Habit(name: "Read", created: today.adding(-30))
        data.habits = [habit]
        for offset in [-9, -8, -3, -2, -1] {
            try Engine.complete(habit.id, day: today.adding(offset), data: &data, today: today)
        }
        let history = Engine.history(habit, data: data, today: today)
        #expect(history.stats.currentStreak == 3)
        #expect(history.completion.firstDay == today.adding(-9))
        #expect(history.completion.completedDays == 5)
        #expect(history.completion.totalDays == 10)
        // The existing completion rate still uses creation and excludes unfinished today.
        #expect(history.stats.eligibleDays == 30)
        try Engine.complete(habit.id, day: today, data: &data, today: today)
        #expect(Engine.history(habit, data: data, today: today).completion.completedDays == 6)
        try Engine.setAmount(0, habitID: habit.id, day: today.adding(-9), data: &data, today: today)
        let cleared = Engine.history(habit, data: data, today: today).completion
        #expect(cleared.firstDay == today.adding(-9))
        #expect(cleared.completedDays == 5)
        #expect(cleared.totalDays == 10)
    }

    @Test func completionWithoutEntriesStartsAtZeroAndFirstEntryTodayCountsOneDay() throws {
        var data = BuddyData()
        let habit = Habit(name: "Read", created: today.adding(-30))
        data.habits = [habit]
        let empty = Engine.history(habit, data: data, today: today).completion
        #expect(empty.firstDay == nil)
        #expect(empty.completedDays == 0)
        #expect(empty.totalDays == 0)
        try Engine.complete(habit.id, day: today, data: &data, today: today)
        let first = Engine.history(habit, data: data, today: today).completion
        #expect(first.firstDay == today)
        #expect(first.completedDays == 1)
        #expect(first.totalDays == 1)
    }

    @Test func completionStartsWithPartialOrNoteEntryAndUsesHistoricalTargets() throws {
        var data = BuddyData()
        var habit = Habit(name: "Read", created: today.adding(-30))
        habit.goals[0].tracking = .count; habit.goals[0].target = 2_000
        var later = habit.currentGoal
        later.from = today.adding(-2); later.target = 5_000
        habit.goals.append(later); data.habits = [habit]
        try Engine.note("Starting small", habitID: habit.id, day: today.adding(-9), data: &data, today: today)
        try Engine.setAmount(1_000, habitID: habit.id, day: today.adding(-8), data: &data, today: today)
        try Engine.setAmount(2_000, habitID: habit.id, day: today.adding(-3), data: &data, today: today)
        try Engine.setAmount(2_000, habitID: habit.id, day: today.adding(-2), data: &data, today: today)
        try Engine.setAmount(8_000, habitID: habit.id, day: today.adding(-1), data: &data, today: today)
        let summary = Engine.history(habit, data: data, today: today).completion
        #expect(summary.firstDay == today.adding(-9))
        #expect(summary.completedDays == 2)
        #expect(summary.totalDays == 10)
        // A backfill extends the summary and the tracked start without losing existing days.
        try Engine.complete(habit.id, day: today.adding(-40), data: &data, today: today)
        let backfilled = Engine.history(data.habits[0], data: data, today: today).completion
        #expect(backfilled.firstDay == today.adding(-40))
        #expect(backfilled.completedDays == 3)
        #expect(backfilled.totalDays == 41)
    }

    @Test func completionKeepsCalendarSpanButNeverCountsFrozenOrPausedDaysAsDone() throws {
        var data = try fixture(days: 9)
        var habit = data.habits[0]
        habit.goals[0].cadence = .daily
        habit.pauses = [Pause(from: today.adding(-5), through: today.adding(-4))]
        data.habits[0] = habit
        for offset in [-5, -4] { data.records[Record.key(habit.id, today.adding(offset))] = nil }
        try Engine.setAmount(0, habitID: habit.id, day: today.adding(-2), data: &data, today: today)
        data.settings.freezesPerMonth = 1
        try Engine.setFreeze(true, habitID: habit.id, day: today.adding(-2), data: &data, today: today)
        let summary = Engine.history(habit, data: data, today: today).completion
        #expect(summary.completedDays == 6)
        #expect(summary.totalDays == 10)
        data.habits[0].archived = today.adding(-1)
        let archived = Engine.history(data.habits[0], data: data, today: today.adding(10)).completion
        #expect(archived.completedDays == 6)
        #expect(archived.totalDays == 9)
    }

    @Test func quitCompletionIncludesDerivedCleanDaysAndExcludesSlips() throws {
        var data = BuddyData()
        var habit = Habit(name: "No smoking", created: today.adding(-9))
        habit.goals[0].mode = .quit; data.habits = [habit]
        try Engine.setAmount(1_000, habitID: habit.id, day: today.adding(-2), data: &data, today: today)
        let summary = Engine.history(habit, data: data, today: today).completion
        #expect(summary.firstDay == habit.created)
        #expect(summary.completedDays == 9)
        #expect(summary.totalDays == 10)
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
