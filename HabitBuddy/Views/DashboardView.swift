import SwiftUI

/// A board of habit widgets laid out like the home screen: small widgets take half a row.
struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    var open: (UUID) -> Void
    @State private var editing = false
    @State private var adding = false
    @State private var configuring: DashboardWidget?
    @State private var daySelection: DaySelection?
    private var widgets: [DashboardWidget] { (store.data.settings.dashboard ?? DashboardWidget.defaults(for: store.data.active)).filter { !$0.kind.needsHabit || habit($0) != nil } }
    private func habit(_ widget: DashboardWidget) -> Habit? { widget.habitID.flatMap { id in store.data.active.first { $0.id == id } } }
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
                            ForEach(row) { widget in tile(widget, width: widget.kind.wide ? width : side, height: widget.kind == .list ? side * 2 + 16 : side) }
                            if row.count == 1 && !row[0].kind.wide { Spacer(minLength: 0) }
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
    }
    private func tile(_ widget: DashboardWidget, width: CGFloat, height: CGFloat) -> some View {
        let h = habit(widget), shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let palette = WidgetPalette(widget.style, scheme: scheme, tint: h.map { BuddyStyle.color($0.color) } ?? BuddyStyle.purple)
        return HabitWidgetContent(kind: widget.kind, habit: h, data: store.data, habits: store.data.active, palette: palette, onCheck: check)
            .frame(width: width, height: height)
            .background(palette.background(shape))
            .overlay { shape.strokeBorder(palette.dark ? Color.white.opacity(0.07) : Color.black.opacity(scheme == .dark ? 0 : 0.06), lineWidth: 1) }
            .contentShape(shape)
            .onTapGesture { if let h { open(h.id) } }
            .contextMenu {
                Button("Edit Widget", systemImage: "slider.horizontal.3") { configuring = widget }
                Button("Remove Widget", systemImage: "trash", role: .destructive) { DashboardLayout.save(store, DashboardLayout.current(store).filter { $0.id != widget.id }) }
            }
    }
    private func check(_ habit: Habit) {
        let goal = habit.goal(on: Day()), p = Engine.progress(habit, day: Day(), data: store.data)
        if goal.tracking == .yesNo || (goal.tap == .addOne && !p.success && goal.mode == .build) { store.quickLog(habit) }
        else { daySelection = DaySelection(habit: habit, day: Day()) }
    }
}

enum DashboardLayout {
    /// Wide widgets take a full row; consecutive small widgets pair up.
    static func rows(_ items: [DashboardWidget]) -> [[DashboardWidget]] {
        var rows: [[DashboardWidget]] = [], pending: DashboardWidget?
        for widget in items {
            if widget.kind.wide { if let p = pending { rows.append([p]); pending = nil }; rows.append([widget]) }
            else if let p = pending { rows.append([p, widget]); pending = nil }
            else { pending = widget }
        }
        if let pending { rows.append([pending]) }
        return rows
    }
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
                                SettingsTile(icon: widget.kind.symbol, color: store.habit(widget.habitID ?? UUID())?.color ?? "indigo")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(widget.kind.title).font(BuddyFont.text(16, .semibold))
                                    Text(widget.kind.needsHabit ? store.habit(widget.habitID ?? UUID())?.name ?? "Habit unavailable" : "All habits").font(BuddyFont.text(13)).foregroundStyle(BuddyStyle.secondaryText(scheme))
                                }
                                Spacer()
                                Text(widget.style.title).font(BuddyFont.text(13)).foregroundStyle(BuddyStyle.secondaryText(scheme))
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    .onMove { source, destination in var list = widgets; list.move(fromOffsets: source, toOffset: destination); DashboardLayout.save(store, list) }
                    .onDelete { offsets in var list = widgets; list.remove(atOffsets: offsets); DashboardLayout.save(store, list) }
                } footer: { Text("Drag to reorder, swipe to remove, tap to change a widget.").font(BuddyFont.text(12)) }
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
}

