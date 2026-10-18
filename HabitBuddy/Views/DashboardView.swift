import SwiftUI
import UniformTypeIdentifiers

/// A board of habit widgets laid out like the home screen: small widgets take half a row, medium a full row
/// and large a full row at double height. Today lists fit their visible rows.
struct DashboardView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent
    /// Shown in place by the bottom switcher, under the overview's shared top bar; otherwise pushed, with a back control.
    var inPlace = false
    /// Told when a widget is lifted over the board and when it's dropped or leaves.
    var lifting: (Bool) -> Void = { _ in }
    var open: (OverviewRoute) -> Void
    @State private var editing = false
    @State private var adding = false
    @State private var configuring: DashboardWidget?
    @State private var daySelection: DaySelection?
    @State private var routine: Routine?
    /// The widget being dragged, and the order shown while it's over the page; the order is saved when it's dropped.
    @State private var dragged: UUID?
    @State private var arranged: [UUID]?
    /// Where the last reorder happened, so a widget that slides under a resting finger doesn't move straight back.
    @State private var lastMove: CGPoint?
    /// Where the board is on the page, for placing a dragged widget.
    @State private var board = BoardFrame()
    /// The visible height, which the page fills while a widget is lifted.
    @State private var screenHeight: CGFloat = 0
    /// Keeps the order shown once a dragged widget has been off the page for a moment.
    @State private var settling: Task<Void, Never>?
    /// Marks a widget lifted from the board, so text dragged in from another app moves nothing.
    static let widgetType = "com.iyashwant.habbitbuddy.dashboard-widget"
    private var widgets: [DashboardWidget] {
        let shown = DashboardLayout.current(store).filter { $0.visible(in: store.visible) }
        guard let arranged else { return shown }
        let byID = Dictionary(shown.map { ($0.id, $0) }) { first, _ in first }, placed = Set(arranged)
        return arranged.compactMap { byID[$0] } + shown.filter { !placed.contains($0.id) }
    }
    var body: some View {
        let widgets = widgets
        ScrollView {
            // Not a lazy stack: in one, touching and holding a widget's check logged it instead of opening the
            // widget's menu (iOS 27 simulator). The board holds at most 100 widgets.
            VStack(alignment: .leading, spacing: 16) {
                Text("Dashboard").font(BuddyFont.text(32, .heavy)).foregroundStyle(BuddyStyle.text(scheme)).padding(.top, 4).homeFlow()
                if widgets.isEmpty {
                    ContentUnavailableView { Label("No widgets yet", systemImage: "square.grid.2x2") } description: { Text(store.visible.active.isEmpty ? "Create a habit, then add widgets for it here." : "Add widgets to keep your habits at a glance.") } actions: { if !store.visible.active.isEmpty { Button("Add Widget") { adding = true }.buttonStyle(.borderedProminent).foregroundStyle(accent.foreground) } }
                        .homeFlow()
                }
                board(widgets)
            }
            .padding(.horizontal, 16).padding(.bottom, 40)
            // The page takes the drop, so the margins and the title don't count as leaving the board. While a widget is
            // lifted it is at least as tall as the screen, so a short board takes it below its last widget too.
            .frame(minHeight: arranged == nil ? nil : screenHeight, alignment: .top)
            .coordinateSpace(.named("dashboard"))
            .onDrop(of: [.utf8PlainText], delegate: BoardDrop(over: hover, drop: drop, leave: leave))
        }.scrollIndicators(.hidden).pageClip()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { screenHeight = $0 }
        .sensoryFeedback(.selection, trigger: arranged) { old, new in old != nil && new != nil && store.settings.haptics }
        .onChange(of: arranged != nil) { _, lifted in lifting(lifted) }
        // In place, the overview draws the canvas behind every page.
        .background(BuddyStyle.canvas(scheme).opacity(inPlace ? 0 : 1)).toolbar(.hidden, for: .navigationBar)
        .switcherPageBar(inPlace: inPlace) {
            CircleControl(symbol: "sliders-horizontal", label: "Edit Dashboard", size: 38, glyph: 16) { editing = true }
            CircleControl(symbol: "plus", label: "Add Widget", filled: true, size: 38, glyph: 17) { adding = true }.disabled(store.visible.active.isEmpty)
        }
        .sheet(isPresented: $editing) { DashboardEditorView().buddySheet() }
        .sheet(isPresented: $adding) { WidgetConfigurator(widget: DashboardWidget(kind: .streak, habitID: store.visible.active.first?.id), isNew: true).buddySheet() }
        .sheet(item: $configuring) { WidgetConfigurator(widget: $0, isNew: false).buddySheet() }
        .sheet(item: $daySelection) { DayEditorView(selection: $0) }
        .sheet(item: $routine) { RoutineSheet(routineID: $0.id).buddySheet(partial: true).presentationDetents([.medium, .large]) }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["BUDDY_VISUAL_SCREEN"] == "widget-config" { configuring = DashboardWidget(kind: .checks, style: .tinted) }
            #endif
        }
    }
    /// Touching and holding a widget opens its menu; moving the finger then lifts the widget, and the others make room
    /// as it passes over them.
    private func board(_ widgets: [DashboardWidget]) -> some View {
        DashboardGrid { ForEach(widgets) { tile($0) } }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("dashboard")) } action: { [board] in board.frame = $0 }
    }
    private func tile(_ widget: DashboardWidget) -> some View {
        DashboardTile(widget: widget, data: store.visible, versions: versions(widget), onCheck: check, onRoutine: complete)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onTapGesture { tap(widget) }
            // The menu comes before the drag: the other way round, holding opened the menu and moving never lifted the
            // widget (iOS 27 simulator).
            .contextMenu { menu(widget) }
            .onDrag { lift(widget) }
            // While it's lifted, its place shows where it will land.
            .opacity(arranged != nil && dragged == widget.id ? 0 : 1)
            .background { if arranged != nil && dragged == widget.id { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(BuddyStyle.border(scheme, 0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])) } }
            .homeFlow()
            .containerValue(\.widgetSize, widget.resolvedSize)
            .containerValue(\.widgetFitsContent, widget.kind == .list)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { [board] in board.heights[widget.id] = $0 }
    }
    @ViewBuilder private func menu(_ widget: DashboardWidget) -> some View {
        Button("Edit Widget", systemImage: "slider.horizontal.3") { configuring = widget }
        if widget.kind.sizes.count > 1 {
            Menu("Size", systemImage: "arrow.up.left.and.arrow.down.right") {
                ForEach(widget.kind.sizesInOrder, id: \.self) { size in
                    Button { update(widget) { $0.size = size == $0.kind.sizes[0] ? nil : size } } label: { if widget.resolvedSize == size { Label(size.title, systemImage: "checkmark") } else { Text(size.title) } }
                }
            }
        }
        Menu("Style", systemImage: "paintpalette") {
            ForEach(WidgetStyle.allCases, id: \.self) { style in
                Button { update(widget) { $0.style = style } } label: { if widget.style == style { Label(style.title, systemImage: "checkmark") } else { Text(style.title) } }
            }
        }
        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(widget) }
        Button("Remove Widget", systemImage: "trash", role: .destructive) { DashboardLayout.save(store, DashboardLayout.current(store).filter { $0.id != widget.id }) }
    }
    private func lift(_ widget: DashboardWidget) -> NSItemProvider {
        // Asked again during the drag; the widget lifted first stays the dragged one.
        if arranged == nil { dragged = widget.id }
        return NSItemProvider(dragging: widget.id, marked: Self.widgetType)
    }
    /// Habit designs open their habit, the badge its milestones, the week the recap and a routine its habits.
    private func tap(_ widget: DashboardWidget) {
        let habit = widget.habits(in: store.visible).first
        switch widget.kind {
        case .routine: routine = store.visible.routines.first { $0.id == widget.routineID }
        case .week: open(.recap)
        case .today: open(.calendar)
        case .list, .checks: break
        case .badge: if let habit { open(.milestones(habit.id)) }
        default: if let habit { open(.habit(habit.id)) }
        }
    }
    private func check(_ habit: Habit) {
        let goal = habit.goal(on: Day()), p = Engine.progress(habit, day: Day(), data: store.data)
        if goal.tracking == .yesNo || (goal.tap == .addOne && !p.success && goal.mode == .build) { store.quickLog(habit) }
        else { daySelection = DaySelection(habit: habit, day: Day()) }
    }
    private func complete(_ routine: Routine) { withAnimation(.snappy(duration: 0.22)) { _ = store.log(Set(routine.habitIDs)) { try Engine.completeRoutine(routine.id, day: Day(), data: &$0) } } }
    /// The versions of every habit a widget shows, so it redraws only when one of them changes.
    private func versions(_ widget: DashboardWidget) -> [HabitVersion] {
        let ids = widget.kind == .routine ? store.visible.routines.first { $0.id == widget.routineID }?.habitIDs ?? [] : widget.habits(in: store.visible).map(\.id)
        return ids.map(store.version)
    }
    private func update(_ widget: DashboardWidget, _ change: (inout DashboardWidget) -> Void) {
        var list = DashboardLayout.current(store)
        guard let index = list.firstIndex(where: { $0.id == widget.id }) else { return }
        change(&list[index]); DashboardLayout.save(store, list)
    }
    /// Moves the dragged widget to the place under the finger: another widget's place, the free half of a row beside a
    /// lone small widget, the start (above the board) or the end (below it).
    private func hover(_ location: CGPoint) {
        settling?.cancel(); settling = nil
        guard let dragged else { return }
        let shown = widgets
        var order = shown.map(\.id)
        if arranged == nil { arranged = order }
        if let lastMove, hypot(location.x - lastMove.x, location.y - lastMove.y) < 12 { return }
        guard let from = order.firstIndex(of: dragged) else { return }
        let boardFrame = board.frame, point = CGPoint(x: location.x - boardFrame.minX, y: location.y - boardFrame.minY)
        let frames = DashboardGrid.frames(shown.map(\.resolvedSize), width: boardFrame.width, heights: shown.map { board.heights[$0.id] })
        let offset: Int
        if point.y < 0 { offset = 0 }
        else if let hit = frames.firstIndex(where: { $0.contains(point) }) { offset = hit > from ? hit + 1 : hit }
        else if let lone = frames.indices.first(where: { DashboardGrid.freeHalf(after: $0, frames: frames, width: boardFrame.width)?.contains(point) == true }) { offset = lone + 1 }
        else if point.y > boardFrame.height { offset = order.count }
        else { return }
        guard offset != from && offset != from + 1 else { return }
        order.move(fromOffsets: [from], toOffset: offset)
        lastMove = location
        withAnimation(.snappy(duration: 0.3)) { arranged = order }
    }
    /// Saves the order shown once the widget is dropped.
    private func drop() { settle(); dragged = nil }
    /// The drag left the page. The widgets stay put: iOS also reports a leave when the switcher fades, and holding a
    /// widget at the bottom scrolls the page until the finger is below it. If the drag doesn't come back, the order
    /// shown is kept, as when a Home Screen icon is let go.
    private func leave() {
        settling?.cancel()
        settling = Task { try? await Task.sleep(for: .milliseconds(300)); if !Task.isCancelled { settle() } }
    }
    /// Saves the order shown. Hidden widgets keep their places among the rest.
    private func settle() {
        settling?.cancel(); settling = nil
        if let arranged {
            let moved = Set(arranged)
            var list = DashboardLayout.current(store), slots = list.indices.filter { moved.contains(list[$0].id) }
            let byID = Dictionary(list.map { ($0.id, $0) }) { first, _ in first }
            for id in arranged where !slots.isEmpty { if let widget = byID[id] { list[slots.removeFirst()] = widget } }
            if list.map(\.id) != DashboardLayout.current(store).map(\.id) { DashboardLayout.save(store, list) }
        }
        withAnimation(.snappy(duration: 0.3)) { arranged = nil }; lastMove = nil
    }
    private func duplicate(_ widget: DashboardWidget) {
        var list = DashboardLayout.current(store), copy = widget
        copy.id = UUID()
        list.insert(copy, at: list.firstIndex { $0.id == widget.id }.map { $0 + 1 } ?? list.endIndex)
        DashboardLayout.save(store, list)
    }
}

