import SwiftUI
import WidgetKit

@MainActor final class AppStore: ObservableObject {
    @Published private(set) var data = BuddyData()
    @Published var error: String?
    @Published var loaded = false
    @Published var sharedStorageAvailable = AppEnvironment.hasSharedContainer
    let repository = AppEnvironment.repository
    init() { reload() }
    func reload() {
        do { data = try repository.load(); loaded = true }
        catch { self.error = error.localizedDescription; loaded = false }
    }
    @discardableResult func change(_ block: (inout BuddyData) throws -> Void) -> Bool {
        guard loaded else { error = "Data could not be loaded. Restore a backup before making changes."; return false }
        do {
            data = try repository.transaction(block)
            Task { await AppEnvironment.changed(data) }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func habit(_ id: UUID) -> Habit? { data.habits.first { $0.id == id } }
    @discardableResult func setAmount(_ value: Int64, _ id: UUID, _ day: Day) -> Bool {
        change { try Engine.setAmount(value, habitID: id, day: day, data: &$0) }
    }
    @discardableResult func quickLog(_ habit: Habit, day: Day = Day()) -> Bool {
        let goal = habit.goal(on: day), old = data.record(habit.id, day).amount
        let result = change { data in
            if goal.tracking == .yesNo { try Engine.setAmount(old == 0 ? 1_000 : 0, habitID: habit.id, day: day, data: &data) }
            else { try Engine.increment(habitID: habit.id, day: day, data: &data) }
        }
        if result && data.settings.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        return result
    }
    func archive(_ id: UUID, restore: Bool = false) {
        change { data in
            if let i = data.habits.firstIndex(where: { $0.id == id }) {
                if restore, let start = data.habits[i].archived?.adding(1), start < Day() {
                    data.habits[i].pauses.append(Pause(from: start, through: Day().adding(-1)))
                }
                data.habits[i].archived = restore ? nil : Day()
            }
        }
    }
    @discardableResult func restore(_ bytes: Data) -> Bool {
        do {
            data = try repository.restore(bytes); loaded = true
            Task { await AppEnvironment.changed(data) }; return true
        } catch { self.error = error.localizedDescription; return false }
    }
}

struct DaySelection: Identifiable {
    let habit: Habit
    let day: Day
    var id: String { "\(habit.id)-\(day.rawValue)" }
}
