import Foundation

/// Progress shared by the Explore tile and challenge detail page.
public struct ChallengeProgress: Equatable, Sendable {
    public let completedDays: Int
    public let dayNumber: Int
    public let completed: Bool

    public init(challenge: Challenge, data: BuddyData, today: Day = Day()) {
        let habits = challenge.habitIDs.compactMap { id in data.habits.first { $0.id == id } }
        let last = min(today, challenge.end)
        var completedDays = 0
        if !habits.isEmpty, challenge.start <= last {
            for day in Day.range(challenge.start, last) {
                if habits.allSatisfy({ Engine.progress($0, day: day, data: data, today: today).success }) {
                    completedDays += 1
                }
            }
        }
        self.completedDays = completedDays
        dayNumber = min(challenge.duration, max(0, challenge.start.distance(to: today) + 1))
        completed = completedDays == challenge.duration
    }
}
