import SwiftUI

/// The hub for the views beyond the overview: patterns, the shared calendar, recaps, notes, badges, routines and the timer.
struct ExploreView: View {
    @Environment(AppStore.self) private var store
    @Environment(TimerController.self) private var timer
    @Environment(\.colorScheme) private var scheme
    /// Shown in place by the bottom switcher, under the overview's shared top bar; otherwise pushed, with a back control.
    var inPlace = false
    @State private var timing = false
    /// Counts for the tile captions, worked out off the main thread so the page opens at once.
    @State private var summary: Summary?
    private struct Summary: Sendable {
        var kept: DayRate, notes: Int, badges: Int
        init(data: BuddyData, today: Day) {
            kept = WeekRecap(data: data, week: today, today: today).total
            // Hidden habits' days stay in the records, so count only the notes of habits shown.
            let shown = Set(data.habits.map(\.id))
            notes = data.records.values.reduce(0) { $0 + ($1.note.isEmpty || !shown.contains($1.habitID) ? 0 : 1) }
            badges = data.active.reduce(0) { $0 + Milestones($1, data: data, today: today).earned }
        }
    }
    var body: some View {
        let data = store.visible, recap = summary?.kept ?? DayRate(), notes = summary?.notes ?? 0, badges = summary?.badges ?? 0
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Explore").font(BuddyFont.text(32, .heavy)).foregroundStyle(BuddyStyle.text(scheme)).padding(.top, 4).homeFlow()
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    tile(.insights, "Insights", "sparkles", "violet", "Best and worst days, times and trends")
                    tile(.calendar, "Calendar", "calendar-days", "sky", "Every habit on one month")
                    tile(.recap, "Weekly Recap", "calendar-check", "green", recap.eligible == 0 ? "Your week at a glance" : "This week \(Int((recap.rate * 100).rounded()))% kept")
                    if data.settings.notes { tile(.notes, "Notes", "notebook-pen", "amber", notes == 0 ? "Every day note in one place" : "\(notes) \(notes == 1 ? "note" : "notes"), searchable") }
                    tile(.milestones(nil), "Milestones", "trophy", "orange", badges == 0 ? "Streak and check-in badges" : "\(badges) \(badges == 1 ? "badge" : "badges") earned")
                    tile(.routines, "Routines", "list-todo", "teal", data.routines.isEmpty ? "Check off habits together" : "\(data.routines.count) \(data.routines.count == 1 ? "routine" : "routines")")
                    tile(.challenges, "Challenges", "flag", "indigo", data.challenges.isEmpty ? "Build a 7, 14 or 30-day streak" : "\(data.challenges.count) active \(data.challenges.count == 1 ? "challenge" : "challenges")")
                    Button { timing = true } label: { label("Timer", "timer", "coral", timer.session == nil ? "Time a session and log it" : "A timer is running") }
                        .buttonStyle(FlatButtonStyle()).accessibilityIdentifier("explore-timer").homeFlow()
                }
            }.padding(.horizontal, 16).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden).pageClip()
        // In place, the overview draws the canvas behind every page.
        .background(BuddyStyle.canvas(scheme).opacity(inPlace ? 0 : 1)).toolbar(.hidden, for: .navigationBar)
        .switcherPageBar(inPlace: inPlace) {}
        .sheet(isPresented: $timing) { TimerView().buddySheet() }
        .task(id: store.revision) {
            let data = store.visible, today = Day()
            if let value = await offMain({ Summary(data: data, today: today) }) { summary = value }
        }
    }
    private func tile(_ route: OverviewRoute, _ title: String, _ icon: String, _ color: String, _ detail: String) -> some View {
        NavigationLink(value: route) { label(title, icon, color, detail) }.buttonStyle(FlatButtonStyle()).homeFlow()
    }
    private func label(_ title: String, _ icon: String, _ color: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LucideIcon(icon, size: 21).foregroundStyle(BuddyStyle.color(color)).frame(width: 42, height: 42)
                .background(BuddyStyle.color(color).opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .circular))
            Spacer(minLength: 12)
            Text(title).font(BuddyFont.text(17, .semibold)).foregroundStyle(BuddyStyle.text(scheme)).lineLimit(1)
            Text(detail).font(BuddyFont.text(12.5)).foregroundStyle(BuddyStyle.secondaryText(scheme)).lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading).padding(.top, 3)
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .surface(padding: 0, radius: 22, tint: BuddyStyle.color(color))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .circular))
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
    }
}

/// Habit icons in a row for filtering a page by habit; nil shows every habit.
struct HabitFilterBar: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent
    let habits: [Habit]
    @Binding var selection: UUID?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { selection = nil } label: {
                    Text("All").font(BuddyFont.text(14, .semibold)).foregroundStyle(BuddyStyle.text(scheme)).frame(height: 38).padding(.horizontal, 15)
                        .background(selection == nil ? BuddyStyle.control(scheme) : BuddyStyle.field(scheme), in: Capsule())
                        .overlay { Capsule().strokeBorder(selection == nil ? accent.color : BuddyStyle.border(scheme, 0.1), lineWidth: selection == nil ? 1.5 : 1) }
                }.buttonStyle(.plain).accessibilityLabel("All Habits").accessibilityAddTraits(selection == nil ? .isSelected : [])
                ForEach(habits) { h in
                    Button { selection = h.id } label: {
                        HabitIcon(habit: h, size: 38, circular: true).overlay { if selection == h.id { Circle().strokeBorder(BuddyStyle.color(h.color), lineWidth: 1.5) } }
                    }.buttonStyle(.plain).accessibilityLabel(h.name).accessibilityAddTraits(selection == h.id ? .isSelected : [])
                }
            }.padding(.vertical, 1)
        }
    }
}

/// A titled panel section used across the explore pages.
struct ExploreSection<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    var detail: String?
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).fieldCaption().foregroundStyle(BuddyStyle.secondaryText(scheme))
            if let detail { Text(detail).font(BuddyFont.text(15)).foregroundStyle(BuddyStyle.text(scheme)).fixedSize(horizontal: false, vertical: true) }
            content()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).panel(radius: 20, border: 0.09)
    }
}
