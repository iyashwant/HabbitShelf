import XCTest
@testable import BuddyCore

/// Checks for the speed work in docs/PERFORMANCE_AUDIT_2026-10-03.md: faster paths must give the same answers.
final class PerformanceTests: XCTestCase {
    let today = Day(rawValue: "2026-10-03")!

    func testValidationIndexesHabitsAndStillRejectsBadRecords() throws {
        var data = BuddyData(), habits: [Habit] = []
        for n in 0..<3 { var h = Habit(name: "H\(n)", created: today.adding(-30)); h.order = n; habits.append(h) }
        data.habits = habits
        for h in habits { for day in Day.range(today.adding(-20), today) { try Engine.setAmount(1_000, habitID: h.id, day: day, data: &data, today: today) } }
        XCTAssertNoThrow(try DataValidation.validate(data, today: today))
        // A record filed under another habit's key, a key for another day, and a record for a missing habit.
        var wrongHabit = data, record = data.record(habits[0].id, today)
        wrongHabit.records.removeValue(forKey: record.key); wrongHabit.records[Record.key(habits[1].id, today)] = record
        XCTAssertThrowsError(try DataValidation.validate(wrongHabit, today: today))
        var wrongDay = data
        wrongDay.records.removeValue(forKey: record.key); wrongDay.records[Record.key(habits[0].id, today.adding(-25))] = record
        XCTAssertThrowsError(try DataValidation.validate(wrongDay, today: today))
        var orphan = data; orphan.records[Record.key(UUID(), today)] = Record(habitID: UUID(), day: today)
        XCTAssertThrowsError(try DataValidation.validate(orphan, today: today))
    }

    func testNoteLimitCountsCharactersNotBytes() throws {
        var data = BuddyData(), h = Habit(name: "Journal", created: today); h.order = 0; data.habits = [h]
        var record = Record(habitID: h.id, day: today)
        // 15,000 emoji are 60,000 UTF-8 bytes but only 15,000 characters.
        record.note = String(repeating: "🙂", count: 15_000); data.records[record.key] = record
        XCTAssertNoThrow(try DataValidation.validate(data, today: today))
        record.note = String(repeating: "a", count: 20_001); data.records[record.key] = record
        XCTAssertThrowsError(try DataValidation.validate(data, today: today))
    }

