import SwiftUI

/// A board of habit widgets laid out like the home screen: small widgets take half a row, medium a full row
/// and large a full row at double height.
struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    var open: (OverviewRoute) -> Void
    @State private var editing = false
    @State private var adding = false
    @State private var configuring: DashboardWidget?
    @State private var daySelection: DaySelection?
    @State private var routine: Routine?
    private var widgets: [DashboardWidget] { DashboardLayout.current(store).filter { $0.visible(in: store.data) } }
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width - 32, side = (width - 16) / 2
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Dashboard").font(BuddyFont.text(32, .heavy)).foregroundStyle(BuddyStyle.text(scheme)).padding(.top, 4)
                    if widgets.isEmpty {
                        ContentUnavailableView { Label("No widgets yet", systemImage: "square.grid.2x2") } description: { Text(store.data.active.isEmpty ? "Create a habit, then add widgets for it here." : "Add widgets to keep your habits at a glance.") } actions: { if !store.data.active.isEmpty { Button("Add Widget") { adding = true }.buttonStyle(.borderedProminent) } }
                    }
                    ForEach(DashboardLayout.rows(widgets), id: \.first!.id) { row in
                        HStack(spacing: 16) {
                            ForEach(row) { widget in tile(widget, width: widget.wide ? width : side, height: DashboardLayout.height(widget, side: side)) }
                            if row.count == 1 && !row[0].wide { Spacer(minLength: 0) }
                        }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 40)
            }.scrollIndicators(.hidden)
        }
        .background(BuddyStyle.canvas(scheme)).toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 8) {
                CircleControl(symbol: "chevron-left", label: "Back", size: 38, glyph: 12.5) { dismiss() }
                Spacer()
                CircleControl(symbol: "sliders-horizontal", label: "Edit Dashboard", size: 38, glyph: 16) { editing = true }
                CircleControl(symbol: "plus", label: "Add Widget", filled: true, size: 38, glyph: 17) { adding = true }.disabled(store.data.active.isEmpty)
            }.padding(.horizontal, 12).padding(.top, 8.8).padding(.bottom, 8).background(BuddyStyle.canvas(scheme))
        }
        .sheet(isPresented: $editing) { DashboardEditorView().buddySheet() }
        .sheet(isPresented: $adding) { WidgetConfigurator(widget: DashboardWidget(kind: .streak, habitID: store.data.active.first?.id), isNew: true).buddySheet() }
        .sheet(item: $configuring) { WidgetConfigurator(widget: $0, isNew: false).buddySheet() }
        .sheet(item: $daySelection) { DayEditorView(selection: $0) }
        .sheet(item: $routine) { RoutineSheet(routineID: $0.id).buddySheet().presentationDetents([.medium, .large]) }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["BUDDY_VISUAL_SCREEN"] == "widget-config" { configuring = DashboardWidget(kind: .checks, style: .tinted) }
            #endif
        }
    }
    private func tile(_ widget: DashboardWidget, width: CGFloat, height: CGFloat) -> some View {
        DashboardTile(widget: widget, data: store.data, onCheck: check, onRoutine: complete)
            .frame(width: width, height: height)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onTapGesture { tap(widget) }
            .contextMenu {
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
    }
    /// Habit designs open their habit, the badge its milestones, the week the recap and a routine its habits.
    private func tap(_ widget: DashboardWidget) {
        let habit = widget.habits(in: store.data).first
        switch widget.kind {
        case .routine: routine = store.data.routines.first { $0.id == widget.routineID }
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
    private func complete(_ routine: Routine) { withAnimation(.snappy(duration: 0.22)) { _ = store.change { try Engine.completeRoutine(routine.id, day: Day(), data: &$0) } } }
    private func update(_ widget: DashboardWidget, _ change: (inout DashboardWidget) -> Void) {
        var list = DashboardLayout.current(store)
        guard let index = list.firstIndex(where: { $0.id == widget.id }) else { return }
        change(&list[index]); DashboardLayout.save(store, list)
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
    let data: BuddyData
    var onCheck: ((Habit) -> Void)?
    var onRoutine: ((Routine) -> Void)?
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous), habits = widget.habits(in: data)
        let palette = WidgetPalette(widget.style, scheme: scheme, tint: widget.tint(data))
        HabitWidgetContent(kind: widget.kind, size: widget.resolvedSize, habit: widget.kind.needsHabit ? habits.first : nil, data: data, habits: habits,
                           routine: data.routines.first { $0.id == widget.routineID }, title: widget.title, palette: palette, onCheck: onCheck, onRoutine: onRoutine)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.background(shape))
            .overlay { shape.strokeBorder(palette.dark ? Color.white.opacity(0.07) : Color.black.opacity(scheme == .dark ? 0 : 0.06), lineWidth: 1) }
    }
}