/// One dashboard widget with its background and outline, drawn at the size its frame gives it.
struct DashboardTile: View {
    @Environment(\.colorScheme) private var scheme
    let widget: DashboardWidget
    @ViewData var data: BuddyData
    /// In the app, the versions of the habits the widget shows (see `HabitWidgetContent.versions`).
    var versions: [HabitVersion]?
    var onCheck: ((Habit) -> Void)?
    var onRoutine: ((Routine) -> Void)?
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous), habits = widget.habits(in: data)
        let palette = WidgetPalette(widget.style, scheme: scheme, tint: widget.tint(data))
        HabitWidgetContent(kind: widget.kind, size: widget.resolvedSize, habit: widget.kind.needsHabit ? habits.first : nil, data: data, habits: habits,
                           routine: data.routines.first { $0.id == widget.routineID }, title: widget.title, palette: palette, versions: versions, inDashboard: true, onCheck: onCheck, onRoutine: onRoutine)
            .equatable().frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.background(shape))
            .overlay { shape.strokeBorder(palette.dark ? Color.white.opacity(0.07) : Color.black.opacity(scheme == .dark ? 0 : 0.06), lineWidth: 1) }
    }
}

/// Lays widgets out like the home screen: wide widgets take a full row and consecutive small widgets pair up. The
/// widgets are one flat list of views, so each keeps its identity and slides to its new place when the order changes.
/// Lists report their natural height; the other designs retain their home-screen proportions.
struct DashboardGrid: SwiftUI.Layout {
    var spacing: CGFloat = 16
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        return CGSize(width: width, height: frames(subviews, width: width).map(\.maxY).max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }
    private func frames(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        let heights: [CGFloat?] = subviews.map { $0.containerValues.widgetFitsContent ? $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height : nil }
        return Self.frames(subviews.map(\.containerValues.widgetSize), width: width, spacing: spacing, heights: heights)
    }
    static func frames(_ sizes: [WidgetSize], width: CGFloat, spacing: CGFloat = 16, heights: [CGFloat?] = []) -> [CGRect] {
        let side = (width - spacing) / 2
        var frames: [CGRect] = [], y: CGFloat = 0, left = true
        for (index, size) in sizes.enumerated() {
            if size == .small {
                frames.append(CGRect(x: left ? 0 : side + spacing, y: y, width: side, height: side))
                if !left { y += side + spacing }
                left.toggle()
            } else {
                if !left { y += side + spacing; left = true }
                let standardHeight = size == .large ? side * 2 + spacing : side
                let height = heights.indices.contains(index) ? heights[index] ?? standardHeight : standardHeight
                frames.append(CGRect(x: 0, y: y, width: width, height: height))
                y += height + spacing
            }
        }
        return frames
    }
    /// The empty right half of a row holding one small widget, if the widget at `index` is one.
    static func freeHalf(after index: Int, frames: [CGRect], width: CGFloat, spacing: CGFloat = 16) -> CGRect? {
        let frame = frames[index]
        guard frame.minX == 0, frame.width < width, index + 1 == frames.count || frames[index + 1].minY > frame.minY else { return nil }
        return CGRect(x: frame.maxX + spacing, y: frame.minY, width: frame.width, height: frame.height)
    }
}

