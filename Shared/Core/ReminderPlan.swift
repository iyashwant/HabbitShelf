import Foundation

public struct PlannedReminder: Equatable, Sendable {
    public var id: String
    public var habitID: UUID?
    public var title: String
    public var body: String
    public var fireDate: Date
}
public struct ReminderCoverage: Sendable {
    public var requests: [PlannedReminder]
    public var requestedCount: Int
    public var omittedCount: Int { requestedCount - requests.count }
}
public enum ReminderPlanner {
    /// Earliest-first allocation gives all habits equal access to the next notification slots.
    /// One-off local dates make today's suppression possible without canceling future reminders.
    public static func plan(_ data: BuddyData, now: Date = Date(), timeZone: TimeZone = .current, budget: Int = 60) -> ReminderCoverage {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        var result: [PlannedReminder] = []
        let today = Day(now, timeZone: timeZone)
        func append(_ reminder: Reminder, habit: Habit?) {
            guard reminder.enabled else { return }
            for offset in 0..<7 {
                guard let local = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                let day = Day(local, timeZone: timeZone)
                guard reminder.weekdays.contains(calendar.component(.weekday, from: local)) else { continue }
                var c = calendar.dateComponents([.year, .month, .day], from: local)
                c.hour = reminder.hour; c.minute = reminder.minute; c.second = 0
                guard let date = calendar.date(from: c), date > now else { continue }
                if let habit = habit, day == today {
                    let p = Engine.progress(habit, day: day, data: data, today: today)
                    if habit.currentGoal.mode == .build ? p.success : p.slip { continue }
                }
                result.append(PlannedReminder(id: "buddy.\(reminder.id).\(day.rawValue)", habitID: habit?.id,
                                              title: habit?.name ?? data.settings.checkInTitle,
                                              body: habit.map { $0.currentGoal.mode == .quit ? "Stay mindful of your intention today." : "A small step makes a difference." } ?? data.settings.checkInBody,
                                              fireDate: date))
            }
        }
        for habit in data.active { for reminder in habit.reminders { append(reminder, habit: habit) } }
        if let reminder = data.settings.checkIn { append(reminder, habit: nil) }
        result.sort { $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate }
        return ReminderCoverage(requests: Array(result.prefix(max(0, budget))), requestedCount: result.count)
    }
}
