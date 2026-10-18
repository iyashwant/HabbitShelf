import SwiftUI

/// Short-term commitments built from existing habits and their shared check-in history.
struct ChallengesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var editing: Challenge?
    @State private var open: Challenge?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if store.visible.challenges.isEmpty {
                    ContentUnavailableView {
                        Label("No challenges yet", systemImage: "flag")
                    } description: {
                        Text("Choose a few habits and keep them going for 7, 14, or 30 days.")
                    } actions: {
                        Button("Create Challenge") { editing = Challenge(name: "") }
                            .buttonStyle(.borderedProminent)
                            .foregroundStyle(Accent(store.settings.accent).foreground)
                            .disabled(store.visible.active.isEmpty)
                    }.padding(.top, 40)
                }
                ForEach(store.visible.challenges) { challenge in
                    ChallengeCard(challenge: challenge) { open = challenge }
                        .contextMenu {
                            Button("Edit Challenge", systemImage: "square.and.pencil") { editing = store.data.challenges.first { $0.id == challenge.id } ?? challenge }
                        }
                }
                if !store.visible.challenges.isEmpty {
                    Text("A day counts when every selected habit reaches its goal. Existing check-ins count toward your challenge.")
                        .font(BuddyFont.text(12.5)).foregroundStyle(BuddyStyle.tertiaryText(scheme))
                        .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(BuddyStyle.canvas(scheme)).toolbar(.hidden, for: .navigationBar)
        .topBar { PageBar(title: "Challenges", trailing: "plus", trailingLabel: "New Challenge", trailingAction: { editing = Challenge(name: "") }) { dismiss() } }
        .sheet(item: $editing) { ChallengeEditorView(challenge: $0).buddySheet() }
        .sheet(item: $open) { ChallengeDetailView(challenge: $0).buddySheet() }
    }
}

private struct ChallengeCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let challenge: Challenge
    var open: () -> Void

    var body: some View {
        let data = store.visible
        let stats = ChallengeProgress(challenge: challenge, data: data)
        let habits = challenge.habitIDs.compactMap { id in data.habits.first { $0.id == id } }
        let tint = BuddyStyle.color(habits.first?.color ?? "violet")
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().strokeBorder(tint.opacity(0.17), lineWidth: 5)
                    Circle().trim(from: 0, to: min(1, Double(stats.completedDays) / Double(challenge.duration)))
                        .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text("\(stats.completedDays)").font(BuddyFont.mono(13, .bold)).foregroundStyle(BuddyStyle.text(scheme))
                }.frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.name).font(BuddyFont.text(17, .semibold)).foregroundStyle(BuddyStyle.text(scheme)).lineLimit(1)
                    Text(stats.completed ? "Challenge complete" : "\(stats.dayNumber) of \(challenge.duration) days · \(stats.completedDays) completed")
                        .font(BuddyFont.text(12.5)).foregroundStyle(BuddyStyle.secondaryText(scheme)).lineLimit(1)
                }
                Spacer(minLength: 4)
                LucideIcon("arrow-up-right", size: 16).foregroundStyle(BuddyStyle.tertiaryText(scheme))
            }
            HStack(spacing: 7) {
                ForEach(habits.prefix(6)) { HabitIcon(habit: $0, size: 28) }
                if habits.count > 6 { Text("+\(habits.count - 6)").font(BuddyFont.mono(11)).foregroundStyle(BuddyStyle.secondaryText(scheme)) }
                Spacer()
                Text("\(challenge.duration) DAYS").font(BuddyFont.mono(10, .semibold)).tracking(0.7).foregroundStyle(tint)
            }
        }
        .padding(15).surface(padding: 0, radius: 23, tint: tint)
        .contentShape(RoundedRectangle(cornerRadius: 23, style: .continuous)).onTapGesture(perform: open)
        .accessibilityElement(children: .contain).accessibilityAction(named: "Open \(challenge.name)", open)
    }
}

struct ChallengeEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent
    @State var challenge: Challenge

    private var existing: Bool { store.data.challenges.contains { $0.id == challenge.id } }
    private var valid: Bool {
        !challenge.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !challenge.habitIDs.isEmpty && challenge.habitIDs.count <= 20
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: existing ? "Edit Challenge" : "New Challenge")
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("CHALLENGE NAME") {
                        TextField("", text: $challenge.name, prompt: Text("30-Day Reading Habit"))
                            .accessibilityLabel("Challenge name").buddyField()
                    }
                    section("LENGTH") {
                        HStack(spacing: 8) {
                            ForEach([7, 14, 30], id: \.self) { days in
                                Button { challenge.duration = days } label: {
                                    VStack(spacing: 3) {
                                        Text("\(days)").font(BuddyFont.text(18, .semibold))
                                        Text("DAYS").font(BuddyFont.mono(9, .semibold)).tracking(0.6)
                                    }.foregroundStyle(challenge.duration == days ? accent.foreground : BuddyStyle.text(scheme))
                                        .frame(maxWidth: .infinity, minHeight: 54)
                                        .background(challenge.duration == days ? accent.color : BuddyStyle.field(scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    section("CHOOSE HABITS · UP TO 20") {
                        VStack(spacing: 0) {
                            ForEach(store.visible.active) { habit in
                                Toggle(isOn: Binding(get: { challenge.habitIDs.contains(habit.id) }, set: { selected in
                                    challenge.habitIDs.removeAll { $0 == habit.id }
                                    if selected && challenge.habitIDs.count < 20 { challenge.habitIDs.append(habit.id) }
                                })) {
                                    HStack(spacing: 10) {
                                        HabitIcon(habit: habit, size: 32)
                                        Text(habit.name).font(BuddyFont.text(15)).lineLimit(1)
                                    }
                                }
                                .tint(accent.color).padding(.horizontal, 14).frame(minHeight: 54)
                                .disabled(!challenge.habitIDs.contains(habit.id) && challenge.habitIDs.count >= 20)
                            }
                        }.panel(radius: 15, border: 0.1)
                    }
                    Text("Your challenge starts today. Every selected habit must meet its own goal for a day to count. Past check-ins today already count.")
                        .font(BuddyFont.text(12.5)).foregroundStyle(BuddyStyle.secondaryText(scheme)).fixedSize(horizontal: false, vertical: true)
                }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 100)
            }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        }
        .background(BuddyStyle.canvas(scheme))
        .overlay(alignment: .bottom) {
            PrimaryAction(title: "Save Challenge") {
                challenge.name = challenge.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let saved = challenge
                if store.change({ data in
                    if let index = data.challenges.firstIndex(where: { $0.id == saved.id }) { data.challenges[index] = saved }
                    else { data.challenges.append(saved) }
                }) { dismiss() }
            }.disabled(!valid).padding(.horizontal, 24).padding(.bottom, 6)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).fieldCaption().foregroundStyle(BuddyStyle.secondaryText(scheme)).padding(.leading, 5)
            content()
        }
    }
}

