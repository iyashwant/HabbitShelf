import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @State private var path: [UUID] = []
    @State private var editor: Habit?
    @State private var daySelection: DaySelection?
    @State private var settings = false
    @State private var stats = false
    @State private var reorder = false
    @State private var category: UUID?
    @State private var month = Day().startOfMonth
    private var habits: [Habit] { store.data.active.filter { category == nil || $0.categories.contains(category!) } }
    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
                    if !store.loaded {
                        ContentUnavailableView("Your data needs attention", systemImage: "externaldrive.badge.exclamationmark", description: Text(store.error ?? "Open Settings to restore a backup."))
                    } else if habits.isEmpty {
                        ContentUnavailableView {
                            Label(category == nil ? "Make a little progress" : "No habits here yet", systemImage: "square.grid.3x3.fill")
                        } description: { Text("Build the habits that matter. One day at a time.") } actions: {
                            Button("Create Habit") { editor = Habit(name: "") }.buttonStyle(.borderedProminent)
                            if store.data.habits.isEmpty { Button("Try sample habits") { loadSamples() } }
                        }.padding(.top, 70)
                    } else {
                        categoryFilter
                        if store.data.settings.layout == .month { monthNavigation }
                        switch store.data.settings.layout {
                        case .cards: LazyVStack(spacing: 14) { ForEach(habits) { habit in card(habit) } }
                        case .compact: compact
                        case .month: monthGrid
                        }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 100)
            }
            .background(scheme == .dark ? Color(white: 0.04) : Color.white)
            .navigationTitle("Habit Buddy").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings") }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { stats = true } label: { Image(systemName: "chart.xyaxis.line") }.accessibilityLabel("Statistics")
                    Button { editor = Habit(name: "") } label: { Image(systemName: "plus").fontWeight(.semibold) }.buttonStyle(.borderedProminent).buttonBorderShape(.circle).accessibilityLabel("Create Habit")
                }
            }
            .safeAreaInset(edge: .bottom) { layoutSwitcher }
            .navigationDestination(for: UUID.self) { HabitDetailView(id: $0) }
            .sheet(item: $editor) { HabitEditorView(habit: $0) }
            .sheet(item: $daySelection) { DayEditorView(selection: $0) }
            .sheet(isPresented: $settings) { SettingsView() }
            .sheet(isPresented: $stats) { StatisticsView() }
            .sheet(isPresented: $reorder) { ReorderView() }
            .fullScreenCover(isPresented: Binding(get: { store.loaded && !store.data.settings.onboarding }, set: { _ in })) { WelcomeView() }
            .alert("Couldn’t complete the action", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.reload(); Task { await NotificationService.reconcile(store.data) } }
            }
            .onOpenURL { url in
                guard url.scheme == "habitbuddy", let text = url.host, let id = UUID(uuidString: text), store.habit(id)?.archived == nil else { return }
                path = [id]
                if let key = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "day" })?.value,
                   let day = Day(rawValue: key), let h = store.habit(id), h.available(on: day, today: Day()) {
                    daySelection = DaySelection(habit: h, day: day)
                }
            }
        }
    }
    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Button("All Habits") { category = nil }.buttonStyle(.bordered).tint(category == nil ? BuddyStyle.purple : .secondary)
                ForEach(store.data.categories) { item in
                    Button { category = item.id } label: { Label(item.name, systemImage: item.symbol) }
                        .buttonStyle(.bordered).tint(category == item.id ? BuddyStyle.purple : .secondary)
                }
                Button { reorder = true } label: { Image(systemName: "arrow.up.arrow.down") }.buttonStyle(.bordered).accessibilityLabel("Reorder habits")
            }.font(.caption)
        }
    }
    private var layoutSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(Layout.allCases, id: \.self) { layout in
                Button { store.change { $0.settings.layout = layout } } label: {
                    Image(systemName: layout == .cards ? "square.grid.3x3.fill" : layout == .compact ? "checklist" : "calendar")
                        .font(.system(size: 19)).frame(width: 45, height: 40)
                        .background(store.data.settings.layout == layout ? Color.primary.opacity(0.12) : .clear, in: Capsule())
                }.buttonStyle(.plain).accessibilityLabel("\(layout.rawValue) view")
                    .accessibilityAddTraits(store.data.settings.layout == layout ? .isSelected : [])
            }
        }.padding(5).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 10)
    }
    private func card(_ habit: Habit) -> some View {
        let stats = Engine.stats(habit, data: store.data)
        let color = BuddyStyle.color(habit.color)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Button { path.append(habit.id) } label: {
                    HStack(spacing: 11) {
                        HabitIcon(habit: habit)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(habit.name).font(.headline).foregroundStyle(.primary)
                            if store.data.settings.showDescriptions && !habit.detail.isEmpty { Text(habit.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                if store.data.settings.showCompletionIndicator { completionButton(habit) }
            }
            Button { path.append(habit.id) } label: { Heatmap(habit: habit, data: store.data) }.buttonStyle(.plain)
            HStack {
                if store.data.settings.showStreak && habit.currentGoal.cadence != .none { MetricChip(symbol: "flame.fill", text: String(stats.currentStreak), color: color) }
                if store.data.settings.showGoal { MetricChip(symbol: "target", text: habit.currentGoal.summary, color: color) }
                Spacer()
                if habit.currentGoal.tracking != .yesNo { Text("\(Amount.text(store.data.record(habit.id, Day()).amount)) / \(Amount.text(habit.currentGoal.target)) \(habit.currentGoal.unit)").font(.caption2).foregroundStyle(.secondary) }
            }
        }.surface().contextMenu { habitMenu(habit) }
    }
    private func completionButton(_ habit: Habit) -> some View {
        return Button { tap(habit, Day()) } label: {
            CompletionBadge(habit: habit, data: store.data)
        }.buttonStyle(.plain).accessibilityLabel(habit.currentGoal.mode == .quit ? "Log or clear a slip for \(habit.name)" : "Log progress for \(habit.name)")
    }
    private func tap(_ habit: Habit, _ day: Day) {
        let goal = habit.goal(on: day), p = Engine.progress(habit, day: day, data: store.data)
        if goal.tracking == .yesNo || (goal.tap == .addOne && !p.success && goal.mode == .build) { store.quickLog(habit, day: day) }
        else { daySelection = DaySelection(habit: habit, day: day) }
    }
    private var compact: some View {
        let days = Day.range(Day().adding(-(store.data.settings.recentDays - 1)), Day())
        return VStack(spacing: 2) {
            HStack {
                Text("\(habits.count) HABITS").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                ForEach(days) { day in Text(String(day.rawValue.suffix(2))).font(.caption2).foregroundStyle(.secondary).frame(width: 28) }
            }.padding(.bottom, 8)
            ForEach(habits) { habit in
                HStack(spacing: 5) {
                    Button { path.append(habit.id) } label: {
                        HStack(spacing: 7) { HabitIcon(habit: habit, size: 28); Text(habit.name).font(.caption).lineLimit(1).foregroundStyle(.primary) }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                    ForEach(days) { day in
                        Button { tap(habit, day) } label: { DayTile(habit: habit, day: day, data: store.data, size: 28) }
                            .buttonStyle(.plain).disabled(!habit.available(on: day, today: Day()))
                            .contextMenu { Button("Edit amount and note") { daySelection = DaySelection(habit: habit, day: day) } }
                    }
                }.padding(.vertical, 7).contextMenu { habitMenu(habit) }
                if habit.id != habits.last?.id { Divider().opacity(0.3) }
            }
        }.surface()
    }
    private var monthNavigation: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month")
            Spacer(); Text(month.monthTitle).font(.subheadline.weight(.semibold)); Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }.disabled(month.month >= Day().month).accessibilityLabel("Next month")
        }.padding(.horizontal, 7)
    }
    private var monthGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 102), spacing: 10)], spacing: 10) {
            ForEach(habits) { habit in
                Button { path.append(habit.id) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 5) { HabitIcon(habit: habit, size: 25); Text(habit.name).font(.caption2.weight(.medium)).foregroundStyle(.primary).lineLimit(1) }
                        MiniMonth(habit: habit, data: store.data, month: month)
                    }.padding(10).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).contextMenu { habitMenu(habit) }
            }
        }
    }
    @ViewBuilder private func habitMenu(_ habit: Habit) -> some View {
        Button("Edit Habit", systemImage: "pencil") { editor = habit }
        Button("Edit Today", systemImage: "calendar") { daySelection = DaySelection(habit: habit, day: Day()) }
        Button("Complete Yesterday", systemImage: "checkmark") { store.change { try Engine.complete(habit.id, day: Day().adding(-1), data: &$0) } }.disabled(!habit.available(on: Day().adding(-1), today: Day()))
        Button("Clear Yesterday", systemImage: "eraser") { store.setAmount(0, habit.id, Day().adding(-1)) }.disabled(!habit.available(on: Day().adding(-1), today: Day()))
        Button("Archive", systemImage: "archivebox") { store.archive(habit.id) }
    }
    private func shiftMonth(_ delta: Int) { month = Day(Day.calendar.date(byAdding: .month, value: delta, to: month.date)!, timeZone: TimeZone(secondsFromGMT: 0)!) }
    private func loadSamples() {
        store.change { data in
            for (name, symbol, color, offset) in [("Read", "book.closed.fill", "cyan", 0), ("Gym Day", "dumbbell.fill", "mint", 1), ("Journal", "pencil.tip", "yellow", 2)] {
                var h = Habit(name: name, created: Day().adding(-90)); h.symbol = symbol; h.color = color; h.order = offset
                h.goals[0].cadence = .daily
                if offset == 1 { h.goals[0].cadence = .weekly; h.goals[0].days = 3 }
                data.habits.append(h)
                for n in 1...90 where (n + offset) % 5 != 0 {
                    var r = Record(habitID: h.id, day: Day().adding(-n)); r.amount = 1_000; data.records[r.key] = r
                }
            }
        }
    }
}

extension Day {
    var monthTitle: String {
        let f = DateFormatter(); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "MMM yyyy"
        return f.string(from: date)
    }
    var localDate: Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: date.addingTimeInterval(12 * 3_600))
        let parts = rawValue.split(separator: "-").map { Int($0)! }
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]; c.hour = 12
        return Calendar.current.date(from: c)!
    }
}
struct MiniMonth: View {
    let habit: Habit
    let data: BuddyData
    let month: Day
    var body: some View {
        let first = month.startOfWeek(data.settings.weekStart)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
            ForEach(Day.range(first, month.endOfMonth)) { day in
                let p = Engine.progress(habit, day: day, data: data)
                RoundedRectangle(cornerRadius: 2).fill(BuddyStyle.color(habit.color).opacity(p.success && day.month == month.month ? 1 : 0.12)).aspectRatio(1, contentMode: .fit)
                    .opacity(day.month == month.month ? 1 : 0)
            }
        }.frame(minHeight: 85, alignment: .top)
    }
}
