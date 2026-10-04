import SwiftUI
import UserNotifications

@main struct HabitBuddyApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var timer = TimerController()
    init() { _ = BuddyIcons.registered; Task.detached(priority:.utility) { _ = BuddyIcons.suggester } }
    var body: some Scene {
        WindowGroup {
            let accent = Accent(store.data.settings.accent)
            OverviewView().environmentObject(store).environmentObject(timer).environment(\.summaries, store.summaries)
                .environment(\.accent, accent).tint(accent.color)
                .environment(\.glass, GlassStyle(store.data.settings.glass, accent: accent))
                .preferredColorScheme(store.data.settings.theme.colorScheme)
                // Alerts, menus, the color picker and the share sheet take the window's tint rather than SwiftUI's.
                .onChange(of: accent, initial: true) { _, accent in
                    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes { for window in scene.windows { window.tintColor = UIColor(accent.color) } }
                }
        }
    }
}
