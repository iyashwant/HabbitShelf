import SwiftUI
import UserNotifications

@main struct HabitBuddyApp: App {
    @State private var store = AppStore()
    @State private var timer = TimerController()
    init() { _ = BuddyIcons.registered; Task.detached(priority:.utility) { _ = BuddyIcons.suggester } }
    var body: some Scene {
        WindowGroup {
            // Reads only the settings, so a check-in doesn't redraw the root.
            let accent = Accent(store.settings.accent)
            OverviewView().environment(store).environment(timer).environment(\.summaries, store.summaries)
                .environment(\.accent, accent).tint(accent.color)
                .environment(\.glass, GlassStyle(store.settings.glass, accent: accent))
                .preferredColorScheme(store.settings.theme.colorScheme)
                // Alerts, menus, the color picker and the share sheet take the window's tint rather than SwiftUI's.
                .onChange(of: accent, initial: true) { _, accent in
                    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes { for window in scene.windows { window.tintColor = UIColor(accent.color) } }
                }
        }
    }
}