enum DashboardLayout {
    /// Wide widgets take a full row; consecutive small widgets pair up.
    static func rows(_ items: [DashboardWidget]) -> [[DashboardWidget]] {
        var rows: [[DashboardWidget]] = [], pending: DashboardWidget?
        for widget in items {
            if widget.wide { if let p = pending { rows.append([p]); pending = nil }; rows.append([widget]) }
            else if let p = pending { rows.append([p, widget]); pending = nil }
            else { pending = widget }
        }
        if let pending { rows.append([pending]) }
        return rows
    }
    /// Small and medium widgets are as tall as a small one is wide; large ones span two rows.
    static func height(_ widget: DashboardWidget, side: CGFloat) -> CGFloat { widget.resolvedSize == .large ? side * 2 + 16 : side }
    @MainActor static func current(_ store: AppStore) -> [DashboardWidget] { store.data.settings.dashboard ?? DashboardWidget.defaults(for: store.data.active) }
    /// The first edit stores the arrangement, so later habit changes don't reshuffle it.
    @MainActor static func save(_ store: AppStore, _ widgets: [DashboardWidget]?) { store.change { $0.settings.dashboard = widgets } }
}

struct DashboardEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme
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
                } footer: { Text("Drag to reorder, swipe to remove, tap to change a widget. Touch and hold a widget on the dashboard to change its size or style.").font(BuddyFont.text(12)) }
                Section {
                    Button("Add Widget", systemImage: "plus") { adding = true }.disabled(store.data.active.isEmpty)
                    Button("Reset to Default Layout", systemImage: "arrow.counterclockwise") { DashboardLayout.save(store, nil) }
                }
            }.scrollContentBackground(.hidden).tint(BuddyStyle.purple)
        }
        .background(BuddyStyle.canvas(scheme))
        .sheet(item: $configuring) { WidgetConfigurator(widget: $0, isNew: false).buddySheet() }
        .sheet(isPresented: $adding) { WidgetConfigurator(widget: DashboardWidget(kind: .streak, habitID: store.data.active.first?.id), isNew: true).buddySheet() }
    }
    private func subject(_ widget: DashboardWidget) -> String {
        let text: String
        if widget.kind.needsHabit { text = widget.habitID.flatMap { store.habit($0)?.name } ?? "Habit unavailable" }
        else if widget.kind == .routine { text = store.data.routines.first { $0.id == widget.routineID }?.name ?? "Routine deleted" }
        else if widget.habitIDs != nil { let count = widget.habits(in: store.data).count; text = "\(count) \(count == 1 ? "habit" : "habits")" }
        else { text = "All habits" }
        return widget.visible(in: store.data) ? text : text + " · hidden"
    }
    private func subjectColor(_ widget: DashboardWidget) -> String {
        if widget.kind.needsHabit { return widget.habitID.flatMap { store.habit($0)?.color } ?? "indigo" }
        if widget.kind == .routine { return store.data.routines.first { $0.id == widget.routineID }?.color ?? "indigo" }
        return "indigo"
    }
}

