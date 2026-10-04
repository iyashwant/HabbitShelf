import SwiftUI

/// Every habit on one month: each day shows a dot per completed habit, shaded by the share done.
struct HabitsCalendarView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent
    @State private var month = Day().startOfMonth
    @State private var selected: Day?
    var body: some View {
        let today = Day(), habits = store.visible.active, weekStart = store.data.settings.weekStart
        let first = month.startOfMonth, offset = (first.weekday - weekStart + 7) % 7, count = first.distance(to: first.endOfMonth) + 1
        let earliest = habits.map(\.created).min() ?? today, model = MonthModel(habits: habits, data: store.visible, first: first, count: count, today: today)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(month.monthTitle).font(BuddyFont.text(22, .heavy)).foregroundStyle(BuddyStyle.text(scheme))
                    Spacer()
                    MonthArrow(next: false) { month = month.addingMonths(-1) }.disabled(month <= earliest.startOfMonth)
                    MonthArrow(next: true) { month = month.addingMonths(1) }.disabled(month >= today.startOfMonth)
                }
                VStack(spacing: 6) {
                    HStack(spacing: 6) { ForEach(0..<7, id: \.self) { i in Text(Heatmap.weekday(weekStart, i)).font(BuddyFont.mono(11)).foregroundStyle(BuddyStyle.tertiaryText(scheme)).frame(maxWidth: .infinity) } }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                        // Leading blanks take negative IDs so they never share an identity with a day.
                        ForEach(-offset..<0, id: \.self) { _ in Color.clear.frame(height: 64) }
                        ForEach(0..<count, id: \.self) { n in
                            let day = first.adding(n)
                            Button { selected = day } label: { cell(day, model.days[n], today) }.buttonStyle(FlatButtonStyle()).disabled(day > today)
                        }
                    }
                }.padding(12).panel(radius: 22, border: 0.09)
                summary(model)
                if !habits.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Habits").fieldCaption().foregroundStyle(BuddyStyle.secondaryText(scheme))
                        FlowLayout(spacing: 8) {
                            ForEach(habits) { h in
                                HStack(spacing: 6) { Circle().fill(BuddyStyle.color(h.color)).frame(width: 8, height: 8); Text(h.name).font(BuddyFont.text(13)).foregroundStyle(BuddyStyle.text(scheme)).lineLimit(1) }
                                    .padding(.horizontal, 10).frame(height: 30).background(BuddyStyle.field(scheme), in: Capsule())
                            }
                        }
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(BuddyStyle.canvas(scheme)).toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { PageBar(title: "Calendar") { dismiss() } }
        .sheet(item: $selected) { DayHabitsView(day: $0).buddySheet().presentationDetents([.medium, .large]) }
    }
    /// One pass over the month for both the day cells and the summary.
    private struct MonthModel {
        var days: [(tracked: Int, done: [Habit])] = []
        var perfect = 0, kept = DayRate()
        init(habits: [Habit], data: BuddyData, first: Day, count: Int, today: Day) {
            for n in 0..<count {
                let day = first.adding(n), tracked = habits.filter { $0.available(on: day, today: today) }
                var done: [Habit] = []
                for habit in tracked {
                    let p = Engine.progress(habit, day: day, data: data, today: today)
                    kept.add(p, today: day == today)
                    if p.success { done.append(habit) }
                }
                if !tracked.isEmpty && done.count == tracked.count { perfect += 1 }
                days.append((tracked.count, done))
            }
        }
    }
    private func cell(_ day: Day, _ counts: (tracked: Int, done: [Habit]), _ today: Day) -> some View {
        let done = counts.done, tracked = counts.tracked
        let share = tracked == 0 ? 0 : Double(done.count) / Double(tracked), shape = RoundedRectangle(cornerRadius: 12, style: .circular)
        return VStack(spacing: 5) {
            Text(String(Int(day.rawValue.suffix(2))!)).font(BuddyFont.mono(13, day == today ? .semibold : .regular))
                .foregroundStyle(day > today ? BuddyStyle.text(scheme).opacity(0.2) : BuddyStyle.text(scheme))
            // Up to six dots in two rows; more completions show as a count.
            VStack(spacing: 3) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { col in
                            let n = row * 3 + col
                            if n < done.count && !(n == 5 && done.count > 6) { Circle().fill(BuddyStyle.color(done[n].color)).frame(width: 6, height: 6) }
                            else if n == 5 && done.count > 6 { Text("+").font(.system(size: 8, weight: .bold)).foregroundStyle(BuddyStyle.secondaryText(scheme)).frame(width: 6, height: 6) }
                            else { Color.clear.frame(width: 6, height: 6) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity).frame(height: 64)
        .background(accent.color.opacity(share * (scheme == .dark ? 0.24 : 0.18)), in: shape)
        .overlay { if day == today { shape.strokeBorder(accent.color, lineWidth: 1.5) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Day.longDay.string(from: day.date)), \(day > today ? "upcoming" : "\(done.count) of \(tracked) habits done")")
    }
    private func summary(_ model: MonthModel) -> some View {
        let perfect = model.perfect, kept = model.kept
        return HStack(spacing: 10) {
            stat("\(perfect)", perfect == 1 ? "Perfect day" : "Perfect days")
            stat(kept.eligible == 0 ? "–" : "\(Int((kept.rate * 100).rounded()))%", "Habit days kept")
            stat("\(kept.done)", "Check-ins")
        }
    }
    private func stat(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(BuddyFont.text(22, .heavy)).monospacedDigit().foregroundStyle(BuddyStyle.text(scheme))
            Text(title).font(BuddyFont.text(12)).foregroundStyle(BuddyStyle.secondaryText(scheme)).lineLimit(1).minimumScaleFactor(0.8)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).panel(radius: 16, border: 0.09)
    }
}

/// All habits tracked on one day, each with its own check, for logging or backfilling that day.
struct DayHabitsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme
    let day: Day
    @State private var editing: DaySelection?
    var body: some View {
        let today = Day(), habits = store.visible.active.filter { $0.available(on: day, today: today) }
        let done = habits.filter { Engine.progress($0, day: day, data: store.data, today: today).success }.count
        VStack(spacing: 0) {
            SheetHeader(title: day == today ? "Today" : Day.longDay.string(from: day.date))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Text(habits.isEmpty ? "No habits were tracked on this day." : "\(done) of \(habits.count) habits done").font(BuddyFont.text(14)).foregroundStyle(BuddyStyle.secondaryText(scheme)).padding(.leading, 4)
                    ForEach(habits) { habit in HabitDayRow(habit: habit, day: day) { editing = $0 } }
                }.padding(.horizontal, 16).padding(.bottom, 30)
            }.scrollIndicators(.hidden)
        }
        .background(BuddyStyle.canvas(scheme))
        .sheet(item: $editing) { DayEditorView(selection: $0) }
    }
}

