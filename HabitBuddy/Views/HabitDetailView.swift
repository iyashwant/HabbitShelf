import SwiftUI

struct HabitDetailView: View {
    @EnvironmentObject private var store: AppStore
    let id: UUID
    @State private var editor: Habit?
    @State private var selection: DaySelection?
    @State private var share = false
    @State private var month = Day().startOfMonth
    var body: some View {
        Group {
            if let habit = store.habit(id) {
                let stats = Engine.stats(habit, data: store.data)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 12) { HabitIcon(habit: habit, size: 52); VStack(alignment: .leading, spacing: 4) { Text(habit.name).font(.title2.bold()); Text(habit.detail).font(.subheadline).foregroundStyle(.secondary) } }
                        Heatmap(habit: habit, data: store.data).surface()
                        HStack { MetricChip(symbol: "flame.fill", text: "\(stats.currentStreak)", color: BuddyStyle.color(habit.color)); MetricChip(symbol: "target", text: habit.currentGoal.summary, color: BuddyStyle.color(habit.color)) }
                        VStack(spacing: 17) {
                            HStack { Button { shift(-1) } label: { Image(systemName: "chevron.left") }; Spacer(); Text(month.monthTitle).font(.headline); Spacer(); Button { shift(1) } label: { Image(systemName: "chevron.right") }.disabled(month.month >= Day().month) }
                            let start = month.startOfWeek(store.data.settings.weekStart)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                                ForEach(0..<7, id: \.self) { index in Text(Calendar.current.shortWeekdaySymbols[(store.data.settings.weekStart - 1 + index) % 7]).font(.caption2).foregroundStyle(.secondary) }
                                ForEach(Day.range(start, month.endOfMonth)) { day in
                                    Button { selection = DaySelection(habit: habit, day: day) } label: { DayTile(habit: habit, day: day, data: store.data, size: 36, showNumber: true) }
                                        .buttonStyle(.plain).disabled(day.month != month.month || !habit.available(on: day, today: Day()) || habit.archived != nil)
                                        .opacity(day.month == month.month ? 1 : 0.2)
                                }
                            }
                            Text("Tap a day to edit its progress or add a note.").font(.caption2).foregroundStyle(.secondary)
                        }.surface()
                        HStack { metric("Completions", "\(stats.completions)"); metric("Completion Rate", "\(Int(stats.rate * 100))%") }
                        HStack { metric("Current Streak", "\(stats.currentStreak)"); metric("Best Streak", "\(stats.bestStreak)") }
                        Button("Share Habit", systemImage: "square.and.arrow.up") { share = true }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                    }.padding(20)
                }
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit", systemImage: "square.and.pencil") { editor = habit }.disabled(habit.archived != nil) } }
                .sheet(isPresented: $share) { ShareHabitView(habit: habit) }
            } else { ContentUnavailableView("Habit unavailable", systemImage: "archivebox") }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editor) { HabitEditorView(habit: $0) }
        .sheet(item: $selection) { DayEditorView(selection: $0) }
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(value).font(.title.bold()); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).surface()
    }
    private func shift(_ delta: Int) { month = Day(Day.calendar.date(byAdding: .month, value: delta, to: month.date)!, timeZone: TimeZone(secondsFromGMT: 0)!) }
}

struct DayEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let selection: DaySelection
    @State private var amount = "0"
    @State private var note = ""
    @State private var complete = false
    @State private var message: String?
    private var habit: Habit { store.habit(selection.habit.id) ?? selection.habit }
    private var goal: Goal { habit.goal(on: selection.day) }
    private var locked: Bool { goal.mode != habit.currentGoal.mode }
    var body: some View {
        NavigationStack {
            Form {
                Section { HStack { HabitIcon(habit: habit); VStack(alignment: .leading) { Text(habit.name).font(.headline); Text(selection.day.rawValue).font(.caption).foregroundStyle(.secondary) } } }
                Section(goal.mode == .quit ? "Slip / amount" : "Progress") {
                    if goal.tracking == .yesNo { Toggle(goal.mode == .quit ? "I had a slip" : "Completed", isOn: $complete).disabled(locked) }
                    else { TextField("Amount in \(goal.unit)", text: $amount).keyboardType(.decimalPad).disabled(locked); Text(goal.mode == .quit ? "A clean day stays strictly below \(Amount.text(goal.target)) \(goal.unit)." : "Target: \(Amount.text(goal.target)) \(goal.unit)").font(.caption).foregroundStyle(.secondary) }
                    if locked { Text("This date belongs to an earlier habit mode. Its progress is preserved.").font(.caption).foregroundStyle(.secondary) }
                    else { Button("Clear Progress") { amount = "0"; complete = false } }
                }
                if store.data.settings.notes { Section("Day note") { TextEditor(text: $note).frame(minHeight: 140); Text("A note does not change progress.").font(.caption).foregroundStyle(.secondary) } }
                if let text = message ?? store.error { Text(text).foregroundStyle(.red) }
            }.navigationTitle("Edit Day").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } } }
                .onAppear { let record = store.data.record(habit.id, selection.day); amount = Amount.text(record.amount); note = record.note; complete = record.amount > 0 }
        }
    }
    private func save() {
        do {
            let value = goal.tracking == .yesNo ? (complete ? Int64(1_000) : 0) : try Amount.parse(amount)
            if store.change({ data in
                if !locked { try Engine.setAmount(value, habitID: habit.id, day: selection.day, data: &data) }
                if data.settings.notes { try Engine.note(note, habitID: habit.id, day: selection.day, data: &data) }
            }) { dismiss() }
        } catch { message = error.localizedDescription }
    }
}
