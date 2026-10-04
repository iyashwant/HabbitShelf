import Foundation

public enum HabitMode: String, Codable, CaseIterable, Sendable { case build, quit }
public enum Tracking: String, Codable, CaseIterable, Sendable { case yesNo, count, measure }
public enum Cadence: String, Codable, CaseIterable, Sendable { case none, daily, weekly, monthly }
public enum TapAction: String, Codable, CaseIterable, Sendable { case addOne, enterTotal }
public enum Theme: String, Codable, CaseIterable, Sendable { case system, light, dark }
public enum Layout: String, Codable, CaseIterable, Sendable { case cards, compact, month, streaks, list }
/// Widget sizes as on the home screen: small takes half a dashboard row, medium a full row, large a full row at double height.
public enum WidgetSize: String, Codable, CaseIterable, Sendable { case small, medium, large }
/// Dashboard and home-screen widget designs.
public enum DashboardKind: String, Codable, CaseIterable, Sendable {
    case streak, month, today, weeks, months, list, ring, stats, year, badge, checks, week, routine
    /// The sizes the design comes in; the first is its default.
    public var sizes: [WidgetSize] {
        switch self {
        case .streak, .ring, .badge: [.small]
        case .month: [.small, .large]
        case .today, .stats, .routine: [.small, .medium]
        case .weeks, .months, .week: [.medium]
        case .year: [.medium, .large]
        case .list: [.large, .medium]
        case .checks: [.medium, .small, .large]
        }
    }
    /// The today ring, today list, quick check and week summarize several habits.
    public var multiHabit: Bool { self == .today || self == .list || self == .checks || self == .week }
    /// Designs about one habit; the rest show several habits or a routine.
    public var needsHabit: Bool { !multiHabit && self != .routine }
}
public enum WidgetStyle: String, Codable, CaseIterable, Sendable { case automatic, light, dark, tinted }
public struct DashboardWidget: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var kind: DashboardKind
    /// The habit shown by a single-habit design.
    public var habitID: UUID?
    public var style: WidgetStyle = .automatic
    /// One of the design's sizes; nil (or a size the design lacks) uses its default.
    public var size: WidgetSize?
    /// The habits a multi-habit design shows, in habit order; nil shows every active habit.
    public var habitIDs: [UUID]?
    /// The routine shown by the routine design.
    public var routineID: UUID?
    /// A heading in place of a multi-habit design's default, such as "Today".
    public var title: String?
    /// A palette color in place of the habit's or routine's own.
    public var color: String?
    public init(kind: DashboardKind, habitID: UUID? = nil, style: WidgetStyle = .automatic, size: WidgetSize? = nil) { self.kind = kind; self.habitID = habitID; self.style = style; self.size = size }
    enum CodingKeys: String, CodingKey { case id, kind, habitID, style, size, habitIDs, routineID, title, color }
    /// Options were added within schema 1, so older dashboards decode with defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); kind = try c.decode(DashboardKind.self, forKey: .kind)
        habitID = try c.decodeIfPresent(UUID.self, forKey: .habitID); style = try c.decodeIfPresent(WidgetStyle.self, forKey: .style) ?? .automatic
        size = try c.decodeIfPresent(WidgetSize.self, forKey: .size); habitIDs = try c.decodeIfPresent([UUID].self, forKey: .habitIDs)
        routineID = try c.decodeIfPresent(UUID.self, forKey: .routineID); title = try c.decodeIfPresent(String.self, forKey: .title)
        color = try c.decodeIfPresent(String.self, forKey: .color)
    }
    public var resolvedSize: WidgetSize { size.flatMap { kind.sizes.contains($0) ? $0 : nil } ?? kind.sizes[0] }
    /// Medium and large widgets span the row.
    public var wide: Bool { resolvedSize != .small }
    /// The habits shown: one for a single-habit design, the chosen ones (or all) for a multi-habit design.
    public func habits(in data: BuddyData) -> [Habit] {
        if kind.needsHabit { return data.activeHabit(habitID).map { [$0] } ?? [] }
        guard kind.multiHabit else { return [] }
        guard let habitIDs else { return data.active }
        let chosen = Set(habitIDs)
        return data.active.filter { chosen.contains($0.id) }
    }
    /// Whether everything the widget shows still exists; widgets for archived or deleted habits and routines are hidden.
    public func visible(in data: BuddyData) -> Bool {
        if kind == .routine { return data.routines.contains { $0.id == routineID } }
        if kind.needsHabit { return !habits(in: data).isEmpty }
        return habitIDs == nil || !habits(in: data).isEmpty
    }
    /// The arrangement shown until the dashboard is first edited. IDs are stable so views keep their identity.
    public static func defaults(for habits: [Habit]) -> [DashboardWidget] {
        guard !habits.isEmpty else { return [] }
        let plan: [(DashboardKind, Int?, WidgetStyle, WidgetSize?)] = [
            (.weeks, 0, .dark, nil), (.today, nil, .automatic, nil), (.ring, 4, .tinted, nil), (.months, 3, .light, nil),
            (.streak, 2, .dark, nil), (.stats, 5, .light, nil), (.checks, nil, .automatic, nil), (.month, 1, .light, nil),
            (.badge, 6, .dark, nil), (.year, 7, .dark, nil), (.week, nil, .tinted, nil), (.list, nil, .automatic, nil)]
        return plan.enumerated().map { n, item in
            var widget = DashboardWidget(kind: item.0, habitID: item.1.map { habits[$0 % habits.count].id }, style: item.2, size: item.3)
            widget.id = UUID(uuidString: String(format: "00000000-0000-0000-0002-%012d", n))!
            return widget
        }
    }
}

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
    public var appearance: CardAppearance?
    public var goals: [Goal]
    /// Left out of every screen and widget until shown again, as while showing the app to someone.
    /// Unset (and not written) while the habit is shown, so older files decode unchanged.
    public var hidden: Bool?
    public var isHidden: Bool { hidden == true }
    public init(name: String, created: Day = Day()) {
        self.name = name; self.created = created; self.goals = [Goal(from: created)]
    }
    public func goal(on day: Day) -> Goal { goals.last(where: { $0.from <= day }) ?? goals[0] }
    public var currentGoal: Goal { goals.last! }
    public func available(on day: Day, today: Day) -> Bool {
        day >= created && day <= today && (archived == nil || day <= archived!) && !pauses.contains { day >= $0.from && day <= $0.through }
    }
    /// The earliest start date a habit may have.
    public static let earliestStart = Day(rawValue: "1970-01-01")!
    /// Days a user may log: tracked days plus any earlier past day. Recording something
    /// before `created` moves the start back to that day (see `Engine.setAmount`).
    public func loggable(on day: Day, today: Day) -> Bool {
        archived == nil && day >= Habit.earliestStart && (day < created || available(on: day, today: today))
    }
}
public struct Pause: Codable, Equatable, Sendable {
    public var from: Day
    public var through: Day
    public init(from: Day, through: Day) { self.from = from; self.through = through }
}
/// Habits checked off together, such as a morning routine.
public struct Routine: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var symbol = "lu:sunrise"
    public var color = "amber"
    public var habitIDs: [UUID] = []
    public init(name: String) { self.name = name }
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
    /// A missed daily-goal day the user chose to freeze: it neither adds to nor breaks the streak.
    public var frozen: Bool?
    public init(habitID: UUID, day: Day) { self.habitID = habitID; self.day = day }
    public var key: String { Self.key(habitID, day) }
    public static func key(_ id: UUID, _ day: Day) -> String { keyPrefix(id) + day.rawValue }
    /// The part of a key shared by one habit's records. Loops over many days build it once.
    public static func keyPrefix(_ id: UUID) -> String { id.uuidString + "|" }
}
public struct CardAppearance: Codable, Equatable, Sendable {
    public var description = true
    public var streak = true
    public var goal = true
    public var indicator = true
    public var monthLabels = true
    public var weekdayLabels = true
    public var categoryIcons = true
    public init() {}
}
/// New installs start dark with HabitKit's plain overview cards (no grid labels, streak or goal chips).
/// Decoding keeps the earlier defaults for keys missing from older backups.
public struct Settings: Codable, Equatable, Sendable {
    public var theme: Theme = .dark
    public var layout: Layout = .cards
    public var weekStart = 2
    public var recentDays = 5
    public var showToday = true
    public var notes = true
    public var haptics = true
    public var showDescriptions = true
    public var showStreak = false
    public var showGoal = false
    public var showCompletionIndicator = true
    public var showMonthLabels = false
    public var showWeekdayLabels = false
    public var showCategoryIcons = true
    public var showCategoryFilter = true
    public var showLayoutSwitcher = true
    public var compactNames = true
    public var dragToReorder = true
    public var onboarding = false
    public var checkIn: Reminder?
    public var checkInTitle = "A little progress today"
    public var checkInBody = "Make time for the habits that matter to you."
    /// Customized dashboard; nil shows `DashboardWidget.defaults` until the first edit.
    public var dashboard: [DashboardWidget]?
    /// Streak freezes each habit may use per calendar month; 0 turns freezing off.
    public var freezesPerMonth = 0
    /// A notification on the last day of each week when the weekly recap is ready.
    public var recapReminder = false
    /// The app accent (see `AccentCode`); nil keeps the default violet and is not written.
    public var accent: String?
    public init() {}
    enum CodingKeys: String, CodingKey { case theme, accent, layout, weekStart, recentDays, showToday, notes, haptics, showDescriptions, showStreak, showGoal, showCompletionIndicator, showMonthLabels, showWeekdayLabels, showCategoryIcons, showCategoryFilter, showLayoutSwitcher, compactNames, dragToReorder, onboarding, checkIn, checkInTitle, checkInBody, dashboard, freezesPerMonth, recapReminder }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = try c.decodeIfPresent(Theme.self, forKey: .theme) ?? .system
        accent = try c.decodeIfPresent(String.self, forKey: .accent)
        layout = try c.decodeIfPresent(Layout.self, forKey: .layout) ?? layout
        weekStart = try c.decodeIfPresent(Int.self, forKey: .weekStart) ?? weekStart
        recentDays = try c.decodeIfPresent(Int.self, forKey: .recentDays) ?? recentDays
        showToday = try c.decodeIfPresent(Bool.self, forKey: .showToday) ?? showToday
        notes = try c.decodeIfPresent(Bool.self, forKey: .notes) ?? notes
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? haptics
        showDescriptions = try c.decodeIfPresent(Bool.self, forKey: .showDescriptions) ?? showDescriptions
        showStreak = try c.decodeIfPresent(Bool.self, forKey: .showStreak) ?? true
        showGoal = try c.decodeIfPresent(Bool.self, forKey: .showGoal) ?? true
        showCompletionIndicator = try c.decodeIfPresent(Bool.self, forKey: .showCompletionIndicator) ?? showCompletionIndicator
        showMonthLabels = try c.decodeIfPresent(Bool.self, forKey: .showMonthLabels) ?? true
        showWeekdayLabels = try c.decodeIfPresent(Bool.self, forKey: .showWeekdayLabels) ?? true
        showCategoryIcons = try c.decodeIfPresent(Bool.self, forKey: .showCategoryIcons) ?? showCategoryIcons
        showCategoryFilter = try c.decodeIfPresent(Bool.self, forKey: .showCategoryFilter) ?? showCategoryFilter
        showLayoutSwitcher = try c.decodeIfPresent(Bool.self, forKey: .showLayoutSwitcher) ?? showLayoutSwitcher
        compactNames = try c.decodeIfPresent(Bool.self, forKey: .compactNames) ?? compactNames
        dragToReorder = try c.decodeIfPresent(Bool.self, forKey: .dragToReorder) ?? dragToReorder
        onboarding = try c.decodeIfPresent(Bool.self, forKey: .onboarding) ?? onboarding
        checkIn = try c.decodeIfPresent(Reminder.self, forKey: .checkIn)
        checkInTitle = try c.decodeIfPresent(String.self, forKey: .checkInTitle) ?? checkInTitle
        checkInBody = try c.decodeIfPresent(String.self, forKey: .checkInBody) ?? checkInBody
        dashboard = try c.decodeIfPresent([DashboardWidget].self, forKey: .dashboard)
        freezesPerMonth = try c.decodeIfPresent(Int.self, forKey: .freezesPerMonth) ?? freezesPerMonth
        recapReminder = try c.decodeIfPresent(Bool.self, forKey: .recapReminder) ?? recapReminder
    }
}
/// How the app accent is saved: a palette color name such as "teal", or a custom color as "#RRGGBB".
public enum AccentCode {
    /// The color of a "#RRGGBB" code; nil for a palette name or anything else.
    public static func hex(_ code: String) -> UInt32? {
        guard code.count == 7, code.first == "#", code.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(code.dropFirst(), radix: 16)
    }
    public static func code(_ hex: UInt32) -> String { String(format: "#%06X", hex & 0xFFFFFF) }
    /// A custom code, or a palette name of lowercase letters.
    public static func isValid(_ code: String) -> Bool {
        hex(code) != nil || ((1...40).contains(code.count) && code.unicodeScalars.allSatisfy { ("a"..."z").contains($0) })
    }
}
public struct BuddyData: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var habits: [Habit] = []
    public var records: [String: Record] = [:]
    public var categories: [Category] = []
    public var routines: [Routine] = []
    public var settings = Settings()
    public init() {}
    enum CodingKeys: String, CodingKey { case schemaVersion, habits, records, categories, routines, settings }
    /// Routines were added within schema 1, so older files decode with none.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        habits = try c.decode([Habit].self, forKey: .habits)
        records = try c.decode([String: Record].self, forKey: .records)
        categories = try c.decode([Category].self, forKey: .categories)
        routines = try c.decodeIfPresent([Routine].self, forKey: .routines) ?? []
        settings = try c.decode(Settings.self, forKey: .settings)
    }
    public var active: [Habit] { habits.filter { $0.archived == nil }.sorted { $0.order < $1.order } }
    /// One active habit by ID, without filtering and sorting every habit like `active`.
    public func activeHabit(_ id: UUID?) -> Habit? { habits.first { $0.id == id && $0.archived == nil } }
    /// The data as screens and widgets show it: hidden habits left out, and routines whose active habits are all
    /// hidden. Other routines and dashboard widgets keep their IDs, which no longer find a hidden habit. Hidden
    /// habits' days stay in `records`, where only their habit finds them; copying every record would cost each
    /// check-in milliseconds on a long history. Code that walks all records must skip habits not in `habits`.
    /// Writes always go to the full data.
    public var withoutHidden: BuddyData {
        guard habits.contains(where: \.isHidden) else { return self }
        var data = self
        data.habits.removeAll(where: \.isHidden)
        data.routines.removeAll { routine in
            let members = routine.habitIDs.compactMap(activeHabit)
            return !members.isEmpty && members.allSatisfy(\.isHidden)
        }
        return data
    }
    /// Puts the active habits in `ids` in that order. Active habits left out (such as hidden ones) keep their places.
    public mutating func reorder(_ ids: [UUID]) {
        var all = active.map(\.id)
        let moving = Set(ids)
        var next = ids.filter(Set(all).contains)[...]
        for i in all.indices where moving.contains(all[i]) { if let id = next.popFirst() { all[i] = id } }
        for (order, id) in all.enumerated() { if let i = habits.firstIndex(where: { $0.id == id }) { habits[i].order = order } }
    }
    public func record(_ id: UUID, _ day: Day) -> Record { records[Record.key(id, day)] ?? Record(habitID: id, day: day) }
}
public enum BuddyError: LocalizedError {
    case invalidAmount, invalidData(String), unavailable, future, locked, storage(String), notFreezable, noFreezesLeft
    public var errorDescription: String? {
        switch self {
        case .invalidAmount: return "Enter a nonnegative amount with up to three decimal places."
        case .invalidData(let reason): return "The data is invalid: \(reason)."
        case .unavailable: return "This habit is archived or no longer exists."
        case .future: return "You can log today and earlier days, but not future or paused days."
        case .locked: return "Progress from a previous habit mode is preserved. You can still edit its note."
        case .storage(let reason): return "Could not save your data: \(reason)"
        case .notFreezable: return "Only a missed past day of a daily goal can be frozen."
        case .noFreezesLeft: return "This habit has used all of this month's streak freezes."
        }
    }
}