    func testStoreIsCompactAndExportIsFormatted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let repo = BuddyRepository(directory: root)
        try repo.transaction { $0.habits.append(Habit(name: "Read")) }
        let stored = try Data(contentsOf: root.appendingPathComponent("habits-v1.json")), exported = try repo.export()
        XCTAssertFalse(stored.contains(UInt8(ascii: "\n")), "The store skips formatting")
        XCTAssertTrue(exported.contains(UInt8(ascii: "\n")), "Exports stay readable")
        XCTAssertEqual(try DataValidation.decode(stored), try DataValidation.decode(exported))
    }

    func testOversizedCommitLeavesTheStoreReadable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
        let repo = BuddyRepository(directory: root, maximumBytes: 4_000), h = Habit(name: "Read")
        try repo.transaction { $0.habits.append(h) }
        let before = try Data(contentsOf: root.appendingPathComponent("habits-v1.json"))
        XCTAssertThrowsError(try repo.transaction { try Engine.note(String(repeating: "x", count: 5_000), habitID: h.id, day: Day(), data: &$0) })
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("habits-v1.json")), before)
        XCTAssertEqual(try BuddyRepository(directory: root).load().habits.map(\.name), ["Read"])
    }

    func testOversizedImportIsRejectedBeforeReading() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"); defer { try? FileManager.default.removeItem(at: file) }
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file); try handle.truncate(atOffset: UInt64(DataValidation.maximumBytes) + 1); try handle.close()
        XCTAssertThrowsError(try DataValidation.read(file))
    }

    func testMonthNumberMatchesCalendarMonths() {
        XCTAssertEqual(Day(rawValue: "2026-01-15")!.monthNumber - Day(rawValue: "2025-12-31")!.monthNumber, 1)
        XCTAssertEqual(Day(rawValue: "2026-10-03")!.monthNumber % 12, 9)
        XCTAssertEqual(Day(rawValue: "1970-01-01")!.monthNumber, 1970 * 12)
    }

    func testLapsePairsHaveDistinctIdentities() {
        let a = UUID(), b = UUID(), c = UUID()
        let pairs = [InsightsSummary.LapsePair(first: a, second: b, together: 3, either: 4), InsightsSummary.LapsePair(first: a, second: c, together: 3, either: 4)]
        XCTAssertEqual(Set(pairs.map(\.id)).count, 2)
    }

    func testInsightsWithoutPairsMatchTheFullSummary() throws {
        var data = BuddyData()
        for n in 0..<3 {
            var h = Habit(name: "H\(n)", created: Day(rawValue: "2026-06-01")!); h.order = n; h.goals[0].cadence = .daily; data.habits.append(h)
            for day in Day.range(h.created, today) where day.rawValue.hasSuffix(n == 0 ? "3" : "7") == false { try Engine.setAmount(1_000, habitID: h.id, day: day, data: &data, today: today) }
        }
        let from = Day(rawValue: "2026-07-01")!
        let full = InsightsSummary(data: data, from: from, today: today), light = InsightsSummary(data: data, from: from, today: today, includePairs: false)
        XCTAssertTrue(light.pairs.isEmpty)
        XCTAssertEqual(InsightsSummary.lapsePairs(data: data, from: from, today: today, maxPairs: 100), InsightsSummary(data: data, from: from, today: today, maxPairs: 100).pairs)
        XCTAssertFalse(full.pairs.isEmpty, "The fixture's habits lapse on shared days")
        XCTAssertEqual(light.weekdays, full.weekdays); XCTAssertEqual(light.months, full.months); XCTAssertEqual(light.total, full.total); XCTAssertEqual(light.hours, full.hours)
    }

    func testStatisticsKeptDaysMatchAnyKeptBuildHabit() throws {
        var data = BuddyData(), ids: [UUID] = []
        for n in 0..<2 { var h = Habit(name: "H\(n)", created: Day(rawValue: "2026-09-01")!); h.order = n; data.habits.append(h); ids.append(h.id) }
        try Engine.setAmount(1_000, habitID: ids[0], day: Day(rawValue: "2026-09-02")!, data: &data, today: today)
        try Engine.setAmount(1_000, habitID: ids[1], day: Day(rawValue: "2026-09-03")!, data: &data, today: today)
        XCTAssertEqual(StatisticsSummary(data: data, year: 2026, today: today).keptDays.map(\.rawValue).sorted(), ["2026-09-02", "2026-09-03"])
        XCTAssertEqual(StatisticsSummary(data: data, habitIDs: [ids[1]], year: 2026, today: today).keptDays.map(\.rawValue), ["2026-09-03"])
    }

    /// Baselines for fixed workloads, so a regression shows in the measured times (no time is asserted).
    func testMeasureValidatingAHundredThousandRecords() {
        var data = BuddyData()
        for n in 0..<50 { var h = Habit(name: "H\(n)", created: today.adding(-1_999)); h.order = n; data.habits.append(h) }
        for h in data.habits { for offset in 0..<2_000 { var r = Record(habitID: h.id, day: today.adding(-offset)); r.amount = 1_000; data.records[r.key] = r } }
        measure { do { try DataValidation.validate(data, today: today) } catch { XCTFail("\(error)") } }
    }
    func testMeasureTenYearHistories() {
        var data = BuddyData()
        for n in 0..<10 { var h = Habit(name: "H\(n)", created: today.adding(-3_652)); h.order = n; h.goals[0].cadence = .daily; data.habits.append(h) }
        for h in data.habits { for offset in stride(from: 0, to: 3_652, by: 2) { var r = Record(habitID: h.id, day: today.adding(-offset)); r.amount = 1_000; data.records[r.key] = r } }
        measure { for h in data.habits { XCTAssertGreaterThan(Engine.history(h, data: data, today: today).total, 0) } }
    }

    /// The one-pass history must agree with the earlier day-by-day implementation on varied histories.
    func testHistoryMatchesReferenceOnRandomHabits() throws {
        var generator = SeededGenerator(seed: 27)
        for trial in 0..<300 {
            let (data, habit) = randomHabit(&generator)
            for weekStart in [1, 2] {
                let expected = Self.referenceStats(habit, data: data, today: today, weekStart: weekStart)
                let history = Engine.history(habit, data: data, today: today, weekStart: weekStart)
                XCTAssertEqual(history.stats, expected, "trial \(trial), week start \(weekStart)")
                let total = Day.range(habit.created, min(today, habit.archived ?? today)).filter { Engine.progress(habit, day: $0, data: data, today: today).success }.count
                XCTAssertEqual(history.total, total, "trial \(trial)")
            }
        }
    }

    private func randomHabit(_ g: inout SeededGenerator) -> (BuddyData, Habit) {
        var data = BuddyData(); data.settings.freezesPerMonth = 3
        let start = today.adding(-Int.random(in: 0...200, using: &g))
        var habit = Habit(name: "Random", created: start)
        var goals: [Goal] = [], day = start
        while day <= today && goals.count < 4 {
            var goal = Goal(from: day)
            goal.mode = Int.random(in: 0..<5, using: &g) == 0 ? .quit : .build
            goal.cadence = goal.mode == .quit ? .daily : [.none, .daily, .weekly, .monthly][Int.random(in: 0..<4, using: &g)]
            goal.days = goal.cadence == .weekly ? Int.random(in: 1...7, using: &g) : goal.cadence == .monthly ? Int.random(in: 1...31, using: &g) : 1
            if Bool.random(using: &g) { goal.tracking = .count; goal.target = Int64(Int.random(in: 1...3, using: &g)) * 1_000 }
            goals.append(goal)
            day = day.adding(Int.random(in: 1...90, using: &g))
        }
        habit.goals = goals
        if start < today.adding(-10) && Bool.random(using: &g) {
            let from = start.adding(Int.random(in: 1...max(1, start.distance(to: today) - 5), using: &g))
            if from < today { habit.pauses = [Pause(from: from, through: min(today.adding(-1), from.adding(Int.random(in: 0...6, using: &g))))] }
        }
        if Int.random(in: 0..<6, using: &g) == 0 { habit.archived = today.adding(-Int.random(in: 0...start.distance(to: today), using: &g)) }
        data.habits = [habit]
        for d in Day.range(start, today) where Int.random(in: 0..<3, using: &g) > 0 {
            var record = Record(habitID: habit.id, day: d)
            record.amount = Int64(Int.random(in: 0...3, using: &g)) * 1_000
            if record.amount == 0 && Int.random(in: 0..<8, using: &g) == 0 { record.frozen = true }
            data.records[record.key] = record
        }
        return (data, habit)
    }

    /// The streak and rate rules as written before the one-pass rewrite.
    static func referenceStats(_ habit: Habit, data: BuddyData, today: Day, weekStart: Int?) -> HabitStats {
        func progress(_ day: Day) -> BuddyCore.Progress { Engine.progress(habit, day: day, data: data, today: today) }
        func frozen(_ day: Day) -> Bool { data.records[Record.key(habit.id, day)]?.frozen == true }
        let end = min(today, habit.archived ?? today)
        guard habit.created <= end else { return HabitStats() }
        var result = HabitStats()
        for day in Day.range(habit.created, end) where habit.goal(on: day).mode == .build && habit.available(on: day, today: today) {
            let success = progress(day).success
            if day < today || success { result.eligibleDays += 1 }
            if success { result.completions += 1 }
        }
        var run = 0, best = 0
        for (index, rule) in habit.goals.enumerated() {
            let next = index + 1 < habit.goals.count ? habit.goals[index + 1].from.adding(-1) : end
            let segmentEnd = min(end, next)
            guard rule.from <= segmentEnd else { continue }
            if index > 0, rule.cadence != habit.goals[index - 1].cadence || rule.mode != habit.goals[index - 1].mode { run = 0 }
            if rule.cadence == .none { run = 0; continue }
            if rule.cadence == .daily || rule.mode == .quit {
                for day in Day.range(rule.from, segmentEnd) {
                    if progress(day).success { run += 1 } else if day < today && !frozen(day) { run = 0 }
                    best = max(best, run)
                }
            } else {
                var cursor = rule.from
                while cursor <= segmentEnd {
                    let periodEnd = rule.cadence == .weekly ? cursor.startOfWeek(weekStart ?? data.settings.weekStart).adding(6) : cursor.endOfMonth
                    let closedEnd = min(periodEnd, next), visibleEnd = min(segmentEnd, closedEnd)
                    let successes = Day.range(cursor, visibleEnd).filter { progress($0).success }.count
                    let target = min(rule.days, cursor.distance(to: closedEnd) + 1)
                    if successes >= target { run += successes; best = max(best, run) }
                    else if closedEnd < today || successes + today.distance(to: closedEnd) + (progress(today).success ? 0 : 1) < target { run = 0 }
                    else { best = max(best, run + successes); run += successes }
                    cursor = closedEnd.adding(1)
                }
            }
        }
        result.currentStreak = run; result.bestStreak = best
        return result
    }
}

/// A small deterministic generator, so a failing trial can be reproduced.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
