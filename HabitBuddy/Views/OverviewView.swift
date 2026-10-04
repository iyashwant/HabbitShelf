import SwiftUI

struct OverviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent
    @Environment(\.glass) private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var switcher
    @State private var toggleOpen = false
    /// A habit opens by zooming out of the card, row or tile that was tapped.
    @Namespace private var zoom
    @State private var path: [OverviewRoute] = []
    @State private var editor: Habit?
    @State private var appearance: Habit?
    @State private var notes: Habit?
    @State private var share: Habit?
    @State private var visualRouted = false
    @State private var daySelection: DaySelection?
    @State private var settings = false
    @State private var settingsStart: SettingsPage?
    @State private var compactSettings = false
    @State private var stats = false
    @State private var reorder = false
    @State private var routine: Routine?
    @State private var timing = false
    @State private var category: UUID?
    @State private var month = Day().startOfMonth
    @State private var page = HomePage.habits
    /// Whether a dashboard widget is lifted. While a widget or card is dragged, the switcher fades and lets the drag
    /// through to the widgets or cards beneath it.
    @State private var liftingWidget = false
    private var lifted: Bool { liftingWidget || arranged != nil }
    /// The card being dragged, and the order shown while it's over the cards; the order is saved when it's dropped.
    @State private var dragged: UUID?
    @State private var arranged: [UUID]?
    /// The card under the finger, and the one the dragged card last took the place of. That one is passed over until
    /// another card is entered, so a taller card that slides back under a resting finger doesn't swap straight back.
    @State private var hovered: UUID?
    @State private var swapped: UUID?
    /// Keeps the order shown once a dragged card has been off the cards for a moment.
    @State private var settling: Task<Void, Never>?
    /// Marks a card lifted from the overview, so text dragged in from another app moves nothing.
    static let habitType = "com.iyashwant.habbitbuddy.habit-card"
    /// The habits in the chosen category, in their saved order.
    private var filtered: [Habit] { store.visible.active.filter { category == nil || $0.categories.contains(category!) } }
    private var habits: [Habit] {
        let shown = filtered
        guard let arranged else { return shown }
        let byID = Dictionary(shown.map { ($0.id, $0) }) { first, _ in first }, placed = Set(arranged)
        return arranged.compactMap { byID[$0] } + shown.filter { !placed.contains($0.id) }
    }
    /// The page under the bottom switcher. With the switcher hidden, Dashboard and Explore are pushed from the top bar instead.
    private var shown: HomePage { store.settings.showLayoutSwitcher ? page : .habits }
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                switch shown {
                case .habits: habitsPage
                case .dashboard: DashboardView(settings: { settings = true }, lifting: { liftingWidget = $0 }) { path.append($0) }
                case .explore: ExploreView(settings: { settings = true })
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if store.settings.showLayoutSwitcher {
                    layoutSwitcher.opacity(lifted ? 0 : 1).allowsHitTesting(!lifted).animation(.snappy(duration: 0.25), value: lifted)
                }
            }
            .navigationDestination(for: OverviewRoute.self) { route in
                switch route {
                case .habit(let id): HabitDetailView(id: id).navigationTransition(.zoom(sourceID: id, in: zoom))
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
            // A sheet keeps the scheme it was presented with, and keeps a light or dark one after System is chosen, so
            // Settings takes the overview's scheme explicitly and follows a theme chosen while it is open.
            .sheet(isPresented: $settings) { SettingsView(start: settingsStart).buddySheet().preferredColorScheme(scheme) }
            .sheet(isPresented: $compactSettings) { CompactListSettingsView() }
            .sheet(isPresented: $stats) { StatisticsView().buddySheet() }
            .sheet(isPresented: $reorder) { ReorderView() }
            .sheet(item: $routine) { RoutineSheet(routineID: $0.id).buddySheet(partial: true).presentationDetents([.medium, .large]) }
            .sheet(isPresented: $timing) { TimerView().buddySheet() }
            .fullScreenCover(isPresented: Binding(get: { store.loaded && !store.settings.onboarding }, set: { _ in })) { WelcomeView() }
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
    private var habitsPage: some View {
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
                        Button("Create Habit") { editor = .draft() }.buttonStyle(.borderedProminent).foregroundStyle(accent.foreground)
                        if store.data.habits.isEmpty { Button("Try sample habits") { loadSamples() } }
                    }.padding(.top, 70)
                } else {
                    if store.settings.showCategoryFilter && !store.data.categories.isEmpty { categoryFilter }
                    if !store.visible.routines.isEmpty { RoutineStrip { routine = $0 } }
                    switch store.settings.layout {
                    case .cards: LazyVStack(spacing: 15.3) { ForEach(habits) { habit in card(habit) } }
                    case .compact: compact
                    case .month: monthGrid
                    case .streaks, .weeks: tileGrid(.streak)
                    case .rings: tileGrid(.ring)
                    case .year: tileGrid(.year, columns: 1)
                    case .list: streakList
                    }
                }
            }.padding(.horizontal, 8).padding(.bottom, 110)
        }
        .overlay {
            // A tap anywhere outside the open toggle minimises it back to the bubble.
            if toggleOpen { Color.clear.contentShape(Rectangle()).onTapGesture { withAnimation(.snappy(duration: 0.25)) { toggleOpen = false } } }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.loaded, !habits.isEmpty, Self.streakViews.contains(store.settings.layout) {
                HStack(spacing: 0) { Spacer(minLength: 0); streakListToggle }.padding(.trailing, 16).padding(.bottom, store.settings.showLayoutSwitcher ? 14 : 26)
            }
        }
        .sensoryFeedback(.selection, trigger: arranged) { old, new in old != nil && new != nil && store.settings.haptics }
        .background(BuddyStyle.canvas(scheme))
        .toolbar(.hidden, for: .navigationBar)
        .homeBar(settings: { settings = true }) {
            if !store.settings.showLayoutSwitcher {
                CircleControl(symbol: "compass", label: "Explore") { open(.explore) }
                CircleControl(symbol: "layout-dashboard", label: "Dashboard") { open(.dashboard) }
            }
            CircleControl(symbol: "stats", label: "Statistics") { stats = true }
            CircleControl(symbol: "plus", label: "Create Habit", filled: true, glyph: 19) { editor = .draft() }
        }
    }
    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Button("All Habits") { category = nil }.buttonStyle(.bordered).tint(category == nil ? accent.color : .secondary)
                ForEach(store.data.categories) { item in
                    Button { category = item.id } label: { HStack { BuddyGlyph(symbol:item.symbol,size:12);Text(item.name) } }
                        .buttonStyle(.bordered).tint(category == item.id ? accent.color : .secondary)
                }
                Button { reorder = true } label: { LucideIcon("arrow-up-down", size: 14) }.buttonStyle(.bordered).accessibilityLabel("Reorder habits")
            }.font(BuddyFont.text(12))
        }
    }
    /// The habit layouts, then Dashboard and Explore at the trailing end. Each opens in place under the switcher.
    private var layoutSwitcher: some View {
        let layout = store.settings.layout
        return HStack(spacing: 4) {
            // Streaks and List share one button, shown with the List icon; the toggle at the bottom of that view switches between them.
            ForEach(Layout.allCases.filter { ($0 != .weeks && !Self.streakViews.contains($0)) || $0 == .list }, id: \.self) { item in
                let merged = item == .list, selected = shown == .habits && (layout == item || (merged && Self.streakViews.contains(layout)))
                switcherButton(item.rawValue, label: merged ? "Streaks, list, rings and year views" : "\(item.rawValue) view", selected: selected) {
                    page = .habits
                    if layout != item && !(merged && Self.streakViews.contains(layout)) { store.change { $0.settings.layout = item } }
                } glyph: { LayoutGlyph(layout: item) }
            }
            Capsule().fill(BuddyStyle.border(scheme, 0.12)).frame(width: 1, height: 20).padding(.horizontal, 2).accessibilityHidden(true)
            ForEach([HomePage.dashboard, .explore], id: \.self) { item in
                switcherButton(item.rawValue, label: item.title, selected: shown == item) { page = item } glyph: { PageGlyph(page: item) }
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 6)
        .animation(glass == nil ? nil : .spring(response: 0.35, dampingFraction: 1), value: shown == .habits ? layout.rawValue : shown.rawValue)
        .glassChrome(in: Capsule(),
                     fill: scheme == .dark ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x2B2B2E), Color(hex: 0x1E1E21)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(.regularMaterial),
                     border: scheme == .dark ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x4B4B4D), Color(hex: 0x27272A)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.black.opacity(0.08)))
        // Six buttons fit a 375-point phone: they narrow from 48 points to fit inside a 16-point margin.
        .padding(.horizontal, 16).padding(.bottom, 16)
    }
    /// Switches the merged Streaks and List view between its two-column tiles and its rows.
    private var streakListToggle: some View {
        let current = store.settings.layout
        return HStack(spacing: 2) {
            if toggleOpen {
                ForEach(Self.streakViews, id: \.self) { item in
                    let on = current == item
                    Button {
                        if !on { store.change { $0.settings.layout = item } }
                        withAnimation(.snappy(duration: 0.25)) { toggleOpen = false }
                    } label: {
                        toggleGlyph(item).foregroundStyle(on ? accent.foreground : Color(hex: scheme == .dark ? 0xECECEC : 0x1C1C1E))
                            .frame(width: 44, height: 32)
                            .background { if on { Capsule().fill(accent.color) } }
                            .contentShape(Capsule())
                    }.buttonStyle(.plain).accessibilityLabel(item.title)
                        .accessibilityAddTraits(on ? .isSelected : [])
                }
            } else {
                // Collapsed to a bubble showing the current view; tapping it opens the full set.
                Button { withAnimation(.snappy(duration: 0.25)) { toggleOpen = true } } label: {
                    toggleGlyph(current).foregroundStyle(Color(hex: scheme == .dark ? 0xECECEC : 0x1C1C1E))
                        .frame(width: 44, height: 32).contentShape(Capsule())
                }.buttonStyle(.plain).accessibilityLabel("\(current.title) view. Show all streak views")
            }
        }
        .padding(3).opacity(lifted ? 0 : 1).allowsHitTesting(!lifted)
        .glassChrome(in: Capsule(), fill: AnyShapeStyle(.regularMaterial), border: AnyShapeStyle(Color.black.opacity(0.08)))
    }
    @ViewBuilder private func toggleGlyph(_ item: Layout) -> some View {
        switch item {
        case .rings: LucideIcon("circle-gauge", size: 18)
        case .year: LucideIcon("calendar-days", size: 18)
        default: LayoutGlyph(layout: item)
        }
    }
    private func switcherButton(_ id: String, label: String, selected: Bool, action: @escaping () -> Void, @ViewBuilder glyph: () -> some View) -> some View {
        Button(action: action) {
            glyph().foregroundStyle(Color(hex: scheme == .dark ? 0xECECEC : 0x1C1C1E))
                .frame(minWidth: 40, maxWidth: 48).frame(height: 44)
                .background {
                    if selected && glass != nil {
                        // A lighter lens slides to the chosen view, like the selection in an iOS tab bar.
                        // Reduce Motion gives each view its own lens, so the change cross-fades instead.
                        Capsule().fill(scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.07))
                            .matchedGeometryEffect(id: reduceMotion ? id : "selection", in: switcher)
                    } else if selected {
                        Capsule().fill(scheme == .dark ? Color(hex: 0x3E3E40) : Color.black.opacity(0.08)).overlay { Capsule().strokeBorder(scheme == .dark ? Color(hex: 0x545456) : Color.black.opacity(0.08), lineWidth: 1) }
                    }
                }
                .contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityLabel(label)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    /// Opens Dashboard or Explore: in place from the bottom switcher, or pushed while the switcher is hidden.
    private func open(_ item: HomePage) {
        if store.settings.showLayoutSwitcher { page = item } else if item != .habits { path.append(item == .dashboard ? .dashboard : .explore) }
    }
    /// With Drag to Reorder on, holding any part of a card opens its menu, and moving the finger then lifts the card:
    /// the menus are inside the card and the drag is around it, the order in which iOS hands a hold over to a drag. The
    /// other cards make room as it passes over them.
    @ViewBuilder private func card(_ habit: Habit) -> some View {
        let card = HabitCard(habit:habit,data:store.data,version:store.version(habit.id),onOpen:{path.append(.habit(habit.id))},onComplete:{tap(habit,Day())}) { habitMenu(habit) }
            .equatable()
            .matchedTransitionSource(id: habit.id, in: zoom) { $0.clipShape(RoundedRectangle(cornerRadius: 24, style: .circular)) }
        if store.settings.dragToReorder {
            let lifting = arranged != nil && dragged == habit.id
            card.onDrag {
                // Asked again during the drag; the card lifted first stays the dragged one.
                if arranged == nil { dragged = habit.id }
                return NSItemProvider(dragging: habit.id, marked: Self.habitType)
            }
            .onDrop(of: [.utf8PlainText], delegate: CardDrop(target: habit.id, enter: enter, drop: drop, leave: leave))
            // While it's lifted, its place shows where it will land.
            .opacity(lifting ? 0 : 1)
            .background { if lifting { RoundedRectangle(cornerRadius: 24, style: .circular).strokeBorder(BuddyStyle.border(scheme, 0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])) } }
        } else { card }
    }
    /// The dragged card takes the place of the card under the finger.
    private func enter(_ target: UUID) {
        settling?.cancel(); settling = nil; hovered = target
        guard let dragged else { return }
        var order = habits.map(\.id)
        if arranged == nil { arranged = order }
        if target == dragged { swapped = nil; return }
        guard target != swapped, let from = order.firstIndex(of: dragged), let to = order.firstIndex(of: target) else { return }
        order.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
        swapped = target
        withAnimation(.snappy(duration: 0.3)) { arranged = order }
    }
    private func drop() { settle(); dragged = nil }
    /// The drag left a card. The cards stay put: it may be crossing to the next card, iOS also reports a leave when the
    /// switcher fades, and holding a card at the bottom scrolls until the finger is below the last one. If the drag
    /// doesn't reach another card, the order shown is kept, as when a Home Screen icon is let go.
    private func leave(_ target: UUID) {
        guard hovered == target else { return }
        hovered = nil
        settling?.cancel()
        settling = Task { try? await Task.sleep(for: .milliseconds(300)); if !Task.isCancelled { settle() } }
    }
    /// Saves the order shown. Habits in other categories and hidden habits keep their places among the rest.
    private func settle() {
        settling?.cancel(); settling = nil
        if let arranged, arranged != filtered.map(\.id) {
            store.change { $0.reorder(arranged) }
        }
        withAnimation(.snappy(duration: 0.3)) { arranged = nil }; hovered = nil; swapped = nil
    }
    private func tap(_ habit: Habit, _ day: Day) {
        let goal = habit.goal(on: day), p = Engine.progress(habit, day: day, data: store.data)
        if goal.tracking == .yesNo || (goal.tap == .addOne && !p.success && goal.mode == .build) { store.quickLog(habit, day: day) }
        else { daySelection = DaySelection(habit: habit, day: day) }
    }
    private var compact: some View {
        let today = Day(), days = Day.range(today.adding(-(store.settings.recentDays - 1)), today)
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
                        CompactRow(habit: habit, data: store.data, version: store.version(habit.id), days: days, today: today, names: store.settings.compactNames,
                                   onOpen: { path.append(.habit(habit.id)) }, onTap: { tap(habit, $0) }, onEdit: { daySelection = DaySelection(habit: habit, day: $0) }) { habitMenu(habit) }
                            .equatable()
                            .matchedTransitionSource(id: habit.id, in: zoom)
                    }
                }
            }.panel(radius: 20, border: 0.07)
        }
    }
    /// The views that share the bottom switcher's one streak button; the toggle above it moves between them.
    static let streakViews: [Layout] = [.streaks, .list, .rings, .year]
    /// One widget design per habit in a grid: streak tiles and goal rings in two columns, 20 weeks and the year in one.
    private func tileGrid(_ kind: DashboardKind, columns: Int = 2) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
            ForEach(habits) { habit in
                let palette = WidgetPalette(.tinted, scheme: scheme, tint: BuddyStyle.color(habit.color)), shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
                HabitWidgetContent(kind: kind, habit: habit, data: store.data, palette: palette, versions: [store.version(habit.id)], onCheck: { tap($0, Day()) })
                    .equatable().frame(height: 158).background(palette.background(shape)).contentShape(shape)
                    .matchedTransitionSource(id: habit.id, in: zoom) { $0.clipShape(shape) }
                    .onTapGesture { path.append(.habit(habit.id)) }.contextMenu { habitMenu(habit) }
            }
        }
    }
    /// One row per habit: today's check, the week, and the streak.
    private var streakList: some View {
        LazyVStack(spacing: 8) {
            ForEach(habits) { habit in
                StreakListRow(habit: habit, data: store.data, version: store.version(habit.id)) { tap(habit, Day()) }
                    .equatable().contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .matchedTransitionSource(id: habit.id, in: zoom) { $0.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)) }
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
            ForEach(habits) { habit in MonthHabitCard(habit:habit,data:store.data,version:store.version(habit.id),onOpen:{path.append(.habit(habit.id))},onComplete:{tap(habit,Day())}).equatable().matchedTransitionSource(id:habit.id,in:zoom){$0.clipShape(RoundedRectangle(cornerRadius:16,style:.circular))}.contextMenu{habitMenu(habit)} }
        }
    }
    @ViewBuilder private func habitMenu(_ habit: Habit) -> some View {
        Button("Edit Habit", systemImage: "pencil") { editor = habit }
        Button("Appearance",systemImage:"slider.horizontal.3"){appearance=habit}
        Button("Share Habit",systemImage:"square.and.arrow.up"){share=habit}
        if store.settings.notes { Button("Notes",systemImage:"note.text"){notes=habit} }
        Button("Reorder Habits",systemImage:"arrow.up.arrow.down"){reorder=true}
        Button("Edit Today", systemImage: "calendar") { daySelection = DaySelection(habit: habit, day: Day()) }
        Button("Complete Yesterday", systemImage: "checkmark") { store.log([habit.id]) { try Engine.complete(habit.id, day: Day().adding(-1), data: &$0) } }.disabled(!habit.loggable(on: Day().adding(-1), today: Day()))
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
        case "dashboard","today-ring","widgets","widget-config":open(.dashboard)
        case "explore":open(.explore)
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
        case "theme":settingsStart = .theme;settings=true
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
/// What the bottom switcher shows: the habits in the chosen layout, the Dashboard or Explore.
enum HomePage: String { case habits, dashboard, explore
    var title: String { rawValue.capitalized }
}

/// The overview's top controls: Settings at the leading edge and the page's own controls at the trailing edge. The
/// habits, Dashboard and Explore share them, so Settings stays put when the switcher changes page.
struct HomeBar<Trailing: View>: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.glass) private var glass
    let settings: () -> Void
    let trailing: Trailing
    func body(content: Content) -> some View {
        content
            .topBar(backdrop: 0) {
                GlassGroup(spacing: 8) {
                    HStack(spacing: 8) {
                        CircleControl(symbol: "settings", label: "Settings", action: settings)
                        Spacer()
                        trailing
                    }
                }.padding(.leading, 7).padding(.trailing, 10).padding(.top, 7).padding(.bottom, 12)
            }
            // The reference fades content (and the top of the controls) into the canvas under the status bar.
            // Liquid Glass leaves that to iOS's scroll edge effect (see `topBar`).
            .overlay(alignment: .top) {
                if glass == nil {
                    GeometryReader { proxy in
                        LinearGradient(colors: [BuddyStyle.canvas(scheme), BuddyStyle.canvas(scheme).opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: proxy.safeAreaInsets.top + 29)
                    }.ignoresSafeArea().allowsHitTesting(false)
                }
            }
    }
}
/// Dashboard's and Explore's top controls: the overview's bar while the bottom switcher shows them in place, or a back
/// control like the other pages while they're pushed with the switcher hidden. `trailing` learns which, to size its controls.
struct SwitcherPageBar<Trailing: View>: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let settings: (() -> Void)?
    let trailing: (_ pushed: Bool) -> Trailing
    @ViewBuilder func body(content: Content) -> some View {
        if let settings { content.homeBar(settings: settings) { trailing(false) } }
        else {
            content.topBar {
                GlassGroup(spacing: 8) {
                    HStack(spacing: 8) {
                        CircleControl(symbol: "chevron-left", label: "Back", size: 38, glyph: 12.5) { dismiss() }
                        Spacer()
                        trailing(true)
                    }
                }.padding(.horizontal, 12).padding(.top, 8.8).padding(.bottom, 8)
            }
        }
    }
}
extension View {
    func homeBar(settings: @escaping () -> Void, @ViewBuilder trailing: () -> some View) -> some View { modifier(HomeBar(settings: settings, trailing: trailing())) }
    func switcherPageBar<Trailing: View>(settings: (() -> Void)?, @ViewBuilder trailing: @escaping (_ pushed: Bool) -> Trailing) -> some View { modifier(SwitcherPageBar(settings: settings, trailing: trailing)) }
}

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

