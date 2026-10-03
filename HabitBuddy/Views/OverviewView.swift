import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @State private var path: [UUID] = []
    @State private var editor: Habit?
    @State private var appearance: Habit?
    @State private var notes: Habit?
    @State private var share: Habit?
    @State private var visualRouted = false
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
                VStack(spacing: 12) {
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
                        if store.data.settings.showCategoryFilter && !store.data.categories.isEmpty { categoryFilter }
                        switch store.data.settings.layout {
                        case .cards: LazyVStack(spacing: 12) { ForEach(habits) { habit in card(habit) } }
                        case .compact: compact
                        case .month: monthGrid
                        }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 100)
            }
            .background(BuddyStyle.canvas(scheme))
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                HStack {
                    CircleControl(symbol: "gearshape", label: "Settings") { settings = true }
                    Spacer()
                    CircleControl(symbol: "chart.xyaxis.line", label: "Statistics") { stats = true }
                    CircleControl(symbol: "plus", label: "Create Habit", filled: true) { editor = Habit(name: "") }
                }.padding(.horizontal, 12).padding(.vertical, 4).background(BuddyStyle.canvas(scheme))
            }
            .safeAreaInset(edge: .bottom) { if store.data.settings.showLayoutSwitcher { layoutSwitcher } }
            .navigationDestination(for: UUID.self) { HabitDetailView(id: $0) }
            .sheet(item: $editor) { HabitEditorView(habit: $0) }
            .sheet(item: $appearance) { HabitAppearanceView(habitID: $0.id) }
            .sheet(item: $notes) { NotesView(habitID: $0.id) }
            .sheet(item: $share) { ShareHabitView(habit: $0) }
            .task { visualRoute() }
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
        HabitCard(habit:habit,data:store.data,onOpen:{path.append(habit.id)},onComplete:{tap(habit,Day())})
            .contextMenu { habitMenu(habit) }
            .modifier(HabitDrag(id:habit.id,enabled:store.data.settings.dragToReorder) { source in
                var ids=store.data.active.map(\.id)
                guard let from=ids.firstIndex(of:source),let to=ids.firstIndex(of:habit.id),from != to else{return}
                ids.remove(at:from);ids.insert(source,at:to)
                store.change { data in for (n,id) in ids.enumerated(){if let i=data.habits.firstIndex(where:{$0.id==id}){data.habits[i].order=n}} }
            })
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
        return VStack(spacing: 12) {
            HStack { Text("Last \(days.count) days").font(.system(size:12)).padding(.horizontal,10).padding(.vertical,8).background(Color.primary.opacity(0.05),in:Capsule());Spacer();Text("\(days.first!.rawValue.suffix(5)) – \(days.last!.rawValue.suffix(5))").font(.system(size:9,design:.monospaced)).foregroundStyle(.secondary) }
            VStack(spacing:2) {
            HStack {
                Text("\(habits.count) HABITS").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                ForEach(days) { day in VStack(spacing:3){Text(String(Calendar.current.shortWeekdaySymbols[day.weekday-1].prefix(2)));Text(String(Int(day.rawValue.suffix(2))!))}.font(.system(size:9,design:.monospaced)).foregroundStyle(day==Day() ? Color.primary:Color.secondary).frame(width:28) }
            }.padding(.bottom, 8)
            ForEach(habits) { habit in
                HStack(spacing: 5) {
                    Button { path.append(habit.id) } label: {
                        HStack(spacing: 7) { HabitIcon(habit: habit, size: 28); if store.data.settings.compactNames { Text(habit.name).font(.system(size:11)).lineLimit(1) }.foregroundStyle(.primary) }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                    ForEach(days) { day in
                        Button { tap(habit, day) } label: { DayTile(habit: habit, day: day, data: store.data, size: 28).frame(height:44) }
                            .buttonStyle(.plain).disabled(!habit.available(on: day, today: Day()))
                            .contextMenu { Button("Edit amount and note") { daySelection = DaySelection(habit: habit, day: day) } }
                    }
                }.frame(minHeight:44).contextMenu { habitMenu(habit) }
                if habit.id != habits.last?.id { Divider().opacity(0.3) }
            }
        }.surface(padding:12,radius:20)
        }
    }
    private var monthNavigation: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month")
            Spacer(); Text(month.monthTitle).font(.subheadline.weight(.semibold)); Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }.disabled(month.month >= Day().month).accessibilityLabel("Next month")
        }.padding(.horizontal, 7)
    }
    private var monthGrid: some View {
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:3),spacing:10) {
            ForEach(habits) { habit in MonthHabitCard(habit:habit,data:store.data,onOpen:{path.append(habit.id)}).contextMenu{habitMenu(habit)} }
        }
    }
    @ViewBuilder private func habitMenu(_ habit: Habit) -> some View {
        Button("Edit Habit", systemImage: "pencil") { editor = habit }
        Button("Appearance",systemImage:"slider.horizontal.3"){appearance=habit}
        Button("Share Habit",systemImage:"square.and.arrow.up"){share=habit}
        if store.data.settings.notes { Button("Notes",systemImage:"note.text"){notes=habit} }
        Button("Reorder Habits",systemImage:"arrow.up.arrow.down"){reorder=true}
        Button("Edit Today", systemImage: "calendar") { daySelection = DaySelection(habit: habit, day: Day()) }
        Button("Complete Yesterday", systemImage: "checkmark") { store.change { try Engine.complete(habit.id, day: Day().adding(-1), data: &$0) } }.disabled(!habit.available(on: Day().adding(-1), today: Day()))
        Button("Uncomplete Yesterday", systemImage: "eraser") { store.setAmount(0, habit.id, Day().adding(-1)) }.disabled(!habit.available(on: Day().adding(-1), today: Day()))
        Button("Archive", systemImage: "archivebox") { store.archive(habit.id) }
    }
    private func shiftMonth(_ delta: Int) { month = Day(Day.calendar.date(byAdding: .month, value: delta, to: month.date)!, timeZone: TimeZone(secondsFromGMT: 0)!) }
    private func loadSamples() { store.change { VisualSamples.populate(&$0) } }
    private func visualRoute() {
        #if DEBUG
        guard !visualRouted,let screen=ProcessInfo.processInfo.environment["BUDDY_VISUAL_SCREEN"] else{return}
        visualRouted=true
        guard let habit=store.data.active.first else{return}
        switch screen {
        case "detail":path=[habit.id]
        case "editor":editor=habit
        case "new-habit":editor=Habit(name:"")
        case "statistics":stats=true
        case "settings":settings=true
        case "share":share=habit
        case "appearance":appearance=habit
        case "notes":notes=habit
        case "day":daySelection=DaySelection(habit:habit,day:Day())
        default:break
        }
        #endif
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
            ForEach(Day.range(first, first.adding(41))) { day in
                let p = Engine.progress(habit, day: day, data: data)
                RoundedRectangle(cornerRadius: 2).fill(BuddyStyle.color(habit.color).opacity(p.success && day.month == month.month ? 1 : 0.12)).aspectRatio(1, contentMode: .fit)
                    .opacity(day.month == month.month ? 1 : 0.12)
            }
        }.frame(minHeight: 85, alignment: .top)
    }
}

