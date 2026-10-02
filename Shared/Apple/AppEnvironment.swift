import Foundation
import WidgetKit
import UserNotifications

enum AppEnvironment {
    static var repository: BuddyRepository {
        let group = Bundle.main.object(forInfoDictionaryKey: "BuddyAppGroup") as? String ?? "group.com.iyashwant.habbitbuddy"
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            // Never silently split app and widget into unrelated databases.
            return BuddyRepository(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HabitBuddy"))
        }
        return BuddyRepository(directory: root.appendingPathComponent("HabitBuddy"))
    }
    static var hasSharedContainer: Bool {
        let group = Bundle.main.object(forInfoDictionaryKey: "BuddyAppGroup") as? String ?? "group.com.iyashwant.habbitbuddy"
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil
    }
    static func changed(_ data: BuddyData) async {
        WidgetCenter.shared.reloadAllTimelines()
        await NotificationService.reconcile(data)
    }
}

enum NotificationService {
    static func request() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
    static func reconcile(_ data: BuddyData) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let old = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: old.filter { $0.identifier.hasPrefix("buddy.") }.map(\.identifier))
        let coverage = ReminderPlanner.plan(data)
        for request in coverage.requests {
            let content = UNMutableNotificationContent()
            content.title = request.title; content.body = request.body; content.sound = .default
            if let id = request.habitID { content.userInfo = ["habitID": id.uuidString] }
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: request.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            do { try await center.add(UNNotificationRequest(identifier: request.id, content: content, trigger: trigger)) }
            catch { NSLog("Habit Buddy: notification scheduling failed: %@", error.localizedDescription) }
        }
    }
}
