import SwiftUI

struct HabitEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var habit: Habit
    @State private var target = "1"
    @State private var emoji = ""
    @State private var symbolSearch = ""
    @State private var reminders = false
    @State private var validation: String?
    private var existing: Bool { store.habit(habit.id) != nil }
    private var goal: Binding<Goal> { Binding(get: { habit.goals[habit.goals.count - 1] }, set: { habit.goals[habit.goals.count - 1] = $0 }) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(spacing: 16) {
                        HabitIcon(habit: habit, size: 78)
                        TextField("Search icons", text: $symbolSearch).textFieldStyle(.roundedBorder)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 13) {
                            ForEach(BuddyStyle.symbols.filter { symbolSearch.isEmpty || $0.localizedCaseInsensitiveContains(symbolSearch) }, id: \.self) { symbol in
                                Button { habit.symbol = symbol } label: {
                                    Image(systemName: symbol).frame(width: 30, height: 30).foregroundStyle(BuddyStyle.color(habit.color).opacity(habit.symbol == symbol ? 1 : 0.35))
                                }.buttonStyle(.plain).accessibilityLabel(symbol)
                            }
                        }
                        HStack { TextField("Or use an emoji", text: $emoji); Button("Use") { if !emoji.isEmpty { habit.symbol = String(emoji.prefix(2)) } }.disabled(emoji.isEmpty) }
                    }
                    field("NAME") { TextField("Habit name", text: $habit.name).textInputAutocapitalization(.sentences).padding(14).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14)) }
                    field("DESCRIPTION") { TextField("What does this habit mean to you?", text: $habit.detail, axis: .vertical).lineLimit(2...4).padding(14).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14)) }
                    field("COLOR") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                            ForEach(BuddyStyle.colors, id: \.0) { token, _ in
                                Button { habit.color = token } label: {
                                    RoundedRectangle(cornerRadius: 10).fill(BuddyStyle.color(token)).frame(height: 36)
                                        .overlay { if habit.color == token { RoundedRectangle(cornerRadius: 10).stroke(Color.primary, lineWidth: 2).padding(-3) } }
                                }.buttonStyle(.plain).accessibilityLabel(token).accessibilityAddTraits(habit.color == token ? .isSelected : [])
                            }
                        }
                    }
                    field("HABIT TYPE") {
                        Picker("Habit type", selection: goal.mode) {
                            Text("Build a habit").tag(HabitMode.build); Text("Quit a habit").tag(HabitMode.quit)
                        }.pickerStyle(.segmented)
                        Text(habit.currentGoal.mode == .quit ? "Clean days fill automatically. Log the days you slip." : "Mark each day you make progress.").font(.caption).foregroundStyle(.secondary)
                    }
                    field("TRACKING") {
                        Picker("Tracking", selection: goal.tracking) { Text("Yes / No").tag(Tracking.yesNo); Text("Count").tag(Tracking.count); Text("Measure").tag(Tracking.measure) }.pickerStyle(.segmented)
                        if habit.currentGoal.tracking != .yesNo {
                            HStack {
                                Text(habit.currentGoal.mode == .quit ? "Stay below" : "Daily target")
                                Spacer(); TextField("Target", text: $target).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                            }.padding(.vertical, 8)
                            if habit.currentGoal.tracking == .measure { TextField("Unit (minutes, km, liters…)", text: goal.unit).textFieldStyle(.roundedBorder) }
                            Picker("On tap", selection: goal.tap) { Text("Add 1").tag(TapAction.addOne); Text("Enter total").tag(TapAction.enterTotal) }.pickerStyle(.segmented)
                        }
                    }
                    if habit.currentGoal.mode == .build {
                        field("STREAK GOAL") {
                            Picker("Schedule", selection: goal.cadence) { ForEach(Cadence.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.pickerStyle(.segmented)
                            if habit.currentGoal.cadence == .weekly || habit.currentGoal.cadence == .monthly {
                                Stepper("\(habit.currentGoal.days) successful days", value: goal.days, in: 1...(habit.currentGoal.cadence == .weekly ? 7 : 31))
                            }
                        }
                    }
                    if !store.data.categories.isEmpty {
                        field("CATEGORIES") {
                            ForEach(store.data.categories) { category in
                                Toggle(category.name, isOn: Binding(get: { habit.categories.contains(category.id) }, set: { included in habit.categories.removeAll { $0 == category.id }; if included { habit.categories.append(category.id) } }))
                            }
                        }
                    }
                    Button { reminders = true } label: { HStack { Label("Reminders", systemImage: "bell"); Spacer(); Text("\(habit.reminders.count)").foregroundStyle(.secondary); Image(systemName: "chevron.right") } }.surface()
                    if existing { Text("Goal changes take effect today. Earlier days keep their original rules. Changing mode or tracking resets today's amount and preserves its note.").font(.caption).foregroundStyle(.secondary) }
                    if let text = validation ?? store.error { Text(text).font(.caption).foregroundStyle(.red) }
                }.padding(20)
            }
            .navigationTitle(existing ? "Edit Habit" : "New Habit").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) { Button("Save") { save() }.font(.headline).frame(maxWidth: .infinity).padding(14).background(BuddyStyle.purple, in: Capsule()).foregroundStyle(.white).padding(.horizontal, 20).padding(.vertical, 10).background(.bar) }
            .sheet(isPresented: $reminders) { ReminderEditorView(reminders: $habit.reminders) }
            .onAppear { target = Amount.text(habit.currentGoal.target) }
            .onChange(of: habit.currentGoal.cadence) { _, new in if new == .daily || new == .none { goal.wrappedValue.days = 1 } else if new == .weekly { goal.wrappedValue.days = min(7, habit.currentGoal.days) } }
        }
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(title).font(.caption2.weight(.medium)).foregroundStyle(.secondary); content() }
    }
    private func save() {
        do {
            var rule = habit.currentGoal
            rule.target = rule.tracking == .yesNo ? 1_000 : try Amount.parse(target)
            if rule.mode == .quit { rule.cadence = .daily; rule.days = 1 }
            if rule.cadence == .none || rule.cadence == .daily { rule.days = 1 }
            habit.name = habit.name.trimmingCharacters(in: .whitespacesAndNewlines)
            habit.goals[habit.goals.count - 1] = rule
            if store.change({ try Engine.saveHabit(habit, data: &$0) }) { dismiss() }
        } catch { validation = error.localizedDescription }
    }
}

