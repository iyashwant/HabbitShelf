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
    func testFutureAndPreStartRejected() { var (data, h) = fixture(); XCTAssertThrowsError(try log(1_000, "2026-10-04", h, &data)); XCTAssertThrowsError(try log(1_000, "2026-09-27", h, &data)) }
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
