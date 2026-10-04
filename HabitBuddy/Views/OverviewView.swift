import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @State private var path: [OverviewRoute] = []
    @State private var editor: Habit?
    @State private var appearance: Habit?
    @State private var notes: Habit?
    @State private var share: Habit?
    @State private var visualRouted = false
    @State private var daySelection: DaySelection?
    @State private var settings = false
    @State private var compactSettings = false
    @State private var stats = false
    @State private var reorder = false
    @State private var routine: Routine?
    @State private var timing = false
    @State private var category: UUID?
    @State private var month = Day().startOfMonth
    private var habits: [Habit] { store.visible.active.filter { category == nil || $0.categories.contains(category!) } }
    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 15) {
                    if store.loading {
                        // Storage is opening; the canvas stays empty rather than showing onboarding or no habits.
                        Color.clear.frame(height: 1)
                    } else if !store.loaded {
                        ContentUnavailableView("Your data needs attention", systemImage: "externaldrive.badge.exclamationmark", description: Text(store.error ?? "Open Settings to restore a backup."))
                    } else if habits.isEmpty {
                        ContentUnavailableView {
                            Label(category == nil ? "Make a little progress" : "No habits here yet", systemImage: "square.grid.3x3.fill")
                        } description: { Text("Build the habits that matter. One day at a time.") } actions: {
                            Button("Create Habit") { editor = .draft() }.buttonStyle(.borderedProminent)
                            if store.data.habits.isEmpty { Button("Try sample habits") { loadSamples() } }
                        }.padding(.top, 70)
                    } else {
                        if store.data.settings.showCategoryFilter && !store.data.categories.isEmpty { categoryFilter }
                        if !store.visible.routines.isEmpty { RoutineStrip { routine = $0 } }
                        switch store.data.settings.layout {
                        case .cards: LazyVStack(spacing: 15.3) { ForEach(habits) { habit in card(habit) } }
                        case .compact: compact
                        case .month: monthGrid
                        case .streaks: streakGrid
                        case .list: streakList
                        }
                    }
                }.padding(.horizontal, 8).padding(.bottom, 110)
            }
            .background(BuddyStyle.canvas(scheme))
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 8) {
                    CircleControl(symbol: "settings", label: "Settings") { settings = true }
                    Spacer()
                    CircleControl(symbol: "compass", label: "Explore") { path.append(.explore) }
                    CircleControl(symbol: "layout-dashboard", label: "Dashboard") { path.append(.dashboard) }
                    CircleControl(symbol: "stats", label: "Statistics") { stats = true }
                    CircleControl(symbol: "plus", label: "Create Habit", filled: true, glyph: 19) { editor = .draft() }
                }.padding(.leading, 7).padding(.trailing, 10).padding(.top, 7).padding(.bottom, 12)
            }
            // The reference fades content (and the top of the controls) into the canvas under the status bar.
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    LinearGradient(colors: [BuddyStyle.canvas(scheme), BuddyStyle.canvas(scheme).opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: proxy.safeAreaInsets.top + 29)
                }.ignoresSafeArea().allowsHitTesting(false)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { if store.data.settings.showLayoutSwitcher { layoutSwitcher } }
            .navigationDestination(for: OverviewRoute.self) { route in
                switch route {
                case .habit(let id): HabitDetailView(id: id)
                case .dashboard: DashboardView { path.append($0) }
                case .explore: ExploreView()
                case .insights: InsightsView()
                case .calendar: HabitsCalendarView()
                case .recap: WeeklyRecapView()
                case .notes: NotesTimelineView()
                case .milestones(let id): MilestonesView(habitID: id)
                case .routines: RoutinesView()
                }
            }
            .sheet(item: $editor) { HabitEditorView(habit: $0).buddySheet() }
            .sheet(item: $appearance) { HabitAppearanceView(habitID: $0.id).buddySheet() }
            .sheet(item: $notes) { NotesView(habitID: $0.id).buddySheet() }
            .sheet(item: $share) { ShareHabitView(habit: $0).buddySheet() }
            .task(id: store.loaded) { visualRoute() }
            .sheet(item: $daySelection) { DayEditorView(selection: $0) }
            .sheet(isPresented: $settings) { SettingsView().buddySheet() }
            .sheet(isPresented: $compactSettings) { CompactListSettingsView() }
            .sheet(isPresented: $stats) { StatisticsView().buddySheet() }
            .sheet(isPresented: $reorder) { ReorderView() }
            .sheet(item: $routine) { RoutineSheet(routineID: $0.id).buddySheet().presentationDetents([.medium, .large]) }
            .sheet(isPresented: $timing) { TimerView().buddySheet() }
            .fullScreenCover(isPresented: Binding(get: { store.loaded && !store.data.settings.onboarding }, set: { _ in })) { WelcomeView() }
            .alert("Couldn’t complete the action", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
            // A Live Activity's Finish button logs from outside the app's store.
            .onReceive(NotificationCenter.default.publisher(for: TimerSessions.changed)) { _ in store.reload() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.reload(reschedule: true) }
                else if phase == .background { store.flushSync() }
            }
            .onOpenURL { url in
                guard url.scheme == "habitbuddy", let text = url.host else { return }
                switch text {
                case "timer": timing = true; return
                case "recap": path = [.recap]; return
                case "today": path = [.calendar]; return
                case "routines": path = [.routines]; return
                default: break
                }
                guard let id = UUID(uuidString: text), store.habit(id)?.archived == nil, store.habit(id)?.isHidden != true else { return }
                path = [.habit(id)]
                if let key = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "day" })?.value,
                   let day = Day(rawValue: key), let h = store.habit(id), h.loggable(on: day, today: Day()) {
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
                    Button { category = item.id } label: { HStack { BuddyGlyph(symbol:item.symbol,size:12);Text(item.name) } }
                        .buttonStyle(.bordered).tint(category == item.id ? BuddyStyle.purple : .secondary)
                }
                Button { reorder = true } label: { LucideIcon("arrow-up-down", size: 14) }.buttonStyle(.bordered).accessibilityLabel("Reorder habits")
            }.font(BuddyFont.text(12))
        }
    }
    private var layoutSwitcher: some View {
        HStack(spacing: 5) {
            ForEach(Layout.allCases, id: \.self) { layout in
                let selected = store.data.settings.layout == layout
                Button { store.change { $0.settings.layout = layout } } label: {
                    LayoutGlyph(layout: layout).foregroundStyle(Color(hex: scheme == .dark ? 0xECECEC : 0x1C1C1E))
                        .frame(width: 48, height: 44)
                        .background { if selected { Capsule().fill(scheme == .dark ? Color(hex: 0x3E3E40) : Color.black.opacity(0.08)).overlay { Capsule().strokeBorder(scheme == .dark ? Color(hex: 0x545456) : Color.black.opacity(0.08), lineWidth: 1) } } }
                        .contentShape(Capsule())
                }.buttonStyle(.plain).accessibilityLabel("\(layout.rawValue) view")
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 6)
        .background {
            Capsule().fill(scheme == .dark ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x2B2B2E), Color(hex: 0x1E1E21)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(.regularMaterial))
                .overlay { Capsule().strokeBorder(scheme == .dark ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x4B4B4D), Color(hex: 0x27272A)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.black.opacity(0.08)), lineWidth: 1) }
        }
        .padding(.bottom, 16)
    }
    private func card(_ habit: Habit) -> some View {
        HabitCard(habit:habit,data:store.data,onOpen:{path.append(.habit(habit.id))},onComplete:{tap(habit,Day())})
            .contextMenu { habitMenu(habit) }
            .modifier(HabitDrag(id:habit.id,enabled:store.data.settings.dragToReorder) { source in
                var ids=store.visible.active.map(\.id)
                guard let from=ids.firstIndex(of:source),let to=ids.firstIndex(of:habit.id),from != to else{return}
                ids.remove(at:from);ids.insert(source,at:to)
                store.change { $0.reorder(ids) }
            })
    }
    private func tap(_ habit: Habit, _ day: Day) {
        let goal = habit.goal(on: day), p = Engine.progress(habit, day: day, data: store.data)
        if goal.tracking == .yesNo || (goal.tap == .addOne && !p.success && goal.mode == .build) { store.quickLog(habit, day: day) }
        else { daySelection = DaySelection(habit: habit, day: day) }
    }
    private var compact: some View {
        let today = Day(), days = Day.range(today.adding(-(store.data.settings.recentDays - 1)), today)
        let line = BuddyStyle.border(scheme, 0.105)
        return VStack(spacing: 12) {
            HStack {
                Button { compactSettings = true } label: {
                    Text("Last \(days.count) days").font(BuddyFont.text(15)).foregroundStyle(BuddyStyle.text(scheme))
                        .padding(.horizontal, 10.2).frame(height: 38).background(BuddyStyle.field(scheme), in: Capsule()).overlay { Capsule().strokeBorder(BuddyStyle.border(scheme, 0.1), lineWidth: 1) }
                        .contentShape(Capsule())
                }.buttonStyle(FlatButtonStyle()).accessibilityHint("Choose the days and whether habit names show")
                Spacer()
                Text("\(days.first!.shortTitle) — \(days.last!.shortTitle)").font(BuddyFont.mono(10.8)).tracking(1.45).foregroundStyle(BuddyStyle.tertiaryText(scheme))
            }
            LazyVStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("\(habits.count) \(habits.count == 1 ? "HABIT" : "HABITS")").font(BuddyFont.mono(11.2)).tracking(1.2).foregroundStyle(BuddyStyle.tertiaryText(scheme))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 17.6)
                    ForEach(days) { day in
                        VStack(spacing: 1.5) {
                            Text(String(Calendar.current.shortWeekdaySymbols[day.weekday-1].prefix(2))).font(BuddyFont.mono(11.2, day == today ? .semibold : .regular))
                            Text(String(Int(day.rawValue.suffix(2))!)).font(BuddyFont.mono(13, day == today ? .semibold : .regular))
                        }.foregroundStyle(day == today ? BuddyStyle.text(scheme) : BuddyStyle.tertiaryText(scheme)).frame(width: 30).padding(.top, 3.2)
                    }
                }.padding(.leading, 15.7).padding(.trailing, 15).frame(height: 53).padding(.top, 1)
                ForEach(habits) { habit in
                    VStack(spacing: 0) {
                        line.frame(height: 1)
                        HStack(spacing: 4) {
                            Button { path.append(.habit(habit.id)) } label: {
                                HStack(spacing: 11) { HabitIcon(habit: habit, size: 34); if store.data.settings.compactNames { Text(habit.name).font(BuddyFont.text(15.2)).lineLimit(1).foregroundStyle(BuddyStyle.text(scheme)) } }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            // Each tile takes half the 8-point gap on both sides, so the whole 38-point pitch is tappable.
                            HStack(spacing: 0) {
                                ForEach(days) { day in
                                    Button { tap(habit, day) } label: { DayTile(habit: habit, day: day, data: store.data, size: 30).frame(maxHeight: .infinity).padding(.horizontal, 4).contentShape(Rectangle()) }
                                        .buttonStyle(.plain).disabled(!habit.loggable(on: day, today: today))
                                        .contextMenu { Button("Edit amount and note") { daySelection = DaySelection(habit: habit, day: day) } }
                                }
                            }
                        }.padding(.leading, 15).padding(.trailing, 11).frame(height: 52).contextMenu { habitMenu(habit) }
                    }
                }
            }.panel(radius: 20, border: 0.07)
        }
    }
    /// Streak tiles in two columns: streak, today's check and this week for each habit.
    private var streakGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(habits) { habit in
                let palette = WidgetPalette(.tinted, scheme: scheme, tint: BuddyStyle.color(habit.color)), shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
                HabitWidgetContent(kind: .streak, habit: habit, data: store.data, palette: palette, onCheck: { tap($0, Day()) })
                    .frame(height: 158).background(palette.background(shape)).contentShape(shape)
                    .onTapGesture { path.append(.habit(habit.id)) }.contextMenu { habitMenu(habit) }
            }
        }
    }
    /// One row per habit: today's check, the week, and the streak.
    private var streakList: some View {
        LazyVStack(spacing: 8) {
            ForEach(habits) { habit in
                let palette = WidgetPalette(.tinted, scheme: scheme, tint: BuddyStyle.color(habit.color)), shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
                HStack(spacing: 12) {
                    HabitCheck(habit: habit, data: store.data, size: 44, palette: palette) { tap(habit, Day()) }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(habit.name).font(BuddyFont.text(17, .semibold)).foregroundStyle(palette.primary).lineLimit(1)
                        WeekStrip(habit: habit, data: store.data, palette: palette, cell: 16)
                    }
                    Spacer(minLength: 4)
                    StreakBadge(summary: store.summaries.streak(habit, data: store.data), palette: palette, size: 26, trailing: true)
                }
                .padding(.horizontal, 14).padding(.vertical, 12).background(palette.background(shape)).contentShape(shape)
                .onTapGesture { path.append(.habit(habit.id)) }.contextMenu { habitMenu(habit) }
            }
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
            ForEach(habits) { habit in MonthHabitCard(habit:habit,data:store.data,onOpen:{path.append(.habit(habit.id))},onComplete:{tap(habit,Day())}).contextMenu{habitMenu(habit)} }
        }
    }
    @ViewBuilder private func habitMenu(_ habit: Habit) -> some View {
        Button("Edit Habit", systemImage: "pencil") { editor = habit }
        Button("Appearance",systemImage:"slider.horizontal.3"){appearance=habit}
        Button("Share Habit",systemImage:"square.and.arrow.up"){share=habit}
        if store.data.settings.notes { Button("Notes",systemImage:"note.text"){notes=habit} }
        Button("Reorder Habits",systemImage:"arrow.up.arrow.down"){reorder=true}
        Button("Edit Today", systemImage: "calendar") { daySelection = DaySelection(habit: habit, day: Day()) }
        Button("Complete Yesterday", systemImage: "checkmark") { store.change { try Engine.complete(habit.id, day: Day().adding(-1), data: &$0) } }.disabled(!habit.loggable(on: Day().adding(-1), today: Day()))
        Button("Uncomplete Yesterday", systemImage: "eraser") { store.setAmount(0, habit.id, Day().adding(-1)) }.disabled(!habit.loggable(on: Day().adding(-1), today: Day()))
        Button("Archive", systemImage: "archivebox") { store.archive(habit.id) }
    }
    private func shiftMonth(_ delta: Int) { month = Day(Day.calendar.date(byAdding: .month, value: delta, to: month.date)!, timeZone: TimeZone(secondsFromGMT: 0)!) }
    private func loadSamples() { store.change { VisualSamples.populate(&$0) } }
    private func visualRoute() {
        #if DEBUG
        guard store.loaded,!visualRouted,let screen=ProcessInfo.processInfo.environment["BUDDY_VISUAL_SCREEN"] else{return}
        visualRouted=true
        let index=Int(ProcessInfo.processInfo.environment["BUDDY_VISUAL_HABIT"] ?? "0") ?? 0
        guard store.data.active.indices.contains(index) else{return}
        let habit=store.data.active[index]
        switch screen {
        case "detail","years","year-calendar":path=[.habit(habit.id)]
        case "dashboard","today-ring","widgets","widget-config":path=[.dashboard]
        case "explore":path=[.explore]
        case "insights":path=[.insights]
        case "calendar":path=[.calendar]
        case "recap":path=[.recap]
        case "notes-timeline":path=[.notes]
        case "milestones":path=[.milestones(nil)]
        case "habit-milestones":path=[.habit(habit.id),.milestones(habit.id)]
        case "routines","routine":path=[.routines]
        case "timer":timing=true
        case "editor":editor=habit
        case "new-habit":editor = .draft()
        case "statistics":stats=true
        case "settings":settings=true
        case "compact-settings":compactSettings=true
        case "share":share=habit
        case "appearance":appearance=habit
        case "notes":notes=habit
        case "day":daySelection=DaySelection(habit:habit,day:Day())
        default:break
        }
        #endif
    }
}