/// Choose a widget design, its habit and style, with a live preview.
struct WidgetConfigurator: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State var widget: DashboardWidget
    let isNew: Bool
    private var habit: Habit? { widget.habitID.flatMap { id in store.data.active.first { $0.id == id } } }
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: isNew ? "Add Widget" : "Edit Widget")
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GeometryReader { proxy in
                        let side = (proxy.size.width - 16) / 2, shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
                        let palette = WidgetPalette(widget.style, scheme: scheme, tint: habit.map { BuddyStyle.color($0.color) } ?? BuddyStyle.purple)
                        HabitWidgetContent(kind: widget.kind, habit: widget.kind.needsHabit ? habit : nil, data: store.data, habits: store.data.active, palette: palette)
                            .frame(width: widget.kind.wide ? proxy.size.width : side, height: widget.kind == .list ? side * 2 + 16 : side)
                            .background(palette.background(shape))
                            .overlay { shape.strokeBorder(palette.dark ? Color.white.opacity(0.07) : Color.black.opacity(0.06), lineWidth: 1) }
                            .allowsHitTesting(false)
                            .frame(maxWidth: .infinity)
                    }.aspectRatio(widget.kind == .list ? 1 : 2.09, contentMode: .fit)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Widget").fieldCaption().foregroundStyle(BuddyStyle.secondaryText(scheme))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(DashboardKind.allCases, id: \.self) { kind in
                                Button { widget.kind = kind; if kind.needsHabit && widget.habitID == nil { widget.habitID = store.data.active.first?.id } } label: {
                                    VStack(spacing: 6) { LucideIcon(kind.symbol, size: 20); Text(kind.title).font(BuddyFont.text(12.5, .medium)).lineLimit(1).minimumScaleFactor(0.8) }
                                        .foregroundStyle(widget.kind == kind ? BuddyStyle.text(scheme) : BuddyStyle.secondaryText(scheme))
                                        .frame(maxWidth: .infinity, minHeight: 64)
                                        .background(widget.kind == kind ? BuddyStyle.control(scheme) : BuddyStyle.field(scheme), in: RoundedRectangle(cornerRadius: 14, style: .circular))
                                        .overlay { RoundedRectangle(cornerRadius: 14, style: .circular).strokeBorder(widget.kind == kind ? BuddyStyle.purple : BuddyStyle.border(scheme, 0.1), lineWidth: widget.kind == kind ? 1.5 : 1) }
                                }.buttonStyle(.plain).accessibilityAddTraits(widget.kind == kind ? .isSelected : [])
                            }
                        }
                    }
                    if widget.kind.needsHabit {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Habit").fieldCaption().foregroundStyle(BuddyStyle.secondaryText(scheme))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(store.data.active) { h in
                                        Button { widget.habitID = h.id } label: {
                                            HStack(spacing: 8) { HabitIcon(habit: h, size: 28); Text(h.name).font(BuddyFont.text(14, .medium)).lineLimit(1) }
                                                .foregroundStyle(BuddyStyle.text(scheme)).padding(.leading, 6).padding(.trailing, 12).frame(height: 42)
                                                .background(BuddyStyle.field(scheme), in: Capsule())
                                                .overlay { Capsule().strokeBorder(widget.habitID == h.id ? BuddyStyle.color(h.color) : BuddyStyle.border(scheme, 0.1), lineWidth: widget.habitID == h.id ? 1.5 : 1) }
                                        }.buttonStyle(.plain).accessibilityAddTraits(widget.habitID == h.id ? .isSelected : [])
                                    }
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Style").fieldCaption().foregroundStyle(BuddyStyle.secondaryText(scheme))
                        SegmentedChoice(selection: $widget.style, options: WidgetStyle.allCases.map { ($0, $0.title) })
                    }
                    if !isNew {
                        Button(role: .destructive) { DashboardLayout.save(store, DashboardLayout.current(store).filter { $0.id != widget.id }); dismiss() } label: { Text("Remove Widget").font(BuddyFont.text(15, .medium)).frame(maxWidth: .infinity, minHeight: 44) }
                    }
                    Text("The same designs are available as home screen widgets: touch and hold the home screen, tap Edit, then Add Widget and search for Habit Buddy.").font(BuddyFont.text(12)).foregroundStyle(BuddyStyle.tertiaryText(scheme))
                }.padding(16).padding(.bottom, 80)
            }.scrollIndicators(.hidden)
        }
        .background(BuddyStyle.canvas(scheme))
        .overlay(alignment: .bottom) {
            PrimaryAction(title: isNew ? "Add Widget" : "Save") {
                var list = DashboardLayout.current(store)
                if let index = list.firstIndex(where: { $0.id == widget.id }) { list[index] = widget } else { list.append(widget) }
                if !widget.kind.needsHabit { list[list.firstIndex(where: { $0.id == widget.id })!].habitID = nil }
                DashboardLayout.save(store, list); dismiss()
            }.disabled(widget.kind.needsHabit && habit == nil).accessibilityIdentifier("save-widget").padding(.horizontal, 24).padding(.bottom, 6)
        }
    }
}
