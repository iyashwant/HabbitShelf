import XCTest
@testable import BuddyCore

final class BuddyCoreTests: XCTestCase {
    let today = Day(rawValue: "2026-10-03")!
    func fixture(tracking: Tracking = .yesNo, mode: HabitMode = .build, target: Int64 = 1_000, cadence: Cadence = .daily, days: Int = 1, start: String = "2026-09-28") -> (BuddyData, Habit) {
        var data = BuddyData(), habit = Habit(name: "Read", created: Day(rawValue: start)!)
        habit.goals[0].tracking = tracking; habit.goals[0].mode = mode; habit.goals[0].target = target; habit.goals[0].cadence = cadence; habit.goals[0].days = days
        data.habits = [habit]; return (data, habit)
    }
    func log(_ value: Int64, _ day: String, _ habit: Habit, _ data: inout BuddyData) throws { try Engine.setAmount(value, habitID: habit.id, day: Day(rawValue: day)!, data: &data, today: today) }
    func testCivilDatesRejectInvalidDates() {
        XCTAssertNil(Day(rawValue: "2026-02-30")); XCTAssertNil(Day(rawValue: "2026-2-03")); XCTAssertNil(Day(rawValue: "not a date"))
        XCTAssertEqual(Day(rawValue: "2024-02-29")?.adding(1).rawValue, "2024-03-01")
    }
    func testFastCivilArithmeticMatchesFoundation() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        var date = formatter.date(from: "1900-01-01")!, previous: Day?
        for _ in 0..<73_051 { // through 2099-12-31
            let text = formatter.string(from: date), day = Day(rawValue: text)!
            XCTAssertEqual(day.date, date); XCTAssertEqual(day.weekday, calendar.component(.weekday, from: date))
            XCTAssertEqual(Day(date, timeZone: calendar.timeZone), day)
            if let previous { XCTAssertEqual(previous.adding(1), day); XCTAssertEqual(previous.distance(to: day), 1); XCTAssertLessThan(previous, day) }
            if text.hasSuffix("-01") { XCTAssertEqual(day.adding(-1), day.adding(-1).startOfMonth.endOfMonth) }
            previous = day; date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        // Foundation is Julian before October 1582; those dates keep its exact rules.
        XCTAssertNil(Day(rawValue: "1582-10-10")); XCTAssertEqual(Day(rawValue: "1582-10-04")?.adding(1).rawValue, "1582-10-15")
        XCTAssertEqual(Day(rawValue: "1583-01-01")?.adding(-1).rawValue, "1582-12-31")
        for bad in ["2026-13-01", "2026-00-10", "2026-04-31", "2026-04-00", "2025-02-29", "2026-04-1a", "2026/04/10", "2026-04-100", "２０２６-04-10"] { XCTAssertNil(Day(rawValue: bad), bad) }
    }
    func testWeekStartsEveryWeekday() { for first in 1...7 { XCTAssertEqual(today.startOfWeek(first).weekday, first); XCTAssertLessThanOrEqual(today.startOfWeek(first), today) } }
    func testFebruaryLeapAndNormalEnd() { XCTAssertEqual(Day(rawValue: "2024-02-15")!.endOfMonth.rawValue, "2024-02-29"); XCTAssertEqual(Day(rawValue: "2026-02-15")!.endOfMonth.rawValue, "2026-02-28") }
    func testTravelDoesNotMoveStoredDay() throws {
        let date = ISO8601DateFormatter().date(from: "2026-10-02T22:30:00Z")!
        let east = Day(date, timeZone: TimeZone(identifier: "Asia/Kolkata")!), west = Day(date, timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        XCTAssertEqual(east.rawValue, "2026-10-03"); XCTAssertEqual(west.rawValue, "2026-10-02")
        let bytes = try JSONEncoder().encode(east); XCTAssertEqual(try JSONDecoder().decode(Day.self, from: bytes), east)
    }
    func testDSTArithmeticIsCivil() { XCTAssertEqual(Day(rawValue: "2026-03-08")!.adding(1).rawValue, "2026-03-09"); XCTAssertEqual(Day(rawValue: "2026-11-01")!.adding(-1).rawValue, "2026-10-31") }
    func testExactDecimalArithmetic() throws { XCTAssertEqual(try Amount.parse("0.1") + Amount.parse("0.2"), try Amount.parse("0.3")); XCTAssertEqual(Amount.text(1_230), "1.23") }
    func testLocalizedDecimalParsing() throws { XCTAssertEqual(try Amount.parse("1,25", locale: Locale(identifier: "de_DE")), 1_250) }
    func testInvalidAmounts() { for text in ["", ".", "-1", "1.0001", "NaN", "1e5", "9.3.3", "1000000001"] { XCTAssertThrowsError(try Amount.parse(text), text) } }
    func testYesNoRepeatedTap() throws { var (data, h) = fixture(); try log(1_000, "2026-10-03", h, &data); XCTAssertTrue(Engine.progress(h, day: today, data: data, today: today).success); try log(0, "2026-10-03", h, &data); XCTAssertFalse(Engine.progress(h, day: today, data: data, today: today).success) }
    func testCountBelowEqualAboveGoal() throws { var (data, h) = fixture(tracking: .count, target: 3_000); for value: Int64 in [2_000, 3_000, 5_000] { try log(value, "2026-10-03", h, &data); XCTAssertEqual(Engine.progress(h, day: today, data: data, today: today).success, value >= 3_000) }; XCTAssertEqual(Engine.stats(h, data: data, today: today).completions, 1) }
    func testCountRejectsFraction() { var (data, h) = fixture(tracking: .count); XCTAssertThrowsError(try log(1_200, "2026-10-03", h, &data)) }
    func testMeasureHitsExactTarget() throws { var (data, h) = fixture(tracking: .measure, target: 300); try Engine.increment(100, habitID: h.id, day: today, data: &data, today: today); try Engine.increment(200, habitID: h.id, day: today, data: &data, today: today); XCTAssertTrue(Engine.progress(h, day: today, data: data, today: today).success) }
    func testOverGoalCompleteIsIdempotent() throws { var (data, h) = fixture(tracking: .count, target: 2_000); try log(6_000, "2026-10-03", h, &data); try Engine.complete(h.id, day: today, data: &data, today: today); XCTAssertEqual(data.record(h.id, today).amount, 6_000) }
    func testClearKeepsNote() throws { var (data, h) = fixture(); try Engine.note("hello", habitID: h.id, day: today, data: &data, today: today); try log(1_000, "2026-10-03", h, &data); try log(0, "2026-10-03", h, &data); XCTAssertEqual(data.record(h.id, today).note, "hello") }
    func testNoteOnlyHasNoProgress() throws { var (data, h) = fixture(); try Engine.note("rest day", habitID: h.id, day: today, data: &data, today: today); XCTAssertFalse(Engine.progress(h, day: today, data: data, today: today).success) }
    func testAppendNote() throws { var (data, h) = fixture(); try Engine.note("one", habitID: h.id, day: today, data: &data, today: today); try Engine.note("two", append: true, habitID: h.id, day: today, data: &data, today: today); XCTAssertEqual(data.record(h.id, today).note, "one\ntwo") }
    func testFutureRejected() { var (data, h) = fixture(); XCTAssertThrowsError(try log(1_000, "2026-10-04", h, &data)); XCTAssertFalse(h.loggable(on: today.adding(1), today: today)) }
    func testBackfillBeforeStartMovesStartBack() throws {
        var (data, h) = fixture(cadence: .daily, start: "2026-09-28")
        try log(1_000, "2026-09-20", h, &data)
        let moved = data.habits[0], day = Day(rawValue: "2026-09-20")!
        XCTAssertEqual(moved.created, day); XCTAssertEqual(moved.goals.map(\.from), [day])
        XCTAssertTrue(Engine.progress(moved, day: day, data: data, today: today).success)
        XCTAssertNoThrow(try DataValidation.validate(data, today: today))
        let stats = Engine.stats(moved, data: data, today: today)
        XCTAssertEqual(stats.completions, 1); XCTAssertEqual(stats.eligibleDays, 13); XCTAssertEqual(stats.bestStreak, 1)
    }
    func testBackfillKeepsLaterGoalVersions() throws {
        var (data, h) = fixture(tracking: .count, target: 2_000, start: "2026-09-28")
        h.goals.append({ var g = h.goals[0]; g.from = Day(rawValue: "2026-10-01")!; g.target = 5_000; return g }()); data.habits[0] = h
        try log(2_000, "2026-09-01", h, &data)
        XCTAssertEqual(data.habits[0].goals.map(\.from.rawValue), ["2026-09-01", "2026-10-01"])
        XCTAssertTrue(Engine.progress(data.habits[0], day: Day(rawValue: "2026-09-01")!, data: data, today: today).success)
    }
    func testEmptyBuildWriteBeforeStartChangesNothing() throws {
        var (data, h) = fixture(start: "2026-09-28"); let before = data
        try log(0, "2026-09-20", h, &data); try Engine.note("", habitID: h.id, day: Day(rawValue: "2026-09-20")!, data: &data, today: today)
        XCTAssertEqual(data, before)
    }
    func testNoteBeforeStartMovesStartBack() throws {
        var (data, h) = fixture(start: "2026-09-28"); let day = Day(rawValue: "2026-09-25")!
        try Engine.note("travel", habitID: h.id, day: day, data: &data, today: today)
        XCTAssertEqual(data.habits[0].created, day); XCTAssertEqual(data.record(h.id, day).note, "travel"); XCTAssertFalse(Engine.progress(data.habits[0], day: day, data: data, today: today).success)
    }
    func testQuitCleanDayBeforeStartBeginsCleanRun() throws {
        var (data, h) = fixture(mode: .quit, start: "2026-09-28")
        try log(0, "2026-09-20", h, &data)
        XCTAssertEqual(data.habits[0].created.rawValue, "2026-09-20"); XCTAssertEqual(Engine.stats(data.habits[0], data: data, today: today).currentStreak, 14)
    }
    func testBackfillBeforeStartRespectsArchiveModeAndEpoch() throws {
        var (data, h) = fixture(start: "2026-09-28")
        XCTAssertThrowsError(try log(1_000, "1969-12-31", h, &data))
        h.goals.append({ var g = h.goals[0]; g.from = today; g.mode = .quit; return g }()); data.habits[0] = h
        XCTAssertThrowsError(try log(1_000, "2026-09-20", h, &data)) { XCTAssertEqual(($0 as? BuddyError)?.errorDescription, BuddyError.locked.errorDescription) }
        h.goals.removeLast(); h.archived = today; data.habits[0] = h
        XCTAssertThrowsError(try log(1_000, "2026-09-20", h, &data)); XCTAssertEqual(data.habits[0].created.rawValue, "2026-09-28")
    }
    func testUnfinishedTodayKeepsDailyStreak() throws { var (data, h) = fixture(); for day in ["2026-10-01", "2026-10-02"] { try log(1_000, day, h, &data) }; XCTAssertEqual(Engine.stats(h, data: data, today: today).currentStreak, 2) }
    func testMissedYesterdayBreaksDailyStreak() throws { var (data, h) = fixture(); try log(1_000, "2026-10-01", h, &data); let s = Engine.stats(h, data: data, today: today); XCTAssertEqual(s.currentStreak, 0); XCTAssertEqual(s.bestStreak, 1) }
    func testWeeklyCountsDistinctDates() throws { var (data, h) = fixture(tracking: .count, target: 1_000, cadence: .weekly, days: 3); for _ in 0..<12 { try Engine.increment(habitID: h.id, day: today, data: &data, today: today) }; XCTAssertEqual(Engine.stats(h, data: data, today: today).completions, 1); XCTAssertEqual(Engine.stats(h, data: data, today: today).currentStreak, 0) }
    func testTwoSuccessfulWeeksCountDatesNotPeriods() throws {
        var (data, h) = fixture(cadence: .weekly, days: 3, start: "2026-09-21")
        for d in ["2026-09-21", "2026-09-22", "2026-09-23", "2026-09-28", "2026-09-29", "2026-09-30"] { try log(1_000, d, h, &data) }
        XCTAssertEqual(Engine.stats(h, data: data, today: today).currentStreak, 6)
    }
    func testUnreachableCurrentWeekBreaks() throws { var (data, h) = fixture(cadence: .weekly, days: 3, start: "2026-09-21"); for d in ["2026-09-21", "2026-09-22", "2026-09-23"] { try log(1_000, d, h, &data) }; XCTAssertEqual(Engine.stats(h, data: data, today: today).currentStreak, 0) }
    func testMonthlyTargetCapsToShortMonth() throws { let febEnd = Day(rawValue: "2026-02-28")!; var (data, h) = fixture(cadence: .monthly, days: 31, start: "2026-02-01"); for d in Day.range(h.created, febEnd) { try Engine.setAmount(1_000, habitID: h.id, day: d, data: &data, today: febEnd) }; XCTAssertEqual(Engine.stats(h, data: data, today: febEnd).currentStreak, 28) }
    func testQuitDerivesCleanDaysWithoutRecords() { let (data, h) = fixture(mode: .quit); XCTAssertTrue(Engine.progress(h, day: today, data: data, today: today).success); XCTAssertEqual(data.records.count, 0); XCTAssertEqual(Engine.stats(h, data: data, today: today).currentStreak, 6); XCTAssertEqual(Engine.stats(h, data: data, today: today).completions, 0) }
    func testQuitThresholdIsStrict() throws { var (data, h) = fixture(tracking: .measure, mode: .quit, target: 3_000); try log(2_999, "2026-10-03", h, &data); XCTAssertTrue(Engine.progress(h, day: today, data: data, today: today).success); try log(3_000, "2026-10-03", h, &data); XCTAssertTrue(Engine.progress(h, day: today, data: data, today: today).slip) }
    func testHistoricalGoalUnchanged() throws { var (data, h) = fixture(tracking: .count, target: 2_000); try log(2_000, "2026-10-02", h, &data); h.goals[0].target = 4_000; try Engine.saveHabit(h, data: &data, today: today); let updated = data.habits[0]; XCTAssertEqual(updated.goal(on: today.adding(-1)).target, 2_000); XCTAssertEqual(updated.goal(on: today).target, 4_000); XCTAssertTrue(Engine.progress(updated, day: today.adding(-1), data: data, today: today).success) }
    func testSecondEditTodayReplacesVersion() throws { var (data, h) = fixture(); h.detail = "first"; try Engine.saveHabit(h, data: &data, today: today); h = data.habits[0]; h.detail = "second"; try Engine.saveHabit(h, data: &data, today: today); XCTAssertEqual(data.habits[0].goals.count, 2) }
    func testModeConversionKeepsHistoryAndLocksAmounts() throws { var (data, h) = fixture(); try log(1_000, "2026-10-02", h, &data); try Engine.note("keep", habitID: h.id, day: today, data: &data, today: today); h.goals[0].mode = .quit; try Engine.saveHabit(h, data: &data, today: today); XCTAssertEqual(data.habits[0].goal(on: today.adding(-1)).mode, .build); XCTAssertThrowsError(try Engine.setAmount(0, habitID: h.id, day: today.adding(-1), data: &data, today: today)); XCTAssertEqual(data.record(h.id, today).note, "keep"); try Engine.note("still editable", habitID: h.id, day: today.adding(-1), data: &data, today: today) }
    func testArchiveBlocksWrites() { var (data, h) = fixture(); h.archived = today; data.habits[0] = h; XCTAssertThrowsError(try log(1_000, "2026-10-03", h, &data)) }
    func testPausedQuitDaysDoNotBecomeClean() { var (data, h) = fixture(mode: .quit); h.pauses = [Pause(from: today.adding(-3), through: today.adding(-1))]; data.habits[0] = h; XCTAssertFalse(Engine.progress(h, day: today.adding(-2), data: data, today: today).available); XCTAssertEqual(Engine.stats(h, data: data, today: today).currentStreak, 1) }
    func testDeleteCategoryPreservesHabitAndHistory() { var (data, h) = fixture(); let category = Category(name: "Health"); data.categories = [category]; h.categories = [category.id]; data.habits[0] = h; Engine.deleteCategory(category.id, data: &data); XCTAssertEqual(data.habits.count, 1); XCTAssertTrue(data.habits[0].categories.isEmpty) }
    func testValidationRejectsDuplicateIDsAndFutureLogs() throws { var (data, h) = fixture(); data.habits.append(h); XCTAssertThrowsError(try DataValidation.validate(data, today: today)); data.habits.removeLast(); let r = Record(habitID: h.id, day: today.adding(1)); data.records[r.key] = r; XCTAssertThrowsError(try DataValidation.validate(data, today: today)) }
    func testValidationRejectsBadGoalOrder() { var (data, h) = fixture(); h.goals.append(h.goals[0]); data.habits[0] = h; XCTAssertThrowsError(try DataValidation.validate(data, today: today)) }
    func testWeeklyStreakCountsSuccessfulWeeks() throws {
        var (data, h) = fixture(cadence: .weekly, days: 2, start: "2026-09-07")
        for d in ["2026-09-07", "2026-09-08", "2026-09-15", "2026-09-16", "2026-09-22", "2026-09-23", "2026-10-01"] { try log(1_000, d, h, &data) }
        // The current week needs one more day and can still get it, so it keeps the run without adding to it.
        XCTAssertEqual(Engine.streak(data.habits[0], data: data, today: today), StreakSummary(value: 3, unit: .weeks))
        try log(1_000, "2026-10-02", h, &data)
        XCTAssertEqual(Engine.streak(data.habits[0], data: data, today: today).value, 4)
        try log(0, "2026-09-16", h, &data)
        XCTAssertEqual(Engine.streak(data.habits[0], data: data, today: today).value, 2)
    }
    func testUnreachableCurrentWeekEndsWeeklyStreak() throws {
        var (data, h) = fixture(cadence: .weekly, days: 5, start: "2026-09-21")
        for d in Day.range(Day(rawValue: "2026-09-21")!, Day(rawValue: "2026-09-25")!) { try log(1_000, d.rawValue, h, &data) }
        XCTAssertEqual(Engine.streak(data.habits[0], data: data, today: today).value, 0)
    }
    func testMonthlyStreakCapsPartialFirstMonth() throws {
        var (data, h) = fixture(cadence: .monthly, days: 10, start: "2026-08-25")
        for d in Day.range(Day(rawValue: "2026-08-25")!, Day(rawValue: "2026-08-31")!) + Day.range(Day(rawValue: "2026-09-01")!, Day(rawValue: "2026-09-10")!) { try log(1_000, d.rawValue, h, &data) }
        XCTAssertEqual(Engine.streak(data.habits[0], data: data, today: today), StreakSummary(value: 2, unit: .months))
    }
    func testDailyStreakSummaryUsesDays() throws {
        var (data, h) = fixture()
        for d in ["2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02"] { try log(1_000, d, h, &data) }
        XCTAssertEqual(Engine.streak(data.habits[0], data: data, today: today), StreakSummary(value: 5, unit: .days))
    }
    func testYearStatsCountsTrackedDaysAndLongestRun() throws {
        var (data, h) = fixture()
        for d in ["2026-09-28", "2026-09-29", "2026-10-01", "2026-10-02", "2026-10-03"] { try log(1_000, d, h, &data) }
        XCTAssertEqual(Engine.yearStats(data.habits[0], year: 2026, data: data, today: today), YearStats(completions: 5, eligible: 6, longestRun: 3))
        XCTAssertEqual(Engine.yearStats(data.habits[0], year: 2025, data: data, today: today), YearStats())
        XCTAssertEqual(Engine.yearStats(data.habits[0], year: 2027, data: data, today: today), YearStats())
    }
    func testDashboardRoundTripsAndDefaultsAreStable() throws {
        var (data, h) = fixture()
        XCTAssertNil(try DataValidation.decode(DataValidation.encode(data), today: today).settings.dashboard)
        XCTAssertTrue(DashboardWidget.defaults(for: []).isEmpty)
        let defaults = DashboardWidget.defaults(for: [h])
        XCTAssertEqual(defaults, DashboardWidget.defaults(for: [h]))
        XCTAssertEqual(defaults.last?.kind, .list); XCTAssertNil(defaults.last?.habitID)
        XCTAssertTrue(defaults.allSatisfy { $0.kind.needsHabit ? $0.habitID == h.id : $0.habitID == nil })
        XCTAssertTrue(defaults.allSatisfy { $0.visible(in: data) })
        data.settings.dashboard = [DashboardWidget(kind: .weeks, habitID: h.id, style: .dark), DashboardWidget(kind: .list)]
        XCTAssertEqual(try DataValidation.decode(DataValidation.encode(data), today: today).settings.dashboard, data.settings.dashboard)
        data.settings.dashboard!.append(data.settings.dashboard![0])
        XCTAssertThrowsError(try DataValidation.validate(data, today: today))
    }
    func testRoutineCompletesOpenBuildHabitsOnly() throws {
        var data = BuddyData(), habits: [Habit] = []
        for (n, name) in ["Stretch", "Water", "Sugar", "Read"].enumerated() {
            var h = Habit(name: name, created: Day(rawValue: "2026-09-01")!); h.order = n; h.goals[0].cadence = .daily
            if n == 1 { h.goals[0].tracking = .count; h.goals[0].target = 3_000 }
            if n == 2 { h.goals[0].mode = .quit }
            habits.append(h)
        }
        data.habits = habits
        try Engine.setAmount(1_000, habitID: habits[1].id, day: today, data: &data, today: today)
        try Engine.setAmount(1_000, habitID: habits[3].id, day: today, data: &data, today: today)
        var routine = Routine(name: "Morning"); routine.habitIDs = habits.map(\.id); data.routines = [routine]
        XCTAssertNoThrow(try DataValidation.validate(data, today: today))
        XCTAssertEqual(try Engine.completeRoutine(routine.id, day: today, data: &data, today: today), 2)
        XCTAssertEqual(data.record(habits[1].id, today).amount, 3_000, "A count is completed to its target")
        XCTAssertEqual(data.record(habits[2].id, today).amount, 0, "Quit habits are left alone")
        XCTAssertTrue(Engine.routineProgress(routine, data: data, day: today, today: today) == (4, 4))
        XCTAssertEqual(try Engine.completeRoutine(routine.id, day: today, data: &data, today: today), 0)
        XCTAssertThrowsError(try Engine.completeRoutine(UUID(), day: today, data: &data, today: today))
    }
    func testRoutinesValidateAndDecodeFromOlderFiles() throws {
        var (data, h) = fixture()
        var object = try JSONSerialization.jsonObject(with: DataValidation.encode(data)) as! [String: Any]
        object.removeValue(forKey: "routines")
        XCTAssertEqual(try DataValidation.decode(JSONSerialization.data(withJSONObject: object), today: today), data)
        var routine = Routine(name: "Evening"); routine.habitIDs = [h.id]; data.routines = [routine]
        XCTAssertEqual(try DataValidation.decode(DataValidation.encode(data), today: today), data)
        data.routines[0].habitIDs.append(UUID()); XCTAssertThrowsError(try DataValidation.validate(data, today: today))
        data.routines[0].habitIDs = [h.id, h.id]; XCTAssertThrowsError(try DataValidation.validate(data, today: today))
        data.routines[0].habitIDs = [h.id]; data.routines[0].name = " "; XCTAssertThrowsError(try DataValidation.validate(data, today: today))
        data.routines[0].name = "Evening"; try log(1_000, "2026-10-02", h, &data)
        Engine.deleteHabit(h.id, data: &data)
        XCTAssertTrue(data.habits.isEmpty); XCTAssertTrue(data.records.isEmpty); XCTAssertEqual(data.routines[0].habitIDs, [])
        XCTAssertNoThrow(try DataValidation.validate(data, today: today))
    }
    func testHiddenHabitsLeaveScreensButKeepTheirData() throws {
        var (data, h) = fixture()
        var g = Habit(name: "Smoke-free", created: Day(rawValue: "2026-09-28")!); g.order = 1; data.habits.append(g)
        try log(1_000, "2026-10-02", h, &data); try log(1_000, "2026-10-02", g, &data); try Engine.note("private", habitID: g.id, day: today, data: &data, today: today)
        var routine = Routine(name: "Evening"); routine.habitIDs = [h.id, g.id]; var alone = Routine(name: "Quiet"); alone.habitIDs = [g.id]; data.routines = [routine, alone]
        data.settings.dashboard = [DashboardWidget(kind: .streak, habitID: g.id), DashboardWidget(kind: .streak, habitID: h.id)]
        XCTAssertFalse(String(decoding: try DataValidation.encode(data), as: UTF8.self).contains("hidden"), "A shown habit writes no flag, so files stay as before")
        XCTAssertEqual(data.withoutHidden, data)
        data.habits[1].hidden = true
        XCTAssertNoThrow(try DataValidation.validate(data, today: today))
        XCTAssertEqual(try DataValidation.decode(DataValidation.encode(data), today: today), data)
        let shown = data.withoutHidden
        XCTAssertEqual(shown.active.map(\.id), [h.id])
        XCTAssertEqual(shown.records, data.records, "Records stay; only their habit finds them, and copying them would slow each check-in")
        XCTAssertEqual(shown.routines.map(\.habitIDs), [[h.id, g.id]], "Routines keep the hidden habit; one with only hidden habits is left out")
        XCTAssertFalse(shown.settings.dashboard![0].visible(in: shown)); XCTAssertTrue(shown.settings.dashboard![1].visible(in: shown))
        XCTAssertEqual(WeekRecap(data: shown, week: today, today: today).total, WeekRecap(data: { var d = data; d.habits.removeLast(); return d }(), week: today, today: today).total)
        // Hiding changes what is shown, not the data: the hidden habit still logs, and routines still complete it.
        try log(1_000, "2026-10-01", g, &data); XCTAssertTrue(Engine.progress(data.habits[1], day: Day(rawValue: "2026-10-01")!, data: data, today: today).success)
        try Engine.completeRoutine(routine.id, day: today, data: &data, today: today); XCTAssertTrue(Engine.progress(data.habits[1], day: today, data: data, today: today).success)
        data.habits[1].hidden = nil; XCTAssertEqual(data.withoutHidden.active.count, 2)
    }
    func testReorderingShownHabitsKeepsHiddenOnesInPlace() {
        var data = BuddyData()
        data.habits = ["A", "B", "C", "D"].enumerated().map { n, name in var habit = Habit(name: name, created: today); habit.order = n; return habit }
        data.habits[2].hidden = true
        let ids = data.habits.map(\.id)
        data.reorder([ids[3], ids[1], ids[0]])
        XCTAssertEqual(data.active.map(\.name), ["D", "B", "C", "A"]); XCTAssertEqual(data.active.map(\.order), [0, 1, 2, 3])
        data.reorder(data.active.map(\.id).reversed()); XCTAssertEqual(data.active.map(\.name), ["A", "C", "B", "D"])
    }
    func testStreakFreezeBridgesOneMissedDailyDay() throws {
        var (data, h) = fixture(start: "2026-09-25")
        for d in ["2026-09-28", "2026-09-29", "2026-10-01", "2026-10-02"] { try log(1_000, d, h, &data) }
        let missed = Day(rawValue: "2026-09-30")!
        XCTAssertEqual(Engine.stats(h, data: data, today: today).currentStreak, 2)
        XCTAssertThrowsError(try Engine.setFreeze(true, habitID: h.id, day: missed, data: &data, today: today)) { XCTAssertEqual(($0 as? BuddyError)?.errorDescription, BuddyError.noFreezesLeft.errorDescription) }
        data.settings.freezesPerMonth = 1
        try Engine.setFreeze(true, habitID: h.id, day: missed, data: &data, today: today)
        XCTAssertTrue(Engine.progress(h, day: missed, data: data, today: today).frozen)
        let stats = Engine.stats(h, data: data, today: today)
        XCTAssertEqual(stats.currentStreak, 4, "A frozen day neither adds to nor breaks the streak")
        XCTAssertEqual(stats.completions, 4); XCTAssertEqual(stats.eligibleDays, 8, "The completion rate still counts the frozen day as missed")
        XCTAssertEqual(Engine.yearStats(h, year: 2026, data: data, today: today).longestRun, 4)
        XCTAssertNoThrow(try DataValidation.validate(data, today: today))
        XCTAssertThrowsError(try Engine.setFreeze(true, habitID: h.id, day: Day(rawValue: "2026-09-27")!, data: &data, today: today)) { XCTAssertEqual(($0 as? BuddyError)?.errorDescription, BuddyError.noFreezesLeft.errorDescription) }
        XCTAssertEqual(Engine.freezesUsed(h, month: missed, data: data), 1)
        for day in [today, Day(rawValue: "2026-09-29")!, today.adding(1)] { XCTAssertThrowsError(try Engine.setFreeze(true, habitID: h.id, day: day, data: &data, today: today)) }
        try log(1_000, "2026-09-30", h, &data)
        XCTAssertNil(data.record(h.id, missed).frozen, "Logging the day replaces its freeze")
        XCTAssertEqual(Engine.stats(h, data: data, today: today).currentStreak, 5)
        var bad = data.record(h.id, today); bad.frozen = true; data.records[bad.key] = bad
        XCTAssertThrowsError(try DataValidation.validate(data, today: today))
    }
    func testStreakFreezeOnlyForDailyBuildGoals() throws {
        for (cadence, mode) in [(Cadence.weekly, HabitMode.build), (.none, .build), (.daily, .quit)] {
            var (data, h) = fixture(mode: mode, cadence: cadence, days: cadence == .weekly ? 3 : 1); data.settings.freezesPerMonth = 3
            XCTAssertThrowsError(try Engine.setFreeze(true, habitID: h.id, day: today.adding(-2), data: &data, today: today), "\(cadence) \(mode)")
        }
    }
    func testTimerLogsElapsedTimeInTheGoalUnit() throws {
        func habit(_ tracking: Tracking, _ unit: String, mode: HabitMode = .build) -> (BuddyData, Habit) {
            var (data, h) = fixture(tracking: tracking, mode: mode, target: tracking == .yesNo ? 1_000 : 10_000); h.goals[0].unit = unit; data.habits[0] = h; return (data, h)
        }
        var (data, h) = habit(.measure, "minutes")
        XCTAssertEqual(try Engine.logTimer(seconds: 750, habitID: h.id, day: today, data: &data, today: today), 12_500)
        XCTAssertEqual(data.record(h.id, today).amount, 12_500)
        (data, h) = habit(.count, "Min")
        XCTAssertEqual(try Engine.logTimer(seconds: 750, habitID: h.id, day: today, data: &data, today: today), 12_000)
        XCTAssertEqual(try Engine.logTimer(seconds: 30, habitID: h.id, day: today, data: &data, today: today), 0)
        XCTAssertEqual(data.record(h.id, today).amount, 12_000)
        (data, h) = habit(.yesNo, "")
        _ = try Engine.logTimer(seconds: 5, habitID: h.id, day: today, data: &data, today: today)
        XCTAssertTrue(Engine.progress(h, day: today, data: data, today: today).success)
        for (tracking, unit, mode) in [(Tracking.measure, "km", HabitMode.build), (.yesNo, "", .quit)] {
            (data, h) = habit(tracking, unit, mode: mode)
            XCTAssertNil(try Engine.logTimer(seconds: 600, habitID: h.id, day: today, data: &data, today: today)); XCTAssertTrue(data.records.isEmpty)
        }
        var goal = Goal(); goal.tracking = .measure; goal.unit = "Hours"
        XCTAssertEqual(TimerUnit(goal), .hours); XCTAssertEqual(TimerUnit(goal)?.duration(target: 1_500), 5_400)
        XCTAssertEqual(TimerUnit.seconds.amount(seconds: 90.25, whole: false), 90_250)
    }
    func testInsightsFindWeekdaysTrendHoursAndHabitsThatLapseTogether() throws {
        var data = BuddyData(), ids: [UUID] = []
        let misses = [["2026-09-16", "2026-09-20", "2026-09-23", "2026-09-30"], ["2026-09-16", "2026-09-23", "2026-09-30"]]
        for n in 0..<2 {
            var h = Habit(name: "H\(n)", created: Day(rawValue: "2026-09-14")!); h.order = n; h.goals[0].cadence = .daily; data.habits.append(h); ids.append(h.id)
            for day in Day.range(h.created, today) where !misses[n].contains(day.rawValue) { try Engine.setAmount(1_000, habitID: h.id, day: day, data: &data, today: today) }
        }
        data.records[Record.key(ids[0], today)]?.completionHour = 7
        let insights = InsightsSummary(data: data, from: Day(rawValue: "2026-09-01")!, today: today)
        XCTAssertEqual(insights.total, DayRate(done: 33, eligible: 40))
        XCTAssertEqual(insights.weekdays[3], DayRate(done: 0, eligible: 6), "Every Wednesday was missed")
        XCTAssertEqual(insights.weekdays[0], DayRate(done: 3, eligible: 4))
        XCTAssertEqual(insights.worstWeekday, 4); XCTAssertEqual(insights.bestWeekday, 2)
        XCTAssertEqual(insights.months.count, 12); XCTAssertEqual(insights.months[11].month.rawValue, "2026-10-01")
        XCTAssertEqual(insights.months[10].rate, DayRate(done: 27, eligible: 34)); XCTAssertEqual(insights.months[11].rate, DayRate(done: 6, eligible: 6))
        XCTAssertGreaterThanOrEqual(insights.hours[7], 1)
        XCTAssertEqual(insights.pairs.count, 1); XCTAssertEqual(insights.pairs[0].together, 3); XCTAssertEqual(insights.pairs[0].either, 4)
        XCTAssertTrue(InsightsSummary(data: data, habitIDs: [ids[1]], from: today, today: today).pairs.isEmpty)
    }
    func testWeekRecapComparesWithThePreviousWeek() throws {
        var data = BuddyData(), ids: [UUID] = []
        for n in 0..<2 {
            var h = Habit(name: "H\(n)", created: Day(rawValue: "2026-09-14")!); h.order = n; h.goals[0].cadence = .daily; data.habits.append(h); ids.append(h.id)
            for day in Day.range(h.created, today) where !["2026-09-23", "2026-09-30"].contains(day.rawValue) { try Engine.setAmount(1_000, habitID: h.id, day: day, data: &data, today: today) }
        }
        try Engine.note("felt good", habitID: ids[0], day: Day(rawValue: "2026-09-29")!, data: &data, today: today)
        let recap = WeekRecap(data: data, week: today, today: today)
        XCTAssertEqual(recap.start.rawValue, "2026-09-28"); XCTAssertEqual(recap.end.rawValue, "2026-10-04")
        XCTAssertEqual(recap.total, DayRate(done: 10, eligible: 12)); XCTAssertEqual(recap.previous, DayRate(done: 12, eligible: 14))
        XCTAssertEqual(recap.rows.count, 2); XCTAssertEqual(recap.rows[0].days, [true, true, false, true, true, true, nil])
        XCTAssertEqual(recap.perfectDays, 5); XCTAssertEqual(recap.bestDay?.rawValue, "2026-09-28"); XCTAssertEqual(recap.notes, 1)
    }
    func testWeekRatesAndRecentRateCountTrackedDays() throws {
        var data = BuddyData()
        for n in 0..<2 {
            var h = Habit(name: "H\(n)", created: Day(rawValue: "2026-09-14")!); h.order = n; h.goals[0].cadence = .daily; data.habits.append(h)
            for day in Day.range(h.created, today) where !["2026-09-23", "2026-09-30"].contains(day.rawValue) { try Engine.setAmount(1_000, habitID: h.id, day: day, data: &data, today: today) }
        }
        let week = WeekRates(habits: data.habits, data: data, week: today, today: today)
        XCTAssertEqual(week.start.rawValue, "2026-09-28"); XCTAssertEqual(week.total, DayRate(done: 10, eligible: 12)); XCTAssertEqual(week.previous, DayRate(done: 12, eligible: 14))
        XCTAssertEqual(week.days[2], DayRate(done: 0, eligible: 2)); XCTAssertEqual(week.days[5], DayRate(done: 2, eligible: 2)); XCTAssertEqual(week.days[6], DayRate())
        XCTAssertEqual(WeekRates(habits: [data.habits[0]], data: data, week: today, today: today).total, DayRate(done: 5, eligible: 6))
        // Thirty days reach back only to the habit's start; an open today is not counted yet.
        XCTAssertEqual(DayRate(data.habits[0], days: 30, data: data, today: today), DayRate(done: 18, eligible: 20))
        XCTAssertEqual(DayRate(data.habits[0], days: 7, data: data, today: today), DayRate(done: 6, eligible: 7))
        try Engine.setAmount(0, habitID: data.habits[0].id, day: today, data: &data, today: today)
        XCTAssertEqual(DayRate(data.habits[0], days: 7, data: data, today: today), DayRate(done: 5, eligible: 6))
    }
    func testDashboardWidgetOptionsRoundTripAndFallBack() throws {
        var (data, h) = fixture()
        var other = Habit(name: "Walk", created: Day(rawValue: "2026-09-28")!); other.order = 1; data.habits.append(other)
        var routine = Routine(name: "Morning"); routine.habitIDs = [h.id]; data.routines = [routine]
        var checks = DashboardWidget(kind: .checks, style: .tinted, size: .large); checks.habitIDs = [other.id]; checks.title = "Evening"; checks.color = "rose"
        var routineWidget = DashboardWidget(kind: .routine, size: .medium); routineWidget.routineID = routine.id
        data.settings.dashboard = [checks, routineWidget, DashboardWidget(kind: .streak, habitID: h.id, size: .large)]
        XCTAssertEqual(try DataValidation.decode(DataValidation.encode(data), today: today).settings.dashboard, data.settings.dashboard)
        XCTAssertEqual(checks.resolvedSize, .large); XCTAssertTrue(checks.wide); XCTAssertEqual(routineWidget.resolvedSize, .medium)
        // A size the design doesn't come in falls back to its default.
        XCTAssertEqual(data.settings.dashboard![2].resolvedSize, .small); XCTAssertFalse(data.settings.dashboard![2].wide)
        XCTAssertEqual(DashboardWidget(kind: .list).resolvedSize, .large); XCTAssertEqual(DashboardWidget(kind: .checks).resolvedSize, .medium)
        XCTAssertEqual(checks.habits(in: data).map(\.name), ["Walk"]); XCTAssertEqual(DashboardWidget(kind: .week).habits(in: data).map(\.name), ["Read", "Walk"])
        XCTAssertEqual(DashboardWidget(kind: .ring, habitID: h.id).habits(in: data).map(\.name), ["Read"]); XCTAssertTrue(routineWidget.habits(in: data).isEmpty)
        XCTAssertTrue(checks.visible(in: data)); XCTAssertTrue(routineWidget.visible(in: data))
        // Widgets whose habits are all archived, or whose routine was deleted, are hidden rather than removed.
        data.habits[1].archived = today
        XCTAssertFalse(checks.visible(in: data)); XCTAssertTrue(DashboardWidget(kind: .week).visible(in: data))
        data.routines = []; XCTAssertFalse(routineWidget.visible(in: data)); XCTAssertFalse(DashboardWidget(kind: .routine).visible(in: data))
        // Widgets saved before these options decode with defaults, and unset options aren't written.
        let old = #"{"id":"00000000-0000-0000-0002-000000000000","kind":"month","habitID":"\#(h.id.uuidString)"}"#
        let widget = try JSONDecoder().decode(DashboardWidget.self, from: Data(old.utf8))
        XCTAssertEqual(widget.style, .automatic); XCTAssertNil(widget.size); XCTAssertNil(widget.habitIDs); XCTAssertNil(widget.title); XCTAssertEqual(widget.resolvedSize, .small)
        let encoded = String(decoding: try JSONEncoder().encode(DashboardWidget(kind: .streak)), as: UTF8.self)
        XCTAssertFalse(encoded.contains("habitIDs")); XCTAssertFalse(encoded.contains("title")); XCTAssertFalse(encoded.contains("size"))
        data.habits[1].archived = nil
        checks.habitIDs = [other.id, other.id]; data.settings.dashboard = [checks]; XCTAssertThrowsError(try DataValidation.validate(data, today: today))
        checks.habitIDs = nil; checks.title = String(repeating: "x", count: 101); data.settings.dashboard = [checks]; XCTAssertThrowsError(try DataValidation.validate(data, today: today))
    }
    func testMilestonesTrackBestStreakAndTotals() throws {
        var (data, h) = fixture(start: "2026-09-20")
        for day in Day.range(Day(rawValue: "2026-09-23")!, Day(rawValue: "2026-10-02")!) { try log(1_000, day.rawValue, h, &data) }
        let m = Milestones(data.habits[0], data: data, today: today)
        XCTAssertEqual(m.bestStreak, 10); XCTAssertEqual(m.currentStreak, 10); XCTAssertEqual(m.total, 10)
        XCTAssertEqual(m.nextStreak, 14); XCTAssertEqual(m.nextTotal, 25); XCTAssertEqual(m.earned, 4)
        XCTAssertEqual(m.totalReached[1]?.rawValue, "2026-09-23"); XCTAssertEqual(m.totalReached[10]?.rawValue, "2026-10-02")
    }
    func testRecapReminderFiresOnTheLastDayOfTheWeek() {
        var (data, _) = fixture(); let now = ISO8601DateFormatter().date(from: "2026-10-03T12:00:00Z")!, zone = TimeZone(secondsFromGMT: 0)!
        XCTAssertTrue(ReminderPlanner.plan(data, now: now, timeZone: zone).requests.isEmpty)
        data.settings.recapReminder = true
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let requests = ReminderPlanner.plan(data, now: now, timeZone: zone).requests
        XCTAssertEqual(requests.count, 1); XCTAssertEqual(requests[0].id, "buddy.\(ReminderPlanner.recapID).2026-10-04")
        XCTAssertEqual(calendar.component(.weekday, from: requests[0].fireDate), 1); XCTAssertEqual(calendar.component(.hour, from: requests[0].fireDate), 19)
        data.settings.weekStart = 1
        XCTAssertEqual(calendar.component(.weekday, from: ReminderPlanner.plan(data, now: now, timeZone: zone).requests[0].fireDate), 7)
    }
    func testSchemaOneSettingsDecodeWithNewDefaults() throws {
        var (data, _) = fixture();data.settings.theme = .dark;data.settings.showDescriptions=false
        var object=try JSONSerialization.jsonObject(with:DataValidation.encode(data)) as! [String:Any]
        var settings=object["settings"] as! [String:Any]
        for key in ["showMonthLabels","showWeekdayLabels","showCategoryIcons","showCategoryFilter","showLayoutSwitcher","compactNames","dragToReorder"]{settings.removeValue(forKey:key)}
        object["settings"]=settings
        let decoded=try DataValidation.decode(JSONSerialization.data(withJSONObject:object),today:today)
        XCTAssertEqual(decoded.habits,data.habits);XCTAssertEqual(decoded.settings.theme,.dark);XCTAssertFalse(decoded.settings.showDescriptions)
        XCTAssertTrue(decoded.settings.showLayoutSwitcher);XCTAssertTrue(decoded.settings.dragToReorder);XCTAssertTrue(decoded.settings.showMonthLabels)
    }
    func testStatisticsSummaryUsesHistoricalSuccessAndRecordedHours() throws {
        var (data,h)=fixture(tracking:.count,target:2_000)
        try log(2_000,"2026-10-01",h,&data);try log(1_000,"2026-10-02",h,&data);try log(2_000,"2026-10-03",h,&data)
        let key=Record.key(h.id,Day(rawValue:"2026-10-01")!);data.records[key]?.completionHour=7
        data.records[Record.key(h.id,today)]?.completionHour=nil
        let summary=StatisticsSummary(data:data,year:2026,today:today)
        XCTAssertEqual(summary.completions,2);XCTAssertEqual(summary.eligible,6);XCTAssertEqual(summary.monthly[9],2);XCTAssertEqual(summary.hourly[7],1)
        XCTAssertEqual(summary.currentStreak,1);XCTAssertEqual(summary.bestStreak,1)
        XCTAssertEqual(StatisticsSummary(data:data,habitIDs:[],year:2026,today:today).completions,0)
    }

    func testAppearanceAndOverviewSettingsRoundTrip() throws {
        var (data,_)=fixture();var appearance=CardAppearance();appearance.description=false;appearance.monthLabels=false;appearance.indicator=false
        data.habits[0].appearance=appearance;data.settings.compactNames=false;data.settings.dragToReorder=false;data.settings.showCategoryFilter=false
        XCTAssertEqual(try DataValidation.decode(DataValidation.encode(data),today:today),data)
    }

    func testAccentDefaultsToVioletAndRoundTrips() throws {
        var (data,_)=fixture();XCTAssertNil(data.settings.accent)
        XCTAssertFalse(String(decoding:try DataValidation.encode(data),as:UTF8.self).contains("accent"),"The default accent is not written")
        for code in ["teal","#1A2B3C"] { data.settings.accent=code;XCTAssertEqual(try DataValidation.decode(DataValidation.encode(data),today:today).settings.accent,code) }
        for code in ["","Teal","#12345","#12345G","#+12345","#1234567",String(repeating:"a",count:41)] { data.settings.accent=code;XCTAssertThrowsError(try DataValidation.validate(data,today:today),code) }
        XCTAssertEqual(AccentCode.hex("#8b8af8"),0x8B8AF8);XCTAssertNil(AccentCode.hex("teal"));XCTAssertEqual(AccentCode.code(0x0A0B0C),"#0A0B0C")
    }

    func testPortableRoundTripPreservesAllData() throws { var (data, h) = fixture(); data.settings.theme = .dark; try Engine.note("hello", habitID: h.id, day: today, data: &data, today: today); XCTAssertEqual(try DataValidation.decode(DataValidation.encode(data), today: today), data) }
    func testCorruptAndEmptyImportsRejected() { XCTAssertThrowsError(try DataValidation.decode(Data())); XCTAssertThrowsError(try DataValidation.decode(Data("{bad}".utf8))) }
    func testRepositoryAtomicTransactionAndFailedChange() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = BuddyRepository(directory: root), h = Habit(name: "Read")
        try repo.transaction { $0.habits.append(h) }
        XCTAssertThrowsError(try repo.transaction { $0.habits[0].name = "" })
        XCTAssertEqual(try repo.load().habits[0].name, "Read")
        XCTAssertFalse(try repo.backups().isEmpty)
    }
    func testBadImportLeavesOriginalIntact() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let repo = BuddyRepository(directory: root); try repo.transaction { $0.habits.append(Habit(name: "Original")) }
        XCTAssertThrowsError(try repo.restore(Data("{}".utf8))); XCTAssertEqual(try repo.load().habits.first?.name, "Original")
    }
    func testRestoreRecoverableAfterCorruptDatabase() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let repo = BuddyRepository(directory: root); try repo.transaction { $0.habits.append(Habit(name: "Safe")) }
        let backup = try repo.export(); try Data("broken".utf8).write(to: root.appendingPathComponent("habits-v1.json"))
        XCTAssertThrowsError(try repo.load()); try repo.restore(backup); XCTAssertEqual(try repo.load().habits[0].name, "Safe")
    }
    func testConcurrentRepositoriesDoNotLoseIncrements() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let repo = BuddyRepository(directory: root); var h = Habit(name: "Water"); h.goals[0].tracking = .count; try repo.transaction { $0.habits = [h] }
        let id = h.id, failures = LockedFailures()
        DispatchQueue.concurrentPerform(iterations: 30) { _ in do { try BuddyRepository(directory: root).transaction { try Engine.increment(habitID: id, day: Day(), data: &$0) } } catch { failures.add(error) } }
        XCTAssertEqual(failures.count, 0); XCTAssertEqual(try repo.load().record(id, Day()).amount, 30_000)
    }
    func testReminderSuppressionAndFairBudget() throws {
        var (data, h) = fixture(); var reminder = Reminder(); reminder.hour = 23; reminder.minute = 0; h.reminders = [reminder]; data.habits = [h]
        let now = ISO8601DateFormatter().date(from: "2026-10-03T12:00:00Z")!, zone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(ReminderPlanner.plan(data, now: now, timeZone: zone).requests.count, 7)
        try log(1_000, "2026-10-03", h, &data)
        XCTAssertEqual(ReminderPlanner.plan(data, now: now, timeZone: zone).requests.count, 6)
        let plan = ReminderPlanner.plan(data, now: now, timeZone: zone, budget: 2); XCTAssertEqual(plan.requests.count, 2); XCTAssertEqual(plan.omittedCount, 4)
    }
    func testReminderFollowsLocalClockAcrossDST() {
        var (data, h) = fixture(start: "2026-01-01"); var r = Reminder(); r.hour = 8; h.reminders = [r]; data.habits = [h]
        let zone = TimeZone(identifier: "America/New_York")!, now = ISO8601DateFormatter().date(from: "2026-03-07T12:00:00Z")!
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        for request in ReminderPlanner.plan(data, now: now, timeZone: zone).requests { XCTAssertEqual(calendar.component(.hour, from: request.fireDate), 8) }
    }
}
private final class LockedFailures: @unchecked Sendable {
    private let lock = NSLock(); private var values: [Error] = []
    var count: Int { lock.lock(); defer { lock.unlock() }; return values.count }
    func add(_ error: Error) { lock.lock(); defer { lock.unlock() }; values.append(error) }
}