/// The board's frame on the page, read only while a widget is dragged, so it's kept where setting it doesn't redraw.
private final class BoardFrame {
    var frame = CGRect.zero
    var heights: [UUID: CGFloat] = [:]
}

/// Follows a widget dragged over the page; dropping it saves the order.
private struct BoardDrop: DropDelegate {
    let over: (CGPoint) -> Void
    let drop: () -> Void
    let leave: () -> Void
    func validateDrop(info: DropInfo) -> Bool { info.carries(DashboardView.widgetType) }
    func dropUpdated(info: DropInfo) -> DropProposal? { over(info.location); return DropProposal(operation: .move) }
    func dropExited(info: DropInfo) { leave() }
    func performDrop(info: DropInfo) -> Bool { drop(); return true }
}

extension ContainerValues {
    /// A dashboard widget's size, which places it in `DashboardGrid`.
    @Entry var widgetSize = WidgetSize.small
    /// Lists fit their rows in the app instead of spreading them across a WidgetKit-sized square.
    @Entry var widgetFitsContent = false
}

enum DashboardLayout {
    /// Small and medium widgets are as tall as a small one is wide; large ones span two rows.
    static func height(_ widget: DashboardWidget, side: CGFloat) -> CGFloat { widget.resolvedSize == .large ? side * 2 + 16 : side }
    @MainActor static func current(_ store: AppStore) -> [DashboardWidget] { store.settings.dashboard ?? DashboardWidget.defaults(for: store.visible.active) }
    /// The first edit stores the arrangement, so later habit changes don't reshuffle it.
    @MainActor static func save(_ store: AppStore, _ widgets: [DashboardWidget]?) { store.change { $0.settings.dashboard = widgets } }
}

