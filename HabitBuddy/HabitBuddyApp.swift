import SwiftUI
import UserNotifications

@main struct HabitBuddyApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            OverviewView().environmentObject(store)
                .tint(BuddyStyle.purple)
                .preferredColorScheme(store.data.settings.theme == .system ? nil : store.data.settings.theme == .dark ? .dark : .light)
        }
    }
}