struct MonthHabitCard: View {
    let habit:Habit
    let data:BuddyData
    var onOpen:()->Void
    @State private var month=Day().startOfMonth
    var body:some View {
        Button(action:onOpen) {
            VStack(alignment:.leading,spacing:8) {
                HStack(spacing:5){HabitIcon(habit:habit,size:24);VStack(alignment:.leading,spacing:2){Text(habit.name).font(.system(size:10,weight:.medium)).lineLimit(1);Text(month.monthTitle).font(.system(size:8)).foregroundStyle(.secondary)}}
                MiniMonth(habit:habit,data:data,month:month)
            }.foregroundStyle(.primary).surface(padding:9,radius:16)
        }.buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance:30).onEnded{v in if abs(v.translation.width)>abs(v.translation.height){shift(v.translation.width>0 ? -1:1)}})
        .accessibilityAction(named:"Previous month"){shift(-1)}.accessibilityAction(named:"Next month"){shift(1)}
    }
    private func shift(_ n:Int){let m=month.addingMonths(n);if m<=Day().startOfMonth && m>=habit.created.startOfMonth{month=m}}
}
struct HabitDrag: ViewModifier {
    let id:UUID
    let enabled:Bool
    let move:(UUID)->Void
    @ViewBuilder func body(content:Content)->some View {
        if enabled{content.draggable(id.uuidString).dropDestination(for:String.self){items,_ in guard let first=items.first,let source=UUID(uuidString:first) else{return false};move(source);return true}}
        else{content}
    }
}
extension Day {
    func addingMonths(_ n:Int)->Day { Day(Self.calendar.date(byAdding:.month,value:n,to:date)!,timeZone:TimeZone(secondsFromGMT:0)!) }
    var noteTitle:String { if self==Day(){return "Today"};let f=DateFormatter();f.timeZone=TimeZone(secondsFromGMT:0);f.dateFormat="EEE, MMM d, yyyy";return f.string(from:date) }
}