struct MonthHabitCard: View, Equatable {
    let habit:Habit
    let data:BuddyData
    /// The store's version of this habit; with one, the card redraws only when it, the habit or the day changes.
    var version:HabitVersion?
    var today=Day()
    var onOpen:()->Void
    var onComplete:()->Void
    @State private var month=Day().startOfMonth
    static func ==(a:Self,b:Self)->Bool { guard let version=a.version,version==b.version else{return false}; return a.habit==b.habit && a.today==b.today }
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:5) {
                Button(action:onComplete){MonthIndicator(habit:habit,data:data)}.buttonStyle(FlatButtonStyle()).accessibilityLabel("Log progress for \(habit.name)")
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
/// One habit in the compact list: its icon (and name) and a tile per recent day. It redraws only when its habit,
/// version, days or name setting change, not each time another habit is logged.
struct CompactRow<Menu: View>: View, Equatable {
    @Environment(\.colorScheme) private var scheme
    let habit: Habit
    let data: BuddyData
    let version: HabitVersion
    let days: [Day]
    let today: Day
    let names: Bool
    var onOpen: () -> Void
    var onTap: (Day) -> Void
    var onEdit: (Day) -> Void
    /// The habit's menu, for holding the row. The name's button carries it too: in the lazy list, holding a button
    /// inside the row's menu area opened the habit instead of the menu (iOS 27 simulator).
    @ViewBuilder var menu: () -> Menu
    var body: some View {
        HStack(spacing: 4) {
            Button(action: onOpen) {
                HStack(spacing: 11) { HabitIcon(habit: habit, size: 34); if names { Text(habit.name).font(BuddyFont.text(15.2)).lineLimit(1).foregroundStyle(BuddyStyle.text(scheme)) } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).contextMenu(menuItems: menu)
            // Each tile takes half the 8-point gap on both sides, so the whole 38-point pitch is tappable.
            HStack(spacing: 0) {
                ForEach(days) { day in
                    Button { onTap(day) } label: { DayTile(habit: habit, day: day, data: data, size: 30).frame(maxHeight: .infinity).padding(.horizontal, 4).contentShape(Rectangle()) }
                        .buttonStyle(FlatButtonStyle()).disabled(!habit.loggable(on: day, today: today))
                        .contextMenu { Button("Edit amount and note") { onEdit(day) } }
                }
            }
        }.padding(.leading, 15).padding(.trailing, 11).frame(height: 52).contextMenu(menuItems: menu)
    }
    static func == (a: Self, b: Self) -> Bool {
        a.version == b.version && a.habit == b.habit && a.days == b.days && a.today == b.today && a.names == b.names
    }
}
/// One habit in the streak list: today's check, this week and the streak. Redraws only when its habit changes.
struct StreakListRow: View, Equatable {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.summaries) private var summaries
    let habit: Habit
    let data: BuddyData
    let version: HabitVersion
    var today = Day()
    var onCheck: () -> Void
    var body: some View {
        let palette = WidgetPalette(.tinted, scheme: scheme, tint: BuddyStyle.color(habit.color)), shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        HStack(spacing: 12) {
            HabitCheck(habit: habit, data: data, size: 44, palette: palette, onTap: onCheck)
            VStack(alignment: .leading, spacing: 6) {
                Text(habit.name).font(BuddyFont.text(17, .semibold)).foregroundStyle(palette.primary).lineLimit(1)
                WeekStrip(habit: habit, data: data, palette: palette, cell: 16)
            }
            Spacer(minLength: 4)
            StreakBadge(summary: summaries.streak(habit, data: data), palette: palette, size: 26, trailing: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 12).background(palette.background(shape))
    }
    static func == (a: Self, b: Self) -> Bool { a.version == b.version && a.habit == b.habit && a.today == b.today }
}
/// Follows a habit card dragged over another card; dropping it saves the order.
private struct CardDrop: DropDelegate {
    let target: UUID
    let enter: (UUID) -> Void
    let drop: () -> Void
    let leave: (UUID) -> Void
    func validateDrop(info: DropInfo) -> Bool { info.carries(OverviewView.habitType) }
    func dropEntered(info: DropInfo) { enter(target) }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func dropExited(info: DropInfo) { leave(target) }
    func performDrop(info: DropInfo) -> Bool { drop(); return true }
}
extension Day {
    var noteTitle:String { self==Day() ? "Today":Day.longDay.string(from:date) }
    /// "SEP 29", for the compact period label.
    var shortTitle:String { Day.shortMonth.string(from:date).uppercased()+" "+String(Int(rawValue.suffix(2))!) }
}
/// Opened from the compact list's "Last N days" pill: how many recent days it shows, whether habit names show
/// beside the icons, and which habits are hidden everywhere.
struct CompactListSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent
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
                    let on = store.settings.recentDays == count, shape = RoundedRectangle(cornerRadius: 12, style: .circular)
                    Button { store.change { $0.settings.recentDays = count } } label: {
                        Text("\(count)").font(BuddyFont.mono(12.5)).foregroundStyle(on ? accent.foreground : BuddyStyle.tertiaryText(scheme))
                            .frame(maxWidth: .infinity, minHeight: 40).background(on ? accent.color : .clear, in: shape)
                            .overlay { if !on { shape.strokeBorder(BuddyStyle.border(scheme, 0.07), lineWidth: 1) } }.contentShape(shape)
                    }.buttonStyle(FlatButtonStyle()).accessibilityLabel(count == 1 ? "1 day" : "\(count) days").accessibilityAddTraits(on ? .isSelected : [])
                }
            }.padding(.top, 10.9)
            Text("Configure whether the habit names will be hidden or not").font(BuddyFont.text(14)).tracking(-0.1).foregroundStyle(note)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 21)
            SegmentedChoice(selection: Binding(get: { store.settings.compactNames }, set: { shown in store.change { $0.settings.compactNames = shown } }), options: [(false, "Hidden"), (true, "Shown")])
                .padding(.top, 10.9)
            Text("Configure which habits are hidden everywhere").font(BuddyFont.text(14)).tracking(-0.1).foregroundStyle(note)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 21)
            HiddenHabitsRow { hiding = true }.padding(.top, 10.9)
        }
        .padding(.horizontal, 20).padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .sheet(isPresented: $hiding) { HideHabitsView().buddySheet().presentationDetents([.medium, .large]) }
        .presentationDetents([.height(425)])
        .buddySheet(partial: true, background: BuddyStyle.field(scheme))
    }
}
/// Opens Hide Habits; shaped like the segmented control above it, with the number hidden.
struct HiddenHabitsRow: View {
    @Environment(AppStore.self) private var store
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
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent
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
                                    HStack(spacing: 6) { LucideIcon("eye", size: 15); Text("Show All") }.font(BuddyFont.text(14, .semibold)).foregroundStyle(accent.color).frame(minHeight: 44).contentShape(Rectangle())
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
                    if habit.isHidden { Circle().fill(accent.color); LucideIcon("check", size: 14).foregroundStyle(accent.foreground) }
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
/// The switcher's Dashboard and Explore icons, a dashboard layout and a compass drawn in the layout icons' thin stroke.
struct PageGlyph: View {
    let page: HomePage
    var body: some View {
        Canvas { context, _ in
            var p = Path()
            switch page {
            case .habits: break
            case .dashboard:
                // Lucide's layout-dashboard: a tall box beside two stacked ones, a short one above a tall one.
                for r in [CGRect(x: 0.5, y: 0.5, width: 7.5, height: 9.5), CGRect(x: 11, y: 0.5, width: 7.5, height: 5.5), CGRect(x: 11, y: 9.5, width: 7.5, height: 9), CGRect(x: 0.5, y: 13.5, width: 7.5, height: 5)] { p.addRoundedRect(in: r, cornerSize: CGSize(width: 1.6, height: 1.6)) }
            case .explore:
                p.addEllipse(in: CGRect(x: 0.5, y: 0.5, width: 18, height: 18))
                p.addLines([CGPoint(x: 13.3, y: 5.7), CGPoint(x: 11.4, y: 11.4), CGPoint(x: 5.7, y: 13.3), CGPoint(x: 7.6, y: 7.6)]); p.closeSubpath()
            }
            context.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
        }.frame(width: 19, height: 19).accessibilityHidden(true)
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
                for y:CGFloat in [0.5,10.5] { for x:CGFloat in [0.5,10.5] { p.addRoundedRect(in:CGRect(x:x,y:y,width:7.5,height:7.5),cornerSize:CGSize(width:1.8,height:1.8)) } }
                context.stroke(p,with:.foreground,style:thin)
            case .list:
                for y:CGFloat in [2,8,14] { p.addEllipse(in:CGRect(x:0.5,y:y-1.8,width:3.6,height:3.6));p.move(to:CGPoint(x:7,y:y));p.addLine(to:CGPoint(x:18,y:y)) }
                context.stroke(p,with:.foreground,style:thin)
            case .month:
                for y:CGFloat in [0.5,5.5,10.5,15.5] { for (a,b) in [(0.5,6.17),(10.5,16.17)] as [(CGFloat,CGFloat)] { p.move(to:CGPoint(x:a,y:y));p.addLine(to:CGPoint(x:b,y:y)) } }
                context.stroke(p,with:.foreground,style:thin)
            case .rings, .weeks, .year: break
            }
        }.frame(width:layout == .compact ? 19.75:layout == .month ? 17:layout == .cards ? 18.7:18.5,height:layout == .compact ? 15.3:layout == .month ? 16:layout == .list ? 16:19).accessibilityHidden(true)
    }
}