/// A habit with its goal and a check for one day. Yes/no and add-one habits log in place; others open the day editor.
struct HabitDayRow: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme
    let habit: Habit
    let day: Day
    var edit: (DaySelection) -> Void
    var body: some View {
        let p = Engine.progress(habit, day: day, data: store.data), goal = habit.goal(on: day)
        HStack(spacing: 12) {
            HabitIcon(habit: habit, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name).font(BuddyFont.text(16, .semibold)).foregroundStyle(BuddyStyle.text(scheme)).lineLimit(1)
                Text(goal.tracking == .yesNo ? goal.summary : "\(Amount.text(p.amount)) / \(Amount.text(goal.target)) \(goal.unit)").font(BuddyFont.text(12.5)).foregroundStyle(BuddyStyle.secondaryText(scheme)).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { tap(p, goal) } label: { CompletionBadge(habit: habit, data: store.data, day: day, size: 42) }
                .buttonStyle(.plain).disabled(habit.archived != nil)
                .accessibilityLabel("Log progress for \(habit.name)").accessibilityValue(p.success ? "Done" : "Not done")
        }
        .padding(.horizontal, 14).padding(.vertical, 10).panel(radius: 18, border: 0.09)
        .contextMenu { Button("Edit amount and note", systemImage: "square.and.pencil") { edit(DaySelection(habit: habit, day: day)) } }
    }
    private func tap(_ p: Progress, _ goal: Goal) {
        if goal.mode == habit.currentGoal.mode && goal.mode == .build && (goal.tracking == .yesNo || (goal.tap == .addOne && !p.success)) { store.quickLog(habit, day: day) }
        else { edit(DaySelection(habit: habit, day: day)) }
    }
}

/// Wraps its children onto new lines when a row is full.
struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { y += row + spacing; x = 0; row = 0 }
            x += size.width + spacing; row = max(row, size.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; row = max(row, size.height)
        }
    }
}
