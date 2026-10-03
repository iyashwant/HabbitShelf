import SwiftUI
import UserNotifications

@main struct HabitBuddyApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var timer = TimerController()
    init() { _ = BuddyIcons.registered }
    var body: some Scene {
        WindowGroup {
            OverviewView().environmentObject(store).environmentObject(timer)
                .tint(BuddyStyle.purple)
                .preferredColorScheme(store.data.settings.theme == .system ? nil : store.data.settings.theme == .dark ? .dark : .light)
        }
    }
}
