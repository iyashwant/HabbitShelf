import Foundation

public enum HabitMode: String, Codable, CaseIterable, Sendable { case build, quit }
public enum Tracking: String, Codable, CaseIterable, Sendable { case yesNo, count, measure }
public enum Cadence: String, Codable, CaseIterable, Sendable { case none, daily, weekly, monthly }
public enum TapAction: String, Codable, CaseIterable, Sendable { case addOne, enterTotal }
public enum Theme: String, Codable, CaseIterable, Sendable { case system, light, dark }
public enum Layout: String, Codable, CaseIterable, Sendable { case cards, compact, month }

public struct Goal: Codable, Equatable, Sendable {
    public var from: Day
    public var mode: HabitMode = .build
    public var tracking: Tracking = .yesNo
    public var target: Int64 = 1_000
    public var cadence: Cadence = .none
    public var days: Int = 1
    public var unit: String = ""
    public var tap: TapAction = .addOne
    public init(from: Day = Day()) { self.from = from }
}
public struct Reminder: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var hour = 20
    public var minute = 0
    public var weekdays = Array(1...7)
    public var enabled = true
    public init() {}
}
public struct Habit: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var detail = ""
    public var symbol = "leaf.fill"
    public var color = "mint"
    public var created: Day
    public var archived: Day?
    public var pauses: [Pause] = []
    public var order = 0
    public var categories: [UUID] = []
    public var reminders: [Reminder] = []
    public var goals: [Goal]
    public init(name: String, created: Day = Day()) {
        self.name = name; self.created = created; self.goals = [Goal(from: created)]
    }
    public func goal(on day: Day) -> Goal { goals.last(where: { $0.from <= day }) ?? goals[0] }
    public var currentGoal: Goal { goals.last! }
    public func available(on day: Day, today: Day) -> Bool {
        day >= created && day <= today && (archived == nil || day <= archived!) && !pauses.contains { day >= $0.from && day <= $0.through }
    }
}
public struct Pause: Codable, Equatable, Sendable {
    public var from: Day
    public var through: Day
    public init(from: Day, through: Day) { self.from = from; self.through = through }
}
public struct Category: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var symbol = "folder.fill"
    public init(name: String) { self.name = name }
}
public struct Record: Codable, Equatable, Sendable {
    public var habitID: UUID
    public var day: Day
    public var amount: Int64 = 0
    public var note = ""
    public var timeZone = TimeZone.current.identifier
    public var updated = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    public var completedAt: Date?
    public var completionHour: Int?
    public init(habitID: UUID, day: Day) { self.habitID = habitID; self.day = day }
    public var key: String { Self.key(habitID, day) }
    public static func key(_ id: UUID, _ day: Day) -> String { "\(id.uuidString)|\(day.rawValue)" }
}
public struct Settings: Codable, Equatable, Sendable {
    public var theme: Theme = .system
    public var layout: Layout = .cards
    public var weekStart = 2
    public var recentDays = 5
    public var showToday = true
    public var notes = true
    public var haptics = true
    public var showDescriptions = true
    public var showStreak = true
    public var showGoal = true
    public var showCompletionIndicator = true
    public var onboarding = false
    public var checkIn: Reminder?
    public var checkInTitle = "A little progress today"
    public var checkInBody = "Make time for the habits that matter to you."
    public init() {}
}
public struct BuddyData: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var habits: [Habit] = []
    public var records: [String: Record] = [:]
    public var categories: [Category] = []
    public var settings = Settings()
    public init() {}
    public var active: [Habit] { habits.filter { $0.archived == nil }.sorted { $0.order < $1.order } }
    public func record(_ id: UUID, _ day: Day) -> Record { records[Record.key(id, day)] ?? Record(habitID: id, day: day) }
}
public enum BuddyError: LocalizedError {
    case invalidAmount, invalidData(String), unavailable, future, locked, storage(String)
    public var errorDescription: String? {
        switch self {
        case .invalidAmount: return "Enter a nonnegative amount with up to three decimal places."
        case .invalidData(let reason): return "The data is invalid: \(reason)."
        case .unavailable: return "This habit is archived or no longer exists."
        case .future: return "You can only log dates from the habit’s start through today."
        case .locked: return "Progress from a previous habit mode is preserved. You can still edit its note."
        case .storage(let reason): return "Could not save your data: \(reason)"
        }
    }
}
