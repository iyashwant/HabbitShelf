import SwiftUI

/// Groups of habits checked off together, such as a morning routine.
struct RoutinesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent
    @State private var editing: Routine?
    @State private var open: Routine?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if store.visible.routines.isEmpty {
                    ContentUnavailableView {
                        Label("No routines yet", systemImage: "list.bullet.rectangle")
                    } description: { Text("Group habits you do together, like a morning routine, and check them all off with one tap.") } actions: {
                        Button("Create Routine") { editing = Routine(name: "") }.buttonStyle(.borderedProminent).foregroundStyle(accent.foreground).disabled(store.visible.active.isEmpty)
                    }.padding(.top, 40)
                }
                ForEach(store.visible.routines) { routine in RoutineCard(routine: routine) { open = routine } }
                if !store.visible.routines.isEmpty { Text("Complete All checks off every open build habit in the routine. Quit habits and counts above their goal are left as they are.").font(BuddyFont.text(12.5)).foregroundStyle(BuddyStyle.tertiaryText(scheme)).padding(.horizontal, 6) }
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(BuddyStyle.canvas(scheme)).toolbar(.hidden, for: .navigationBar)
        .topBar { PageBar(title: "Routines", trailing: "plus", trailingLabel: "New Routine", trailingAction: { editing = Routine(name: "") }) { dismiss() } }
        .sheet(item: $editing) { RoutineEditorView(routine: $0).buddySheet() }
        .sheet(item: $open) { RoutineSheet(routineID: $0.id).buddySheet(partial: true).presentationDetents([.medium, .large]) }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["BUDDY_VISUAL_SCREEN"] == "routine", let first = store.data.routines.first { open = first }
            #endif
        }
    }
}

struct RoutineCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let routine: Routine
    var open: () -> Void
    var body: some View {
        let progress = Engine.routineProgress(routine, data: store.visible), color = BuddyStyle.color(routine.color)
        let habits = routine.habitIDs.compactMap { store.visible.activeHabit($0) }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                BuddyGlyph(symbol: routine.symbol, size: 24).foregroundStyle(color).frame(width: 46, height: 46).background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .circular))
                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.name).font(BuddyFont.text(17.3, .semibold)).foregroundStyle(BuddyStyle.text(scheme)).lineLimit(1)
                    Text(progress.total == 0 ? "No active habits" : progress.done == progress.total ? "All \(progress.total) done today" : "\(progress.done) of \(progress.total) done today")
                        .font(BuddyFont.text(13)).foregroundStyle(BuddyStyle.secondaryText(scheme)).accessibilityIdentifier("routine-progress")
                }
                Spacer(minLength: 8)
                CompleteAllButton(routine: routine, compact: true)
            }
            HStack(spacing: 6) {
                ForEach(habits) { h in
                    let done = Engine.progress(h, day: Day(), data: store.data).success
                    HabitIcon(habit: h, size: 30).opacity(done ? 1 : 0.45).overlay(alignment: .bottomTrailing) {
                        if done { LucideIcon("check", size: 10).foregroundStyle(.black.opacity(0.8)).frame(width: 14, height: 14).background(BuddyStyle.color(h.color), in: Circle()).offset(x: 3, y: 3) }
                    }
                }
            }
        }
        .padding(15).surface(padding: 0, radius: 24, tint: color)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .circular)).onTapGesture(perform: open)
        .accessibilityElement(children: .contain).accessibilityAction(named: "Open \(routine.name)", open)
    }
}

/// Completes every open build habit in a routine today.
struct CompleteAllButton: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accent) private var accent
    let routine: Routine
    var compact = false
    var body: some View {
        let progress = Engine.routineProgress(routine, data: store.visible), done = progress.done == progress.total
        let action = { withAnimation(.snappy(duration: 0.22)) { _ = store.log(Set(routine.habitIDs)) { try Engine.completeRoutine(routine.id, day: Day(), data: &$0) } } }
        Group {
            if compact {
                Button(action: action) {
                    HStack(spacing: 5) { LucideIcon("check-check", size: 16); Text(done ? "Done" : "All").font(BuddyFont.text(14, .semibold)) }
                        .foregroundStyle(done ? BuddyStyle.color(routine.color) : accent.foreground).padding(.horizontal, 13).frame(height: 36)
                        .background(done ? BuddyStyle.color(routine.color).opacity(0.14) : accent.color, in: Capsule())
                }.buttonStyle(.plain)
            } else { PrimaryAction(title: done ? "All Done" : "Complete All", symbol: "check-check", action: action) }
        }
        .disabled(done || progress.total == 0)
        .accessibilityLabel("Complete All in \(routine.name)")
    }
}

