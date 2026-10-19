import ActivityKit
import Observation
import SwiftUI
import UserNotifications

/// Starts and finishes habit timers, with a Live Activity and an end-of-countdown notification.
@MainActor @Observable final class TimerController {
    private(set) var session: TimerSession?
    var message: String?
    @ObservationIgnored private var observer: NSObjectProtocol?
    init() {
        #if DEBUG
        // Visual fixtures start without a leftover timer from an earlier run.
        if ProcessInfo.processInfo.environment["BUDDY_VISUAL_SCREEN"] != nil, ProcessInfo.processInfo.environment["BUDDY_VISUAL_RESET"] != "false" {
            TimerSessions.current = nil
            for activity in Activity<HabitTimerAttributes>.activities { Task { await activity.end(nil, dismissalPolicy: .immediate) } }
        }
        #endif
        session = TimerSessions.current
        // A Live Activity button may finish or cancel the timer while the app runs.
        observer = NotificationCenter.default.addObserver(forName: TimerSessions.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.session = TimerSessions.current }
        }
    }
    var liveActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    func start(_ habit: Habit, duration: TimeInterval?) {
        let session = TimerSession(habitID: habit.id, day: Day(), start: Date(), duration: duration)
        TimerSessions.current = session; self.session = session; message = nil
        if liveActivitiesEnabled {
            let attributes = HabitTimerAttributes(habitID: habit.id.uuidString, name: habit.name, symbol: habit.symbol, color: habit.color, summary: Self.summary(habit, short: true))
            do { _ = try Activity.request(attributes: attributes, content: ActivityContent(state: .init(start: session.start, end: session.end), staleDate: session.end)) }
            catch { message = "The timer is running, but the Lock Screen activity couldn't start: \(error.localizedDescription)" }
        }
        if let end = session.end {
            let content = UNMutableNotificationContent()
            content.title = habit.name; content.body = "Time's up. Open HabitShelf to log it."; content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: TimerSessions.notification, content: content, trigger: trigger))
        }
    }
    /// Logs the elapsed time (capped at the countdown) through the shared engine, then ends the timer.
    func finish(_ store: AppStore) {
        guard let session else { return }
        let now = Date()
        Task { if await store.finishTimer(session, at: now) { end() } }
    }
    func cancel() { end() }
    private func end() { let ended = session; session = nil; Task { await TimerSessions.stop(ended) } }
    /// What finishing does, in words. The short form fits the Live Activity.
    static func summary(_ habit: Habit, short: Bool = false) -> String {
        switch TimerUnit(habit.currentGoal) {
        case .completion: short ? "Completes when finished" : "Finishing completes \(habit.name)"
        case .some: short ? "Logs \(habit.currentGoal.unit) when finished" : "Finishing logs the time to \(habit.name) in \(habit.currentGoal.unit)"
        case nil: "This habit doesn't take timers"
        }
    }
}
