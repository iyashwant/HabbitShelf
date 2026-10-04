import Foundation
import WidgetKit
import UserNotifications

enum AppEnvironment {
    /// One repository per process, so its decoded snapshot is reused between widget, control and Shortcut requests.
    /// Every load and transaction still re-reads the file under the lock, so writes from other processes are seen.
    static let repository: BuddyRepository = {
        #if DEBUG
        let environment=ProcessInfo.processInfo.environment
        // Each fixture gets its own store, so a fixture pinned to another date can't invalidate it.
        if environment["BUDDY_VISUAL_SCREEN"] != nil { return BuddyRepository(directory:FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("VisualAudit"+(environment["BUDDY_VISUAL_FIXTURE"].map{"-"+$0} ?? ""))) }
        #endif
        guard let root = sharedContainer else {
            // Never silently split app and widget into unrelated databases.
            return BuddyRepository(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HabitBuddy"))
        }
        return BuddyRepository(directory: root.appendingPathComponent("HabitBuddy"))
    }()
    private static let sharedContainer: URL? = {
        let group = Bundle.main.object(forInfoDictionaryKey: "BuddyAppGroup") as? String ?? "group.com.iyashwant.habbitbuddy"
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }()
    static var hasSharedContainer: Bool { sharedContainer != nil }
    /// Refreshes what a saved change affects outside the app.
    static func changed(_ data: BuddyData, scope: SyncScope = .all) async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BUDDY_VISUAL_SCREEN"] != nil{return}
        #endif
        if scope.contains(.widgets) {
            WidgetCenter.shared.reloadAllTimelines()
            ControlCenter.shared.reloadAllControls()
        }
        if scope.contains(.reminders) { await ReminderCoordinator.shared.reconcile(data) }
    }
}

/// What a change affects outside the app: widget timelines and controls, and scheduled reminders.
struct SyncScope: OptionSet, Sendable {
    let rawValue: Int
    static let widgets = SyncScope(rawValue: 1), reminders = SyncScope(rawValue: 2)
    static let all: SyncScope = [.widgets, .reminders]
    init(rawValue: Int) { self.rawValue = rawValue }
    /// Collections a change didn't touch still share storage with the old snapshot, so comparing them is immediate.
    /// App-only settings, such as the theme, layout, card options and dashboard, affect neither. The accent tints
    /// widgets that show several habits.
    init(from old: BuddyData, to new: BuddyData) {
        let sameHabits = old.habits == new.habits && old.routines == new.routines
        if old.settings == new.settings {
            // Records are compared only after categories are known to have changed, i.e. not on a check-in.
            self = sameHabits && old.categories != new.categories && old.records == new.records ? [] : .all
            return
        }
        guard sameHabits && old.records == new.records else { self = .all; return }
        let a = old.settings, b = new.settings
        var scope: SyncScope = []
        if a.weekStart != b.weekStart || a.notes != b.notes || a.accent != b.accent { scope.insert(.widgets) }
        if a.weekStart != b.weekStart || a.checkIn != b.checkIn || a.checkInTitle != b.checkInTitle || a.checkInBody != b.checkInBody || a.recapReminder != b.recapReminder { scope.insert(.reminders) }
        self = scope
    }
}

/// Schedules reminders for this process one run at a time. Requests that arrive during a run collapse into one
/// follow-up with the newest data, so an older snapshot never replaces a newer schedule. Callers return once
/// their data, or newer data, has been applied.
actor ReminderCoordinator {
    static let shared = ReminderCoordinator()
    private var latest: BuddyData?
    private var requested = 0, applied = 0, running = false
    private var waiting: [(ticket: Int, resume: CheckedContinuation<Void, Never>)] = []
    func reconcile(_ data: BuddyData) async {
        requested += 1
        let ticket = requested
        latest = data
        guard !running else { await withCheckedContinuation { waiting.append((ticket, $0)) }; return }
        running = true
        while let next = latest {
            let generation = requested
            latest = nil
            await NotificationService.apply(next)
            applied = generation
            let done = waiting.filter { $0.ticket <= applied }
            waiting.removeAll { $0.ticket <= applied }
            for waiter in done { waiter.resume.resume() }
        }
        running = false
    }
}

enum NotificationService {
    static func request() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
    static func reconcile(_ data: BuddyData) async { await ReminderCoordinator.shared.reconcile(data) }
    /// Replaces only the `buddy.` requests whose content or time changed, and adds the missing ones.
    fileprivate static func apply(_ data: BuddyData) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let coverage = ReminderPlanner.plan(data)
        let wanted = Dictionary(coverage.requests.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let scheduled = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("buddy.") }
        var current = Set<String>(), stale: [String] = []
        for request in scheduled {
            if let plan = wanted[request.identifier], matches(request, plan) { current.insert(request.identifier) } else { stale.append(request.identifier) }
        }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        for request in coverage.requests where !current.contains(request.id) {
            current.insert(request.id)
            let content = UNMutableNotificationContent()
            content.title = request.title; content.body = request.body; content.sound = .default
            if let id = request.habitID { content.userInfo = ["habitID": id.uuidString] }
            let trigger = UNCalendarNotificationTrigger(dateMatching: components(request.fireDate), repeats: false)
            do { try await center.add(UNNotificationRequest(identifier: request.id, content: content, trigger: trigger)) }
            catch { NSLog("Habit Buddy: notification scheduling failed: %@", error.localizedDescription) }
        }
    }
    private static func components(_ date: Date) -> DateComponents { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date) }
    private static func matches(_ request: UNNotificationRequest, _ plan: PlannedReminder) -> Bool {
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger, !trigger.repeats else { return false }
        return request.content.title == plan.title && request.content.body == plan.body
            && request.content.userInfo["habitID"] as? String == plan.habitID?.uuidString
            && trigger.dateComponents == components(plan.fireDate)
    }
}
