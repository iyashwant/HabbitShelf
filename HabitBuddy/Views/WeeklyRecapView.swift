import SwiftUI

/// A week of every habit, compared with the week before, ready to share as an image.
struct WeeklyRecapView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    /// Set on appear: the current week on its last day, otherwise the last finished week.
    @State private var week = Day()
    @State private var configured = false
    @State private var export: SharedImage?
    @State private var message: String?
    @State private var rendering = false
    var body: some View {
        let today = Day(), weekStart = store.settings.weekStart, current = today.startOfWeek(weekStart)
        let start = week.startOfWeek(weekStart), recap = WeekRecap(data: store.visible, week: start, today: today)
        let earliest = (store.visible.habits.map(\.created).min() ?? today).startOfWeek(weekStart)
        let lastDay = Calendar.current.weekdaySymbols[(weekStart + 5) % 7]
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    MonthArrow(next: false) { week = start.adding(-7) }.disabled(start <= earliest)
                    Spacer()
                    Text(start == current ? "This Week" : start == current.adding(-7) ? "Last Week" : Self.range(recap)).font(BuddyFont.mono(14)).foregroundStyle(BuddyStyle.text(scheme))
                    Spacer()
                    MonthArrow(next: true) { week = start.adding(7) }.disabled(start >= current)
                }
                RecapPoster(recap: recap, data: store.visible, scheme: scheme)
                VStack(spacing: 0) {
                    SettingsToggle(title: "Remind me on \(lastDay)s", isOn: Binding(get: { store.settings.recapReminder }, set: { value in store.change { $0.settings.recapReminder = value }; if value { Task { _ = try? await NotificationService.request(); await NotificationService.reconcile(store.data) } } }))
                }.panel(radius: 20, border: 0.1)
                Text("A notification at 7 PM on the last day of each week, when the recap is ready.").font(BuddyFont.text(12.5)).foregroundStyle(BuddyStyle.tertiaryText(scheme)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                if let message { Text(message).font(BuddyFont.text(13)).foregroundStyle(.red) }
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(BuddyStyle.canvas(scheme)).toolbar(.hidden, for: .navigationBar)
        .topBar { PageBar(title: "Weekly Recap", trailing: "share", trailingLabel: "Share Weekly Recap", trailingAction: { share(recap) }) { dismiss() } }
        .sheet(item: $export) { image in NativeShareSheet(items: [image.url]) }
        .onAppear {
            guard !configured else { return }
            configured = true
            // On the week's last day the current week is complete enough to recap; earlier, show the week before.
            week = today == current.adding(6) ? current : current.adding(-7)
        }
    }
    static func range(_ recap: WeekRecap) -> String { "\(Day.shortMonth.string(from: recap.start.date)) \(Int(recap.start.rawValue.suffix(2))!) – \(Day.shortMonth.string(from: recap.end.date)) \(Int(recap.end.rawValue.suffix(2))!)" }
    @MainActor private func share(_ recap: WeekRecap) {
        guard !rendering else { return }
        rendering = true; message = nil
        let poster = RecapPoster(recap: recap, data: store.visible, scheme: scheme).padding(16).background(BuddyStyle.canvas(scheme)).environment(\.colorScheme, scheme)
        Task {
            defer { rendering = false }
            do { export = SharedImage(url: try await ImageExport.png(poster, width: 420, scale: 3, name: "weekly-recap-\(recap.start.rawValue).png")) }
            catch { message = error.localizedDescription }
        }
    }
}

struct RecapPoster: View {
    let recap: WeekRecap
    @ViewData var data: BuddyData
    let scheme: ColorScheme
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous), palette = WidgetPalette(.automatic, scheme: scheme, tint: Accent(data.settings.accent).color)
        let change = recap.previous.eligible == 0 || recap.total.eligible == 0 ? nil : Int(((recap.total.rate - recap.previous.rate) * 100).rounded())
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("WEEK OF \(WeeklyRecapView.range(recap).uppercased())").font(BuddyFont.text(11, .semibold)).tracking(1.2).foregroundStyle(palette.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(recap.total.eligible == 0 ? "–" : "\(Int((recap.total.rate * 100).rounded()))%").font(BuddyFont.text(52, .heavy)).monospacedDigit().foregroundStyle(palette.primary)
                    if let change {
                        Text(change == 0 ? "Same as last week" : "\(change > 0 ? "▲" : "▼") \(abs(change)) \(abs(change) == 1 ? "pt" : "pts")").font(BuddyFont.text(13, .semibold))
                            .foregroundStyle(change > 0 ? BuddyStyle.color("green") : change < 0 ? BuddyStyle.color("coral") : palette.secondary)
                            .padding(.horizontal, 9).frame(height: 26).background((change > 0 ? BuddyStyle.color("green") : change < 0 ? BuddyStyle.color("coral") : palette.secondary).opacity(0.13), in: Capsule())
                    }
                }
                Text(recap.total.eligible == 0 ? "No tracked habit days this week." : "\(recap.total.done) of \(recap.total.eligible) habit days kept").font(BuddyFont.text(14)).foregroundStyle(palette.secondary)
            }
            HStack(spacing: 8) {
                stat("\(recap.perfectDays)", recap.perfectDays == 1 ? "Perfect day" : "Perfect days", palette)
                stat(recap.bestDay.map { Day.shortWeekday.string(from: $0.date) } ?? "–", "Best day", palette)
                stat("\(recap.notes)", recap.notes == 1 ? "Note" : "Notes", palette)
            }
            VStack(spacing: 10) {
                ForEach(recap.rows, id: \.habitID) { row in
                    if let habit = data.habits.first(where: { $0.id == row.habitID }) {
                        let tint = BuddyStyle.color(habit.color)
                        HStack(spacing: 10) {
                            HabitIcon(habit: habit, size: 30)
                            Text(habit.name).font(BuddyFont.text(14, .semibold)).foregroundStyle(palette.primary).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 3) {
                                ForEach(0..<7, id: \.self) { i in
                                    let kept = row.days[i], square = RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    square.fill(kept == true ? tint : kept == false ? tint.opacity(palette.dark ? 0.22 : 0.18) : .clear).frame(width: 14, height: 14)
                                        .overlay { if kept == nil { square.strokeBorder(palette.outline, lineWidth: 1) } }
                                }
                            }
                            Text("\(row.rate.done)/\(row.rate.eligible)").font(BuddyFont.mono(11)).foregroundStyle(palette.secondary).frame(width: 30, alignment: .trailing)
                        }
                        .accessibilityElement(children: .ignore).accessibilityLabel("\(habit.name), \(row.rate.done) of \(row.rate.eligible) days kept")
                    }
                }
            }
            HStack { Spacer(); Text("HabitShelf").font(BuddyFont.text(11, .semibold)).foregroundStyle(palette.secondary) }
        }
        .padding(20).background(palette.background(shape)).overlay { shape.strokeBorder(BuddyStyle.border(scheme, 0.08), lineWidth: 1) }
    }
    private func stat(_ value: String, _ title: String, _ palette: WidgetPalette) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(BuddyFont.text(20, .heavy)).foregroundStyle(palette.primary).lineLimit(1)
            Text(title).font(BuddyFont.text(11.5)).foregroundStyle(palette.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(palette.outline.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