enum OverviewRoute: Hashable { case habit(UUID), dashboard, explore, insights, calendar, recap, notes, milestones(UUID?), routines }

extension Day {
    var monthTitle: String { Day.monthYear.string(from: date) }
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
    var onComplete:()->Void
    @State private var month=Day().startOfMonth
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:5) {
                Button(action:onComplete){MonthIndicator(habit:habit,data:data)}.buttonStyle(.plain).accessibilityLabel("Log progress for \(habit.name)")
                Button(action:onOpen){VStack(alignment:.leading,spacing:2){Text(habit.name).font(.system(size:11,weight:.medium)).lineLimit(1);Text(month.monthTitle).font(.system(size:9,design:.monospaced)).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain)
            }
            Button(action:onOpen){MiniMonth(habit:habit,data:data,month:month)}.buttonStyle(.plain)
        }.foregroundStyle(.primary).surface(padding:9,radius:16)
        .simultaneousGesture(DragGesture(minimumDistance:30).onEnded{v in if abs(v.translation.width)>abs(v.translation.height){shift(v.translation.width>0 ? -1:1)}})
        .accessibilityAction(named:"Previous month"){shift(-1)}.accessibilityAction(named:"Next month"){shift(1)}
    }
    private func shift(_ n:Int){let m=month.addingMonths(n);if m<=Day().startOfMonth && m>=habit.created.startOfMonth{month=m}}
}
struct MonthIndicator:View {
    let habit:Habit
    let data:BuddyData
    var body:some View {
        let p=Engine.progress(habit,day:Day(),data:data),c=BuddyStyle.color(habit.color)
        Group {
            if p.success { BuddyGlyph(symbol:habit.symbol,size:13).foregroundStyle(Color.black.opacity(0.7)).frame(width:26,height:26).background(c,in:Circle()) }
            else if habit.currentGoal.tracking != .yesNo {CompletionBadge(habit:habit,data:data,size:26)}
            else {Image(systemName:p.slip ? "xmark":"checkmark").font(.system(size:13)).foregroundStyle(.secondary).frame(width:26,height:26).background(Color.primary.opacity(0.035),in:Circle()).overlay{Circle().stroke(Color.primary.opacity(0.12),lineWidth:1)}}
        }
    }
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
    var noteTitle:String { self==Day() ? "Today":Day.longDay.string(from:date) }
    /// "SEP 29", for the compact period label.
    var shortTitle:String { Day.shortMonth.string(from:date).uppercased()+" "+String(Int(rawValue.suffix(2))!) }
}
/// Opened from the compact list's "Last N days" pill: how many recent days it shows, whether habit names show
/// beside the icons, and which habits are hidden everywhere.
struct CompactListSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @State private var hiding = false
    var body: some View {
        let note = scheme == .dark ? Color(hex: 0xA0A0A8) : BuddyStyle.secondaryText(scheme)
        VStack(alignment: .leading, spacing: 0) {
            Text("Compact List Settings").font(BuddyFont.text(22, .bold)).tracking(0.7).foregroundStyle(BuddyStyle.text(scheme))
                .accessibilityAddTraits(.isHeader)
            Text("Configure the amount of days to display in the compact list").font(BuddyFont.text(14)).tracking(-0.1).lineSpacing(2.4).foregroundStyle(note)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 9.7)
            HStack(spacing: 5) {
                ForEach(1...7, id: \.self) { count in
                    let on = store.data.settings.recentDays == count, shape = RoundedRectangle(cornerRadius: 12, style: .circular)
                    Button { store.change { $0.settings.recentDays = count } } label: {
                        Text("\(count)").font(BuddyFont.mono(12.5)).foregroundStyle(on ? Color.white : BuddyStyle.tertiaryText(scheme))
                            .frame(maxWidth: .infinity, minHeight: 40).background(on ? BuddyStyle.purple : .clear, in: shape)
                            .overlay { if !on { shape.strokeBorder(BuddyStyle.border(scheme, 0.07), lineWidth: 1) } }.contentShape(shape)
                    }.buttonStyle(FlatButtonStyle()).accessibilityLabel(count == 1 ? "1 day" : "\(count) days").accessibilityAddTraits(on ? .isSelected : [])
                }
            }.padding(.top, 10.9)
            Text("Configure whether the habit names will be hidden or not").font(BuddyFont.text(14)).tracking(-0.1).foregroundStyle(note)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 21)
            SegmentedChoice(selection: Binding(get: { store.data.settings.compactNames }, set: { shown in store.change { $0.settings.compactNames = shown } }), options: [(false, "Hidden"), (true, "Shown")])
                .padding(.top, 10.9)
            Text("Configure which habits are hidden everywhere").font(BuddyFont.text(14)).tracking(-0.1).foregroundStyle(note)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 21)
            HiddenHabitsRow { hiding = true }.padding(.top, 10.9)
        }
        .padding(.horizontal, 20).padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .sheet(isPresented: $hiding) { HideHabitsView().buddySheet().presentationDetents([.medium, .large]) }
        .presentationDetents([.height(425)])
        .presentationDragIndicator(.visible)
        .presentationBackground(BuddyStyle.field(scheme))
    }
}
/// Opens Hide Habits; shaped like the segmented control above it, with the number hidden.
struct HiddenHabitsRow: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme
    let action: () -> Void
    var body: some View {
        let count = store.data.active.filter(\.isHidden).count, shape = RoundedRectangle(cornerRadius: 15, style: .circular)
        Button(action: action) {
            HStack(spacing: 10) {
                LucideIcon("eye-off", size: 17).foregroundStyle(BuddyStyle.secondaryText(scheme))
                Text("Hidden Habits").font(BuddyFont.text(14, .medium)).tracking(0.28).foregroundStyle(BuddyStyle.text(scheme))
                Spacer(minLength: 8)
                Text(count == 0 ? "None" : "\(count) hidden").font(BuddyFont.text(14)).foregroundStyle(BuddyStyle.secondaryText(scheme))
                LucideIcon("chevron-right", size: 15).foregroundStyle(BuddyStyle.tertiaryText(scheme))
            }
            .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 50)
            .background(scheme == .dark ? Color(hex: 0x171719) : BuddyStyle.field(scheme), in: shape)
            .overlay { shape.strokeBorder(BuddyStyle.border(scheme, 0.1), lineWidth: 1) }.contentShape(shape)
        }
        .buttonStyle(FlatButtonStyle())
        .accessibilityElement(children: .ignore).accessibilityLabel("Hidden Habits").accessibilityValue(count == 0 ? "None" : "\(count) hidden")
        .accessibilityAddTraits(.isButton)
    }
}
/// Every active habit with a check to hide it. A hidden habit leaves every screen and widget until it is shown again;
/// its history, reminders, routines and Shortcuts carry on.
struct HideHabitsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let habits = store.data.active, hidden = habits.filter(\.isHidden).count
        VStack(spacing: 0) {
            SheetHeader(title: "Hide Habits")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Checked habits are left out of every screen and widget, for when you show the app to someone. Their history and reminders stay as they are.")
                        .font(BuddyFont.text(14)).foregroundStyle(BuddyStyle.secondaryText(scheme)).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                    if habits.isEmpty {
                        ContentUnavailableView("No habits yet", systemImage: "eye.slash", description: Text("Habits you create appear here."))
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(habits) { habit in
                                if habit.id != habits.first?.id { BuddyStyle.border(scheme, 0.07).frame(height: 1) }
                                row(habit)
                            }
                        }.panel(radius: 20, border: 0.07)
                        HStack {
                            Text(hidden == 0 ? "Every habit is shown" : "\(hidden) of \(habits.count) hidden").font(BuddyFont.mono(11)).tracking(1).textCase(.uppercase)
                                .foregroundStyle(BuddyStyle.tertiaryText(scheme))
                            Spacer()
                            if hidden > 0 {
                                Button { store.change { data in for i in data.habits.indices { data.habits[i].hidden = nil } } } label: {
                                    HStack(spacing: 6) { LucideIcon("eye", size: 15); Text("Show All") }.font(BuddyFont.text(14, .semibold)).foregroundStyle(BuddyStyle.purple).frame(minHeight: 44).contentShape(Rectangle())
                                }.buttonStyle(FlatButtonStyle()).accessibilityLabel("Show All Habits")
                            }
                        }.padding(.horizontal, 4).frame(minHeight: 44)
                    }
                }.padding(.horizontal, 16).padding(.bottom, 30)
            }.scrollIndicators(.hidden)
        }
        .background(BuddyStyle.canvas(scheme))
    }
    private func row(_ habit: Habit) -> some View {
        let id = habit.id, hide = !habit.isHidden
        return Button { store.change { data in if let i = data.habits.firstIndex(where: { $0.id == id }) { data.habits[i].hidden = hide ? true : nil } } } label: {
            HStack(spacing: 11) {
                HabitIcon(habit: habit, size: 34)
                Text(habit.name).font(BuddyFont.text(15.2)).lineLimit(1).foregroundStyle(BuddyStyle.text(scheme))
                Spacer(minLength: 8)
                ZStack {
                    if habit.isHidden { Circle().fill(BuddyStyle.purple); LucideIcon("check", size: 14).foregroundStyle(.white) }
                    else { Circle().strokeBorder(BuddyStyle.border(scheme, 0.22), lineWidth: 1.5) }
                }.frame(width: 26, height: 26)
            }.padding(.horizontal, 15).frame(height: 56).contentShape(Rectangle())
        }
        .buttonStyle(FlatButtonStyle())
        .accessibilityElement(children: .ignore).accessibilityLabel(habit.name).accessibilityValue(habit.isHidden ? "Hidden" : "Shown")
        .accessibilityAddTraits(habit.isHidden ? [.isButton, .isSelected] : .isButton).accessibilityHint(habit.isHidden ? "Shows the habit again" : "Hides the habit everywhere")
        .accessibilityIdentifier("hide-habit")
    }
}
/// The three drawn view-switcher icons: card rows, a checklist, and a two-column list.
struct LayoutGlyph: View {
    let layout:Layout
    var body:some View {
        Canvas { context,size in
            let thin=StrokeStyle(lineWidth:1,lineCap:.round,lineJoin:.round)
            var p=Path()
            switch layout {
            case .cards:
                var bars=Path()
                for y:CGFloat in [0.67,11.33] { bars.move(to:CGPoint(x:0.67,y:y));bars.addLine(to:CGPoint(x:18,y:y)) }
                context.stroke(bars,with:.foreground,style:StrokeStyle(lineWidth:1.33,lineCap:.round))
                for y:CGFloat in [4.5,15.17] { for x:CGFloat in [0.83,7.83,14.83] { p.addRoundedRect(in:CGRect(x:x,y:y,width:3,height:3),cornerSize:CGSize(width:0.8,height:0.8)) } }
                context.stroke(p,with:.foreground,style:thin)
            case .compact:
                for y:CGFloat in [1.2,7.5] { p.move(to:CGPoint(x:0.75,y:y+0.6));p.addLine(to:CGPoint(x:2.5,y:y+2.3));p.addLine(to:CGPoint(x:5.6,y:y-0.6)) }
                for y:CGFloat in [2,8.33,14.67] { p.move(to:CGPoint(x:y>14 ? 7.4:8.8,y:y));p.addLine(to:CGPoint(x:19.2,y:y)) }
                context.stroke(p,with:.foreground,style:StrokeStyle(lineWidth:1.1,lineCap:.round,lineJoin:.round))
                context.fill(Path(ellipseIn:CGRect(x:2.1,y:13.7,width:1.9,height:1.9)),with:.foreground)
            case .streaks:
                for y:CGFloat in [0.5,9.9] { for x:CGFloat in [0.5,9.9] { p.addRoundedRect(in:CGRect(x:x,y:y,width:7.6,height:7.6),cornerSize:CGSize(width:2,height:2)) } }
                context.stroke(p,with:.foreground,style:thin)
            case .list:
                for y:CGFloat in [2,8,14] { p.addEllipse(in:CGRect(x:0.5,y:y-1.8,width:3.6,height:3.6));p.move(to:CGPoint(x:7,y:y));p.addLine(to:CGPoint(x:18,y:y)) }
                context.stroke(p,with:.foreground,style:thin)
            case .month:
                for y:CGFloat in [0.5,5.5,10.5,15.5] { for (a,b) in [(0.5,6.17),(10.5,16.17)] as [(CGFloat,CGFloat)] { p.move(to:CGPoint(x:a,y:y));p.addLine(to:CGPoint(x:b,y:y)) } }
                context.stroke(p,with:.foreground,style:thin)
            }
        }.frame(width:layout == .compact ? 19.75:layout == .month ? 17:layout == .cards ? 18.7:18.5,height:layout == .compact ? 15.3:layout == .month ? 16:layout == .list ? 16:19).accessibilityHidden(true)
    }
}