struct DashboardEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent
    @State private var configuring: DashboardWidget?
    @State private var adding = false
    private var widgets: [DashboardWidget] { DashboardLayout.current(store) }
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Edit Dashboard")
            List {
                Section {
                    ForEach(widgets) { widget in
                        Button { configuring = widget } label: {
                            HStack(spacing: 12) {
                                SettingsTile(icon: widget.kind.symbol, color: widget.color ?? subjectColor(widget))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(widget.kind.title).font(BuddyFont.text(16, .semibold))
                                    Text(subject(widget)).font(BuddyFont.text(13)).foregroundStyle(BuddyStyle.secondaryText(scheme)).lineLimit(1)
                                }
                                Spacer()
                                Text("\(widget.resolvedSize.title) · \(widget.style.title)").font(BuddyFont.text(13)).foregroundStyle(BuddyStyle.secondaryText(scheme))
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    .onMove { source, destination in var list = widgets; list.move(fromOffsets: source, toOffset: destination); DashboardLayout.save(store, list) }
                    .onDelete { offsets in var list = widgets; list.remove(atOffsets: offsets); DashboardLayout.save(store, list) }
                } footer: { Text("Drag to reorder, swipe to remove, tap to change a widget. On the dashboard, touch and hold a widget to change its size or style, or hold and move it to a new place.").font(BuddyFont.text(12)) }
                Section {
                    Button("Add Widget", systemImage: "plus") { adding = true }.disabled(store.visible.active.isEmpty)
                    Button("Reset to Default Layout", systemImage: "arrow.counterclockwise") { DashboardLayout.save(store, nil) }
                }
            }.scrollContentBackground(.hidden).tint(accent.color)
        }
        .background(BuddyStyle.canvas(scheme))
        .sheet(item: $configuring) { WidgetConfigurator(widget: $0, isNew: false).buddySheet() }
        .sheet(isPresented: $adding) { WidgetConfigurator(widget: DashboardWidget(kind: .streak, habitID: store.visible.active.first?.id), isNew: true).buddySheet() }
    }
    private func subject(_ widget: DashboardWidget) -> String {
        let text: String
        // A hidden habit's name stays out of the list; its widget keeps its place for when the habit is shown again.
        if widget.kind.needsHabit, let habit = widget.habitID.flatMap(store.habit), habit.isHidden { return "Hidden habit" }
        if widget.kind == .routine, store.data.routines.contains(where: { $0.id == widget.routineID }), !store.visible.routines.contains(where: { $0.id == widget.routineID }) { return "Hidden routine" }
        if widget.kind.needsHabit { text = widget.habitID.flatMap { store.habit($0)?.name } ?? "Habit unavailable" }
        else if widget.kind == .routine { text = store.data.routines.first { $0.id == widget.routineID }?.name ?? "Routine deleted" }
        else if widget.habitIDs != nil { let count = widget.habits(in: store.visible).count; text = "\(count) \(count == 1 ? "habit" : "habits")" }
        else { text = "All habits" }
        return widget.visible(in: store.visible) ? text : text + " · hidden"
    }
    private func subjectColor(_ widget: DashboardWidget) -> String {
        if widget.kind.needsHabit { return widget.habitID.flatMap { store.visible.activeHabit($0)?.color } ?? "indigo" }
        if widget.kind == .routine { return store.data.routines.first { $0.id == widget.routineID }?.color ?? "indigo" }
        return "indigo"
    }
}

