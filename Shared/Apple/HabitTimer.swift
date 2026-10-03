import ActivityKit
import AppIntents
import Foundation
import UserNotifications

/// The Live Activity for a running habit timer. The state only holds dates, so the system draws the clock.
struct HabitTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var start: Date
        /// Countdown end; nil counts up.
        var end: Date?
    }
    var habitID: String
    var name: String
    var symbol: String
    var color: String
    /// What finishing logs, e.g. "Logs minutes to Meditate".
    var summary: String
}

/// One running timer. It logs to the day it started, even if it ends after midnight.
struct TimerSession: Codable, Equatable {
    var habitID: UUID
    var day: Day
    var start: Date
    /// Countdown length in seconds; nil counts up.
    var duration: TimeInterval?
    var end: Date? { duration.map { start.addingTimeInterval($0) } }
    func elapsed(_ now: Date = Date()) -> TimeInterval { let value = max(0, now.timeIntervalSince(start)); return duration.map { min($0, value) } ?? value }
    func finished(_ now: Date = Date()) -> Bool { end.map { now >= $0 } ?? false }
}

/// The running timer is kept in the App Group defaults, so the app and its Live Activity buttons agree on it.
enum TimerSessions {
    static let notification = "timer.end"
    static let changed = Notification.Name("BuddyTimerChanged")
    private static let key = "buddy.timer"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: Bundle.main.object(forInfoDictionaryKey: "BuddyAppGroup") as? String ?? "group.com.iyashwant.habbitbuddy") ?? .standard
    }
    static var current: TimerSession? {
        get { defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(TimerSession.self, from: $0) } }
        set { if let newValue, let bytes = try? JSONEncoder().encode(newValue) { defaults.set(bytes, forKey: key) } else { defaults.removeObject(forKey: key) } }
    }
    /// Ends a timer and its Live Activity without logging. A timer started since is left running.
    static func stop(_ session: TimerSession? = TimerSessions.current) async {
        // A finished session was already cleared when it was logged; its notification still goes.
        if current == nil || current == session { current = nil; UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notification]) }
        for activity in Activity<HabitTimerAttributes>.activities where session == nil || activity.content.state.start == session!.start {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        NotificationCenter.default.post(name: changed, object: nil)
    }
    private struct AlreadyFinished: Error {}
    /// Logs a session exactly once. The session is claimed inside the store's locked transaction, so the app's
    /// Finish and the Live Activity's can't both log it. Returns nil when it was already finished or cancelled.
    static func finish(_ session: TimerSession, repository: BuddyRepository, at now: Date = Date()) throws -> BuddyData? {
        var claimed = false
        do {
            return try repository.transaction { data in
                guard current == session else { throw AlreadyFinished() }
                _ = try Engine.logTimer(seconds: session.elapsed(now), habitID: session.habitID, day: session.day, data: &data)
                current = nil; claimed = true
            }
        } catch is AlreadyFinished { return nil }
        catch {
            // Nothing was saved, so the timer keeps running and can be finished again.
            if claimed && current == nil { current = session }
            throw error
        }
    }
}

/// The Live Activity's Finish button. Live Activity intents run in the app's process.
struct FinishTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Finish Habit Timer"
    static var description = IntentDescription("Log the running habit timer and end it.")
    init() {}
    func perform() async throws -> some IntentResult {
        guard let session = TimerSessions.current else { return .result() }
        let data = try TimerSessions.finish(session, repository: AppEnvironment.repository)
        await TimerSessions.stop(session)
        if let data { await AppEnvironment.changed(data) }
        return .result()
    }
}
struct CancelTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Cancel Habit Timer"
    static var description = IntentDescription("End the running habit timer without logging it.")
    init() {}
    func perform() async throws -> some IntentResult { await TimerSessions.stop(); return .result() }
}
