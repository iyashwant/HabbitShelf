import Foundation
import Testing
@testable import BuddyCore

struct CalendarLayoutTests {
    @Test func olderSettingsKeepTheCompactGrid() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data(#"{"layout":"month"}"#.utf8))
        #expect(settings.layout == .month)
        #expect(settings.calendarLayout == nil)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        #expect(object?["calendarLayout"] == nil)
    }

    @Test(arguments: CalendarLayout.allCases)
    func portableBackupsPreserveLayoutAndHistory(_ layout: CalendarLayout) throws {
        let today = Day(rawValue: "2026-10-19")!
        var data = BuddyData()
        let habit = Habit(name: "Read", created: today.adding(-20))
        data.habits = [habit]
        try Engine.complete(habit.id, day: today.adding(-1), data: &data, today: today)
        data.settings.layout = .month
        data.settings.calendarLayout = layout
        let restored = try DataValidation.decode(DataValidation.encode(data), today: today)
        #expect(restored.settings.calendarLayout == layout)
        #expect(restored.settings.layout == .month)
        #expect(restored.habits == data.habits)
        #expect(restored.records == data.records)
    }
}
