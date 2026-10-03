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
    public static let recapID = UUID(uuidString: "00000000-0000-0000-0003-000000000001")!
    /// Earliest-first allocation gives all habits equal access to the next notification slots.
    /// One-off local dates make today's suppression possible without canceling future reminders.
    public static func plan(_ data: BuddyData, now: Date = Date(), timeZone: TimeZone = .current, budget: Int = 60) -> ReminderCoverage {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        var result: [PlannedReminder] = []
        let today = Day(now, timeZone: timeZone)
        func append(_ reminder: Reminder, habit: Habit?, title: String? = nil, body: String? = nil) {
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
                                              title: title ?? habit?.name ?? data.settings.checkInTitle,
                                              body: body ?? habit.map { $0.currentGoal.mode == .quit ? "Stay mindful of your intention today." : "A small step makes a difference." } ?? data.settings.checkInBody,
                                              fireDate: date))
            }
        }
        for habit in data.active { for reminder in habit.reminders { append(reminder, habit: habit) } }
        if let reminder = data.settings.checkIn { append(reminder, habit: nil) }
        if data.settings.recapReminder {
            // The evening of the week's last day, e.g. Sunday when weeks start on Monday.
            var recap = Reminder(); recap.id = recapID; recap.hour = 19; recap.weekdays = [(data.settings.weekStart + 5) % 7 + 1]
            append(recap, habit: nil, title: "Your week in habits", body: "Your weekly recap is ready. Take a look at how the week went.")
        }
        result.sort { $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate }
        return ReminderCoverage(requests: Array(result.prefix(max(0, budget))), requestedCount: result.count)
    }
}