struct ReminderEditorView: View {
    @Binding var reminders: [Reminder]
    @Environment(\.dismiss) private var dismiss
    @State private var denied = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                ForEach($reminders) { $reminder in
                    Section {
                        Toggle("Enabled", isOn: $reminder.enabled)
                        DatePicker("Time", selection: Binding(get: { Calendar.current.date(from: DateComponents(hour: reminder.hour, minute: reminder.minute)) ?? Date() }, set: { reminder.hour = Calendar.current.component(.hour, from: $0); reminder.minute = Calendar.current.component(.minute, from: $0) }), displayedComponents: .hourAndMinute)
                        WeekdayPicker(days: $reminder.weekdays)
                        Button("Remove Reminder", role: .destructive) { reminders.removeAll { $0.id == reminder.id } }
                    }
                }
                if reminders.count < 3 { Button("Add Reminder", systemImage: "plus") { reminders.append(Reminder()) } }
                Section {
                    Button("Allow Notifications") { Task { do { denied = try await !NotificationService.request() } catch { message = error.localizedDescription } } }
                    if denied { Text("Notification permission is off. Your reminders remain saved.").font(.caption); Link("Open System Settings", destination: URL(string: UIApplication.openSettingsURLString)!) }
                    if let message { Text(message).foregroundStyle(.red) }
                } footer: { Text("Notifications follow the phone’s local clock. A rolling seven-day queue is refreshed when you open the app or log progress. iOS may delay delivery.") }
            }.navigationTitle("Reminders").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
struct WeekdayPicker: View {
    @Binding var days: [Int]
    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...7, id: \.self) { day in
                Button { if days.contains(day) { if days.count > 1 { days.removeAll { $0 == day } } } else { days.append(day) } } label: {
                    Text(["S", "M", "T", "W", "T", "F", "S"][day - 1]).font(.caption).frame(maxWidth: .infinity).padding(.vertical, 9).background(days.contains(day) ? BuddyStyle.purple : Color.secondary.opacity(0.15), in: Circle()).foregroundStyle(days.contains(day) ? Color.white : .primary)
                }.buttonStyle(.plain).accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
            }
        }
    }
}
