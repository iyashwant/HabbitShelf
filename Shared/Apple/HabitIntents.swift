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
    @Parameter(title: "Theme", default: .system) var theme: WidgetAppearance
}
enum WidgetAppearance: String, AppEnum {
    case system,light,dark,tinted
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Widget Theme"
    static var caseDisplayRepresentations: [Self:DisplayRepresentation] = [.system:"System",.light:"Light",.dark:"Dark",.tinted:"Tinted"]
    var style: WidgetStyle { switch self { case .system: .automatic; case .light: .light; case .dark: .dark; case .tinted: .tinted } }
}
struct ChooseRoutineWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Routine"
    static var description = IntentDescription("Choose the routine shown in this widget.")
    @Parameter(title: "Routine") var routine: RoutineEntity?
    @Parameter(title: "Theme", default: .system) var theme: WidgetAppearance
}
struct ChooseCompactHabitsIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Habits"
    @Parameter(title: "Habits") var habits: [HabitEntity]?
    @Parameter(title: "Theme", default: .system) var theme: WidgetAppearance
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

struct RoutineEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Routine"
    static var defaultQuery = RoutineQuery()
    var id: UUID
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    init(_ routine: Routine) { id = routine.id; name = routine.name }
}
struct RoutineQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [RoutineEntity] { try AppEnvironment.repository.load().routines.filter { identifiers.contains($0.id) }.map(RoutineEntity.init) }
    func suggestedEntities() async throws -> [RoutineEntity] { try AppEnvironment.repository.load().routines.map(RoutineEntity.init) }
}
struct CompleteRoutineIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Routine"
    static var description = IntentDescription("Complete every open build habit in a routine for today. Quit habits are left alone.")
    @Parameter(title: "Routine") var routine: RoutineEntity?
    init() {}
    init(_ routine: RoutineEntity?) { self.routine = routine }
    func perform() async throws -> some IntentResult {
        guard let id = routine?.id else { throw BuddyError.unavailable }
        try await IntentWrite.run { try Engine.completeRoutine(id, day: Day(), data: &$0) }
        return .result()
    }
}
/// Control Center, Lock Screen and Action button logging. Yes/no habits toggle; counts add one until the goal.
struct ControlLogIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Habit"
    static var description = IntentDescription("Check off a yes/no habit, or add one to a count that hasn't reached its goal.")
    @Parameter(title: "Habit") var habit: HabitEntity?
    init() {}
    init(_ habit: HabitEntity?) { self.habit = habit }
    func perform() async throws -> some IntentResult {
        guard let id = habit?.id else { throw BuddyError.unavailable }
        try await IntentWrite.run { data in
            guard let h = data.active.first(where: { $0.id == id }) else { throw BuddyError.unavailable }
            let day = Day(), g = h.goal(on: day), old = data.record(id, day).amount
            if g.tracking == .yesNo { try Engine.setAmount(old == 0 ? 1_000 : 0, habitID: id, day: day, data: &data) }
            else if g.mode == .build && old < g.target { try Engine.increment(habitID: id, day: day, data: &data) }
        }
        return .result()
    }
}
struct ChooseControlHabitIntent: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Habit"
    @Parameter(title: "Habit") var habit: HabitEntity?
    init() {}
}
struct ChooseControlRoutineIntent: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Routine"
    @Parameter(title: "Routine") var routine: RoutineEntity?
    init() {}
}
/// Lock Screen widgets have no theme, so they take only the habit.
struct ChooseLockHabitIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Habit"
    static var description = IntentDescription("Choose the habit shown on the Lock Screen.")
    @Parameter(title: "Habit") var habit: HabitEntity?
}
struct ChooseLockHabitsIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Habits"
    static var description = IntentDescription("Choose the habits counted today, or leave empty for all.")
    @Parameter(title: "Habits") var habits: [HabitEntity]?
}
/// Opens the app's timer, for the Control Center control.
struct OpenTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Habit Timer"
    static var openAppWhenRun = true
    init() {}
    func perform() async throws -> some IntentResult & OpensIntent { .result(opensIntent: OpenURLIntent(URL(string: "habitbuddy://timer")!)) }
}
extension HabitEntity { init(id: UUID, name: String) { self.id = id; self.name = name } }