/// A routine's habits with their checks, for checking them off one at a time or all at once.
struct RoutineSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.glass) private var glass
    let routineID: UUID
    @State private var editing: DaySelection?
    @State private var editor: Routine?
    var body: some View {
        VStack(spacing: 0) {
            if let routine = store.visible.routines.first(where: { $0.id == routineID }) {
                let habits = routine.habitIDs.compactMap { store.visible.activeHabit($0) }, progress = Engine.routineProgress(routine, data: store.visible)
                SheetHeader(title: routine.name, trailingSymbol: "square-pen") { editor = routine }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        Text("\(progress.done) of \(progress.total) done today").font(BuddyFont.text(14)).foregroundStyle(BuddyStyle.secondaryText(scheme)).padding(.leading, 4)
                        ForEach(habits) { habit in HabitDayRow(habit: habit, day: Day()) { editing = $0 } }
                    }.padding(.horizontal, 16).padding(.bottom, 100)
                }.scrollIndicators(.hidden)
                .overlay(alignment: .bottom) { CompleteAllButton(routine: routine).padding(.horizontal, 24).padding(.bottom, 6) }
            } else { ContentUnavailableView("Routine deleted", systemImage: "trash") }
        }
        // With Liquid Glass the half-height sheet shows iOS's glass (see `BuddySheet`).
        .background(BuddyStyle.canvas(scheme).opacity(glass == nil ? 1 : 0))
        .sheet(item: $editing) { DayEditorView(selection: $0) }
        .sheet(item: $editor) { RoutineEditorView(routine: $0).buddySheet() }
    }
}

struct RoutineEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent
    @State var routine: Routine
    @State private var icons = false
    @State private var confirmDelete = false
    private var existing: Bool { store.data.routines.contains { $0.id == routine.id } }
    var body: some View {
        let valid = !routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !routine.habitIDs.isEmpty
        VStack(spacing: 0) {
            SheetHeader(title: existing ? "Edit Routine" : "New Routine")
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Button { icons = true } label: {
                        BuddyGlyph(symbol: routine.symbol, size: 40).foregroundStyle(BuddyStyle.color(routine.color)).frame(width: 88, height: 88).background(BuddyStyle.color(routine.color).opacity(0.14), in: Circle())
                    }.buttonStyle(.plain).frame(maxWidth: .infinity).accessibilityLabel("Choose Routine Icon")
                    caption("Name") { TextField("", text: $routine.name, prompt: Text("Morning, Evening, Gym…")).accessibilityLabel("Routine name").buddyField() }
                    caption("Color") { ColorPalette(selection: $routine.color) }
                    caption("Habits") {
                        VStack(spacing: 0) {
                            ForEach(store.visible.active) { habit in
                                Toggle(isOn: Binding(get: { routine.habitIDs.contains(habit.id) }, set: { on in routine.habitIDs.removeAll { $0 == habit.id }; if on { routine.habitIDs.append(habit.id) } })) {
                                    HStack(spacing: 10) { HabitIcon(habit: habit, size: 32); Text(habit.name).font(BuddyFont.text(15)).lineLimit(1) }
                                }.tint(accent.color).padding(.horizontal, 14).frame(height: 54)
                            }
                        }.panel(radius: 15, border: 0.1)
                    }
                    if existing {
                        Button(role: .destructive) { confirmDelete = true } label: { Text("Delete Routine").font(BuddyFont.text(15, .medium)).frame(maxWidth: .infinity, minHeight: 44) }
                        Text("Deleting a routine keeps its habits and their history.").font(BuddyFont.text(12)).foregroundStyle(BuddyStyle.tertiaryText(scheme))
                    }
                }.padding(.horizontal, 16).padding(.bottom, 110)
            }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        }
        .background(BuddyStyle.canvas(scheme))
        .overlay(alignment: .bottom) {
            PrimaryAction(title: "Save") {
                routine.name = routine.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let saved = routine
                if store.change({ data in if let i = data.routines.firstIndex(where: { $0.id == saved.id }) { data.routines[i] = saved } else { data.routines.append(saved) } }) { dismiss() }
            }.disabled(!valid).padding(.horizontal, 24).padding(.bottom, 6)
        }
        .sheet(isPresented: $icons) { IconPickerView(selection: $routine.symbol, color: BuddyStyle.color(routine.color)).buddySheet() }
        .confirmationDialog("Delete \(routine.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Routine", role: .destructive) { let id = routine.id; if store.change({ data in data.routines.removeAll { $0.id == id } }) { dismiss() } }
        }
    }
    private func caption<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).fieldCaption().foregroundStyle(BuddyStyle.secondaryText(scheme)).padding(.leading, 5); content() }
    }
}

/// Routine chips above the overview. Tapping one opens its habits.
struct RoutineStrip: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    var open: (Routine) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.visible.routines) { routine in
                    let progress = Engine.routineProgress(routine, data: store.visible), done = progress.total > 0 && progress.done == progress.total
                    Button { open(routine) } label: {
                        HStack(spacing: 7) {
                            BuddyGlyph(symbol: routine.symbol, size: 15).foregroundStyle(BuddyStyle.color(routine.color))
                            Text(routine.name).font(BuddyFont.text(14, .medium)).foregroundStyle(BuddyStyle.text(scheme)).lineLimit(1)
                            Text("\(progress.done)/\(progress.total)").font(BuddyFont.mono(11.5)).foregroundStyle(done ? BuddyStyle.color(routine.color) : BuddyStyle.secondaryText(scheme))
                        }
                        .padding(.horizontal, 13).frame(height: 38)
                        .background(done ? BuddyStyle.color(routine.color).opacity(0.13) : BuddyStyle.field(scheme), in: Capsule())
                        .overlay { Capsule().strokeBorder(done ? BuddyStyle.color(routine.color).opacity(0.5) : BuddyStyle.border(scheme, 0.1), lineWidth: 1) }
                    }.buttonStyle(.plain).accessibilityLabel("\(routine.name), \(progress.done) of \(progress.total) done")
                }
            }.padding(.horizontal, 2)
        }
    }
}