private struct ChallengeDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let challenge: Challenge
    @State private var selectedDay: Day
    @State private var editing: Challenge?
    @State private var editingDay: DaySelection?
    @State private var confirmDelete = false

    init(challenge: Challenge) {
        self.challenge = challenge
        let today = Day()
        _selectedDay = State(initialValue: min(max(today, challenge.start), challenge.end))
    }

    var body: some View {
        let data = store.visible
        let habits = challenge.habitIDs.compactMap { id in data.habits.first { $0.id == id } }
        let tint = BuddyStyle.color(habits.first?.color ?? "violet")
        let stats = ChallengeProgress(challenge: challenge, data: data)
        VStack(spacing: 0) {
            SheetHeader(title: challenge.name, trailingSymbol: "square-pen") {
                editing = store.data.challenges.first { $0.id == challenge.id } ?? challenge
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ExploreSection(title: "PROGRESS", detail: stats.completed ? "You completed every day of this challenge." : "\(stats.completedDays) of \(challenge.duration) challenge days completed.") {
                        VStack(alignment: .leading, spacing: 9) {
                            ProgressView(value: Double(stats.completedDays), total: Double(challenge.duration)).tint(tint)
                            Text("Day \(stats.dayNumber) of \(challenge.duration)").font(BuddyFont.mono(12)).foregroundStyle(BuddyStyle.secondaryText(scheme))
                        }
                    }
                    ExploreSection(title: "CHALLENGE DAYS", detail: "Tap a past day to review or update its habit check-ins.") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 7), spacing: 9) {
                            ForEach(0..<challenge.duration, id: \.self) { index in
                                let day = challenge.start.adding(index)
                                let p = dayProgress(day, habits: habits, data: data)
                                Button { selectedDay = day } label: {
                                    ZStack {
                                        Circle().fill(p.done ? tint.opacity(0.2) : BuddyStyle.field(scheme))
                                        if p.done { Circle().strokeBorder(tint.opacity(0.8), lineWidth: 1.5) }
                                        if day == selectedDay { Circle().strokeBorder(BuddyStyle.text(scheme).opacity(0.65), lineWidth: 1.5).padding(-2) }
                                        Text("\(index + 1)").font(BuddyFont.mono(11, p.done ? .bold : .medium)).foregroundStyle(p.done ? tint : BuddyStyle.secondaryText(scheme))
                                    }.frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                                }.buttonStyle(.plain).disabled(day > Day())
                                    .accessibilityLabel("Day \(index + 1), \(p.done ? "complete" : "incomplete")")
                            }
                        }
                    }
                    ExploreSection(title: selectedDay == Day() ? "TODAY · \(selectedDay.date.formatted(date: .abbreviated, time: .omitted).uppercased())" : selectedDay.date.formatted(date: .complete, time: .omitted).uppercased(), detail: dayProgress(selectedDay, habits: habits, data: data).summary) {
                        if selectedDay > Day() {
                            Text("This challenge day has not started yet.").font(BuddyFont.text(14)).foregroundStyle(BuddyStyle.secondaryText(scheme))
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(habits) { habit in
                                    HabitDayRow(habit: habit, day: selectedDay) { editingDay = $0 }
                                }
                            }
                        }
                    }
                    Button("Delete Challenge", role: .destructive) { confirmDelete = true }
                        .font(BuddyFont.text(15, .medium)).frame(maxWidth: .infinity, minHeight: 48)
                        .panel(radius: 16, border: 0.08)
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 30)
            }.scrollIndicators(.hidden)
        }
        .background(BuddyStyle.canvas(scheme))
        .sheet(item: $editing) { ChallengeEditorView(challenge: $0).buddySheet() }
        .sheet(item: $editingDay) { DayEditorView(selection: $0) }
        .confirmationDialog("Delete \(challenge.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Challenge", role: .destructive) {
                let id = challenge.id
                if store.change({ $0.challenges.removeAll { $0.id == id } }) { dismiss() }
            }
        } message: { Text("Deleting this challenge keeps all habit check-ins and history.") }
    }

    private func dayProgress(_ day: Day, habits: [Habit], data: BuddyData) -> (done: Bool, summary: String) {
        let states = habits.map { Engine.progress($0, day: day, data: data) }
        let done = !states.isEmpty && states.allSatisfy(\.success)
        let ready = states.filter(\.available).count
        let summary = done ? "Every selected habit met its goal." : "\(states.filter(\.success).count) of \(states.count) selected habits complete."
        return (done, ready == 0 ? "No selected habits are active on this date." : summary)
    }
}