/// Choose a widget design, its size, what it shows, its title, style and color, with a live preview.
struct WidgetConfigurator: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
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
        if widget.kind.needsHabit { return store.data.active.contains { $0.id == widget.habitID } }
        if widget.kind == .routine { return store.data.routines.contains { $0.id == widget.routineID } }
        return true
    }
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: isNew ? "Add Widget" : "Edit Widget")
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GeometryReader { proxy in
                        let side = (proxy.size.width - 16) / 2
                        DashboardTile(widget: widget, data: store.data)
                            .frame(width: widget.wide ? proxy.size.width : side, height: DashboardLayout.height(widget, side: side))
                            .allowsHitTesting(false)
                            .frame(maxWidth: .infinity)
                            .animation(.snappy(duration: 0.25), value: widget.resolvedSize)
                    }
                    .aspectRatio(widget.resolvedSize == .large ? 1 : 2.09, contentMode: .fit)
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
                    Text("Every design is also a home screen widget, in the same sizes: touch and hold the home screen, tap Edit, then Add Widget and search for Habit Buddy. Home screen widgets choose their habits and theme in Edit Widget and keep each habit's color.")
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
        if kind.needsHabit && !store.data.active.contains(where: { $0.id == widget.habitID }) { widget.habitID = store.data.active.first?.id }
        if kind == .routine && widget.routineID == nil { widget.routineID = store.data.routines.first?.id }
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
            .overlay { RoundedRectangle(cornerRadius: 14, style: .circular).strokeBorder(on ? BuddyStyle.purple : BuddyStyle.border(scheme, 0.1), lineWidth: on ? 1.5 : 1) }
        }
        .buttonStyle(.plain).accessibilityLabel(kind.title).accessibilityAddTraits(on ? .isSelected : [])
    }
    private var habitPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.data.active) { h in
                    chip(selected: widget.habitID == h.id, color: BuddyStyle.color(h.color)) { widget.habitID = h.id } label: { HabitIcon(habit: h, size: 28); Text(h.name) }
                }
            }
        }
    }
    private var habitsPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(selected: widget.habitIDs == nil, color: BuddyStyle.purple) { widget.habitIDs = nil } label: { Text("All Habits").padding(.leading, 6) }
                    ForEach(store.data.active) { h in
                        let on = widget.habitIDs?.contains(h.id) ?? false
                        chip(selected: on, color: BuddyStyle.color(h.color)) { toggle(h.id) } label: {
                            HabitIcon(habit: h, size: 28); Text(h.name)
                            if on { LucideIcon("check", size: 13).foregroundStyle(BuddyStyle.color(h.color)) }
                        }
                    }
                }
            }
            Text(widget.habitIDs == nil ? "Shows every habit, including ones you add later." : "Shows \(widget.habits(in: store.data).count) chosen. Tap a habit to add or remove it.")
                .font(BuddyFont.text(12)).foregroundStyle(BuddyStyle.tertiaryText(scheme)).padding(.leading, 5)
        }
    }
    private var routinePicker: some View {
        Group {
            if store.data.routines.isEmpty {
                Text("No routines yet. Create one in Explore, then Routines, and it appears here.").font(BuddyFont.text(13)).foregroundStyle(BuddyStyle.secondaryText(scheme)).padding(.leading, 5)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.data.routines) { r in
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
                chip(selected: widget.color == nil, color: BuddyStyle.purple) { widget.color = nil } label: { Text(own).padding(.leading, 6) }
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
    /// The widget's own color, else its habit's or routine's, else violet.
    func tint(_ data: BuddyData) -> Color {
        if let color { return BuddyStyle.color(color) }
        if kind.needsHabit, let habit = habits(in: data).first { return BuddyStyle.color(habit.color) }
        if kind == .routine, let routine = data.routines.first(where: { $0.id == routineID }) { return BuddyStyle.color(routine.color) }
        return BuddyStyle.purple
    }
}
