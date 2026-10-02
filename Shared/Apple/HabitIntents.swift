import AppIntents
import Foundation
import WidgetKit

struct HabitEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Habit"
    static var defaultQuery = HabitQuery()
    var id: UUID
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    init(_ habit: Habit) { id = habit.id; name = habit.name }
}
struct HabitQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [HabitEntity] { try AppEnvironment.repository.load().active.filter { identifiers.contains($0.id) }.map(HabitEntity.init) }
    func suggestedEntities() async throws -> [HabitEntity] { try AppEnvironment.repository.load().active.map(HabitEntity.init) }
}
struct ChooseHabitIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Habit"
    static var description = IntentDescription("Choose the habit displayed in this widget.")
    @Parameter(title: "Habit") var habit: HabitEntity?
}
enum IntentWrite {
    static func run(_ change: (inout BuddyData) throws -> Void) async throws {
        guard AppEnvironment.hasSharedContainer else { throw BuddyError.storage("configure the App Group for the app and widget targets in Xcode") }
        let data = try AppEnvironment.repository.transaction(change)
        await AppEnvironment.changed(data)
    }
    static func day(_ date: Date?) -> Day { Day(date ?? Date()) }
}
struct CompleteHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Habit"
    static var description = IntentDescription("Complete today. An already saved amount above the goal is kept.")
    @Parameter(title: "Habit") var habit: HabitEntity
    func perform() async throws -> some IntentResult { try await IntentWrite.run { try Engine.complete(habit.id, day: Day(), data: &$0) }; return .result() }
}
struct ClearHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Clear Habit"
    static var description = IntentDescription("Clear today's progress and preserve its note.")
    @Parameter(title: "Habit") var habit: HabitEntity
    func perform() async throws -> some IntentResult { try await IntentWrite.run { try Engine.setAmount(0, habitID: habit.id, day: Day(), data: &$0) }; return .result() }
}
struct IncrementHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Increment Habit"
    @Parameter(title: "Habit") var habit: HabitEntity
    func perform() async throws -> some IntentResult { try await IntentWrite.run { try Engine.increment(habitID: habit.id, day: Day(), data: &$0) }; return .result() }
}
struct LogAmountIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Habit Amount"
    @Parameter(title: "Habit") var habit: HabitEntity
    @Parameter(title: "Amount", description: "A nonnegative number with up to three decimal places.") var amount: String
    @Parameter(title: "Date") var date: Date?
    @Parameter(title: "Add to existing total", default: false) var add: Bool
    func perform() async throws -> some IntentResult {
        let value = try Amount.parse(amount), day = IntentWrite.day(date)
        try await IntentWrite.run { if add { try Engine.increment(value, habitID: habit.id, day: day, data: &$0) } else { try Engine.setAmount(value, habitID: habit.id, day: day, data: &$0) } }
        return .result()
    }
}
struct LogNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Habit Note"
    @Parameter(title: "Habit") var habit: HabitEntity
    @Parameter(title: "Note") var note: String
    @Parameter(title: "Date") var date: Date?
    @Parameter(title: "Append", default: false) var append: Bool
    func perform() async throws -> some IntentResult { try await IntentWrite.run { try Engine.note(note, append: append, habitID: habit.id, day: IntentWrite.day(date), data: &$0) }; return .result() }
}
struct GetHabitProgressIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Habit Progress"
    static var description = IntentDescription("Return a JSON object with amount, goal, remaining, unit, note, and success for a date.")
    @Parameter(title: "Habit") var habit: HabitEntity
    @Parameter(title: "Date") var date: Date?
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let data = try AppEnvironment.repository.load(), day = IntentWrite.day(date)
        guard let h = data.active.first(where: { $0.id == habit.id }) else { throw BuddyError.unavailable }
        guard h.available(on: day, today: Day()) else { throw BuddyError.future }
        let p = Engine.progress(h, day: day, data: data), g = h.goal(on: day)
        let object: [String: Any] = ["day": day.rawValue, "amount": Amount.text(p.amount), "goal": Amount.text(g.target), "remaining": Amount.text(max(0, g.target - p.amount)), "unit": g.unit, "note": data.record(h.id, day).note, "success": p.success, "mode": g.mode.rawValue]
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return .result(value: String(decoding: bytes, as: UTF8.self))
    }
}
struct OpenHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Habit"
    static var openAppWhenRun = true
    @Parameter(title: "Habit") var habit: HabitEntity
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "habitbuddy://\(habit.id.uuidString)")!))
    }
}
struct HabitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CompleteHabitIntent(), phrases: ["Complete a habit in \(.applicationName)"], shortTitle: "Complete Habit", systemImageName: "checkmark")
        AppShortcut(intent: ClearHabitIntent(), phrases: ["Clear a habit in \(.applicationName)"], shortTitle: "Clear Habit", systemImageName: "eraser")
        AppShortcut(intent: IncrementHabitIntent(), phrases: ["Add progress in \(.applicationName)"], shortTitle: "Increment Habit", systemImageName: "plus")
        AppShortcut(intent: LogAmountIntent(), phrases: ["Log an amount in \(.applicationName)"], shortTitle: "Log Amount", systemImageName: "number")
        AppShortcut(intent: LogNoteIntent(), phrases: ["Add a note in \(.applicationName)"], shortTitle: "Log Note", systemImageName: "note.text")
        AppShortcut(intent: GetHabitProgressIntent(), phrases: ["Get habit progress in \(.applicationName)"], shortTitle: "Get Progress", systemImageName: "chart.bar")
        AppShortcut(intent: OpenHabitIntent(), phrases: ["Open a habit in \(.applicationName)"], shortTitle: "Open Habit", systemImageName: "square.grid.3x3")
    }
}

/// Single interaction intent reused by all widget buttons. Each invocation commits once under a file lock.
struct WidgetLogIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Habit Progress"
    @Parameter(title: "Habit ID") var habitID: String
    @Parameter(title: "Day") var dayKey: String
    init() {}
    init(_ id: UUID, day: Day = Day()) { habitID = id.uuidString; dayKey = day.rawValue }
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: habitID), let day = Day(rawValue: dayKey) else { throw BuddyError.unavailable }
        try await IntentWrite.run { data in
            guard let h = data.active.first(where: { $0.id == id }) else { throw BuddyError.unavailable }
            let g = h.goal(on: day), old = data.record(id, day).amount
            if g.tracking == .yesNo { try Engine.setAmount(old == 0 ? 1_000 : 0, habitID: id, day: day, data: &data) }
            else if g.mode == .build && old < g.target { try Engine.increment(habitID: id, day: day, data: &data) }
            else { throw BuddyError.storage("open the app to edit a numeric total that is already at its goal or a quit amount") }
        }
        return .result()
    }
}
