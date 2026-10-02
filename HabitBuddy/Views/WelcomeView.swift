import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "square.grid.3x3.fill").font(.system(size: 76)).foregroundStyle(BuddyStyle.purple)
            Text("Small steps.\nVisible progress.").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("Build good habits, leave others behind, and see your consistency grow one square at a time.").font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 18) {
                Label("Yes/no, counts, and measured goals", systemImage: "target")
                Label("Daily, weekly, and monthly streaks", systemImage: "flame")
                Label("Local storage with recoverable backups", systemImage: "lock.shield")
            }.font(.subheadline).surface()
            Spacer()
            Button("Get Started") { store.change { $0.settings.onboarding = true } }.font(.headline).frame(maxWidth: .infinity).padding(17).background(BuddyStyle.purple, in: Capsule()).foregroundStyle(.white)
        }.padding(28)
    }
}