/// Choose a widget design, its size, what it shows, its title, style and color, with a live preview.
struct WidgetConfigurator: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent
    @State var widget: DashboardWidget
    let isNew: Bool
    /// The page of designs showing: one habit, several habits or a routine. Paging doesn't change the chosen design.
    @State private var group: Int
    @State private var page: Int?
    private static let groups: [(String, [DashboardKind])] = [
        ("One Habit", [.streak, .ring, .stats, .badge, .month, .weeks, .months, .year]),
        ("Several Habits", [.today, .checks, .week, .list]),
        ("Routine", [.routine])]
    init(widget: DashboardWidget, isNew: Bool) {
        _widget = State(initialValue: widget); self.isNew = isNew
        let group = Self.groups.firstIndex { $0.1.contains(widget.kind) } ?? 0
        _group = State(initialValue: group); _page = State(initialValue: group)
    }
    private var valid: Bool {
        if widget.kind.needsHabit { return store.visible.active.contains { $0.id == widget.habitID } }
        if widget.kind == .routine { return store.visible.routines.contains { $0.id == widget.routineID } }
        return true
    }
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: isNew ? "Add Widget" : "Edit Widget")
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    preview
                    .accessibilityElement(children: .ignore).accessibilityLabel("Preview of the \(widget.kind.title) widget")
                    section("Widget") {
                        SegmentedChoice(selection: Binding(get: { group }, set: { index in withAnimation(.snappy(duration: 0.3)) { group = index; page = index } }), options: Self.groups.indices.map { ($0, Self.groups[$0].0) })
                        // One page of designs per tab, three to a row; swiping sideways moves to the next tab.
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(Self.groups.indices, id: \.self) { index in
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                                        ForEach(Self.groups[index].1, id: \.self) { kind in kindButton(kind) }
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 1)
                                    .containerRelativeFrame(.horizontal, alignment: .top)
                                    .id(index)
                                }
                            }.scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.paging)
                        .scrollPosition(id: $page)
                        .frame(height: pagerHeight, alignment: .top).clipped()
                        .padding(.horizontal, -16)
                        .onChange(of: page) { _, index in if let index, index != group { withAnimation(.snappy(duration: 0.2)) { group = index } } }
                    }
                    if widget.kind.sizes.count > 1 {
                        section("Size") { SegmentedChoice(selection: Binding(get: { widget.resolvedSize }, set: { widget.size = $0 }), options: widget.kind.sizesInOrder.map { ($0, $0.title) }) }
                    }
                    if widget.kind.needsHabit { section("Habit") { habitPicker } }
                    if widget.kind.multiHabit { section("Habits") { habitsPicker } }
                    if widget.kind == .routine { section("Routine") { routinePicker } }
                    if widget.kind.showsTitle(widget.resolvedSize) {
                        section("Title") {
                            TextField("", text: Binding(get: { widget.title ?? "" }, set: { widget.title = String($0.prefix(100)) }), prompt: Text(widget.kind.defaultTitle))
                                .accessibilityLabel("Widget title").buddyField()
                        }
                    }
                    section("Style") { SegmentedChoice(selection: $widget.style, options: WidgetStyle.allCases.map { ($0, $0.title) }) }
                    if widget.kind.usesAccent || widget.style == .tinted { section("Color") { colorPicker } }
                    if !isNew {
                        Button(role: .destructive) { DashboardLayout.save(store, DashboardLayout.current(store).filter { $0.id != widget.id }); dismiss() } label: { Text("Remove Widget").font(BuddyFont.text(15, .medium)).frame(maxWidth: .infinity, minHeight: 44) }
                    }
                    Text("Every design is also a home screen widget, in the same sizes: touch and hold the home screen, tap Edit, then Add Widget and search for HabbitShelf. Home screen widgets choose their habits and theme in Edit Widget and keep each habit's color.")
                        .font(BuddyFont.text(12)).foregroundStyle(BuddyStyle.tertiaryText(scheme))
                }.padding(16).padding(.bottom, 80)
            }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        }
        .background(BuddyStyle.canvas(scheme))
        .overlay(alignment: .bottom) {
            PrimaryAction(title: isNew ? "Add Widget" : "Save") { save() }
                .disabled(!valid).accessibilityIdentifier("save-widget").padding(.horizontal, 24).padding(.bottom, 6)
        }
    }
    @ViewBuilder private var preview: some View {
        if widget.kind == .list {
            DashboardTile(widget: widget, data: store.visible)
                .fixedSize(horizontal: false, vertical: true)
                .allowsHitTesting(false)
        } else {
            GeometryReader { proxy in
                let side = (proxy.size.width - 16) / 2
                DashboardTile(widget: widget, data: store.visible)
                    .frame(width: widget.wide ? proxy.size.width : side, height: DashboardLayout.height(widget, side: side))
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity)
                    .animation(.snappy(duration: 0.25), value: widget.resolvedSize)
            }
            .aspectRatio(widget.resolvedSize == .large ? 1 : 2.09, contentMode: .fit)
        }
    }
    private func save() {
        var saved = widget
        if !saved.kind.needsHabit { saved.habitID = nil }
        if !saved.kind.multiHabit { saved.habitIDs = nil }
        if saved.kind != .routine { saved.routineID = nil }
        let title = saved.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        saved.title = saved.kind.multiHabit && !title.isEmpty ? title : nil
        if saved.resolvedSize == saved.kind.sizes[0] { saved.size = nil }
        if !(saved.kind.usesAccent || saved.style == .tinted) { saved.color = nil }
        var list = DashboardLayout.current(store)
        if let index = list.firstIndex(where: { $0.id == saved.id }) { list[index] = saved } else { list.append(saved) }
        DashboardLayout.save(store, list); dismiss()
    }
    /// The pager is as tall as the page showing, so short pages take less room.
    private var pagerHeight: CGFloat { let rows = CGFloat((Self.groups[group].1.count + 2) / 3); return rows * 74 + (rows - 1) * 8 + 2 }
    private func choose(_ kind: DashboardKind) {
        widget.kind = kind
        if let size = widget.size, !kind.sizes.contains(size) { widget.size = nil }
        if kind.needsHabit && !store.visible.active.contains(where: { $0.id == widget.habitID }) { widget.habitID = store.visible.active.first?.id }
        if kind == .routine && widget.routineID == nil { widget.routineID = store.visible.routines.first?.id }
    }
    private func kindButton(_ kind: DashboardKind) -> some View {
        let on = widget.kind == kind
        return Button { withAnimation(.snappy(duration: 0.2)) { choose(kind) } } label: {
            VStack(spacing: 6) {
                LucideIcon(kind.symbol, size: 20)
                Text(kind.title).font(BuddyFont.text(12.5, .medium)).lineLimit(1).minimumScaleFactor(0.8)
                Text(kind.sizesInOrder.map { String($0.title.prefix(1)) }.joined(separator: " · ")).font(BuddyFont.mono(9.5)).foregroundStyle(BuddyStyle.tertiaryText(scheme))
            }
            .foregroundStyle(on ? BuddyStyle.text(scheme) : BuddyStyle.secondaryText(scheme))
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(on ? BuddyStyle.control(scheme) : BuddyStyle.field(scheme), in: RoundedRectangle(cornerRadius: 14, style: .circular))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .circular).strokeBorder(on ? accent.color : BuddyStyle.border(scheme, 0.1), lineWidth: on ? 1.5 : 1) }
        }
        .buttonStyle(.plain).accessibilityLabel(kind.title).accessibilityAddTraits(on ? .isSelected : [])
    }
    private var habitPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.visible.active) { h in
                    chip(selected: widget.habitID == h.id, color: BuddyStyle.color(h.color)) { widget.habitID = h.id } label: { HabitIcon(habit: h, size: 28); Text(h.name) }
                }
            }
        }
    }
    private var habitsPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(selected: widget.habitIDs == nil, color: accent.color) { widget.habitIDs = nil } label: { Text("All Habits").padding(.leading, 6) }
                    ForEach(store.visible.active) { h in
                        let on = widget.habitIDs?.contains(h.id) ?? false
                        chip(selected: on, color: BuddyStyle.color(h.color)) { toggle(h.id) } label: {
                            HabitIcon(habit: h, size: 28); Text(h.name)
                            if on { LucideIcon("check", size: 13).foregroundStyle(BuddyStyle.color(h.color)) }
                        }
                    }
                }
            }
            Text(widget.habitIDs == nil ? "Shows every habit, including ones you add later." : "Shows \(widget.habits(in: store.visible).count) chosen. Tap a habit to add or remove it.")
                .font(BuddyFont.text(12)).foregroundStyle(BuddyStyle.tertiaryText(scheme)).padding(.leading, 5)
        }
    }
    private var routinePicker: some View {
        Group {
            if store.visible.routines.isEmpty {
                Text("No routines yet. Create one in Explore, then Routines, and it appears here.").font(BuddyFont.text(13)).foregroundStyle(BuddyStyle.secondaryText(scheme)).padding(.leading, 5)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.visible.routines) { r in
                            chip(selected: widget.routineID == r.id, color: BuddyStyle.color(r.color)) { widget.routineID = r.id } label: {
                                BuddyGlyph(symbol: r.symbol, size: 15).foregroundStyle(BuddyStyle.color(r.color)).frame(width: 28, height: 28).background(BuddyStyle.color(r.color).opacity(0.14), in: Circle())
                                Text(r.name)
                            }
                        }
                    }
                }
            }
        }
    }
    private var colorPicker: some View {
        let own = widget.kind.needsHabit ? "Habit's Color" : widget.kind == .routine ? "Routine's Color" : "Default"
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(selected: widget.color == nil, color: accent.color) { widget.color = nil } label: { Text(own).padding(.leading, 6) }
                ForEach(BuddyStyle.colors, id: \.0) { token, _ in
                    Button { widget.color = token } label: {
                        Circle().fill(BuddyStyle.color(token)).frame(width: 30, height: 30)
                            .overlay { if widget.color == token { Circle().strokeBorder(BuddyStyle.color(token), lineWidth: 2).padding(-5) } }
                            .frame(width: 42, height: 42).contentShape(Circle())
                    }.buttonStyle(.plain).accessibilityLabel(token).accessibilityAddTraits(widget.color == token ? .isSelected : [])
                }
            }.padding(.vertical, 1)
        }
    }
    private func toggle(_ id: UUID) {
        var chosen = Set(widget.habitIDs ?? [])
        if chosen.contains(id) { chosen.remove(id) } else { chosen.insert(id) }
        // Against every active habit, so a hidden habit stays chosen while it is out of the list.
        widget.habitIDs = chosen.isEmpty ? nil : store.data.active.map(\.id).filter(chosen.contains)
    }
    private func chip<Label: View>(selected: Bool, color: Color, action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            HStack(spacing: 8) { label() }.font(BuddyFont.text(14, .medium)).lineLimit(1)
                .foregroundStyle(BuddyStyle.text(scheme)).padding(.leading, 6).padding(.trailing, 12).frame(height: 42)
                .background(BuddyStyle.field(scheme), in: Capsule())
                .overlay { Capsule().strokeBorder(selected ? color : BuddyStyle.border(scheme, 0.1), lineWidth: selected ? 1.5 : 1) }
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).fieldCaption().foregroundStyle(BuddyStyle.secondaryText(scheme)); content() }
    }
}

extension DashboardWidget {
    /// The widget's own color, else its habit's or routine's, else the app accent.
    func tint(_ data: BuddyData) -> Color {
        if let color { return BuddyStyle.color(color) }
        if kind.needsHabit, let habit = habits(in: data).first { return BuddyStyle.color(habit.color) }
        if kind == .routine, let routine = data.routines.first(where: { $0.id == routineID }) { return BuddyStyle.color(routine.color) }
        return Accent(data.settings.accent).color
    }
}

extension NSItemProvider {
    /// An ID dragged within the app, marked with the kind of thing lifted. Only this app sees it, so dropping it on
    /// another app does nothing.
    convenience init(dragging id: UUID, marked marker: String) {
        self.init()
        let data = Data(id.uuidString.utf8)
        for type in [UTType.utf8PlainText.identifier, marker] {
            registerDataRepresentation(forTypeIdentifier: type, visibility: .ownProcess) { done in done(data, nil); return nil }
        }
    }
}

extension DropInfo {
    /// Whether the drag is something lifted in this app and marked with `type`; text from another app isn't.
    func carries(_ type: String) -> Bool { itemProviders(for: [.utf8PlainText]).contains { $0.hasItemConformingToTypeIdentifier(type) } }
}
