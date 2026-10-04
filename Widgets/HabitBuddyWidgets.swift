import SwiftUI
import WidgetKit
import AppIntents

struct BuddyEntry: TimelineEntry {
    let date: Date
    let data: BuddyData
    let habitID: UUID?
    let error: String?
    var selectedIDs: [UUID]?
    var theme: WidgetAppearance = .system
    var routineID: UUID?
    /// Active habits in order, sorted once for the entry rather than on every lookup.
    let active: [Habit]
    /// The chosen habit or routine is hidden in the app, so the widget shows neither it nor its name.
    let hidden: Bool
    /// `data` is kept without hidden habits (see `BuddyData.withoutHidden`), so no design shows them.
    init(date: Date, data: BuddyData, habitID: UUID?, error: String?, selectedIDs: [UUID]? = nil, theme: WidgetAppearance = .system, routineID: UUID? = nil) {
        let shown = data.withoutHidden
        self.date = date; self.data = shown; self.habitID = habitID; self.error = error; self.selectedIDs = selectedIDs; self.theme = theme; self.routineID = routineID
        active = shown.active
        hidden = data.habits.contains { $0.id == habitID && $0.isHidden } || (routineID != nil && data.routines.contains { $0.id == routineID } && !shown.routines.contains { $0.id == routineID })
    }
    static let hiddenMessage = "Hidden in Habit Buddy."
    var selectedHabits: [Habit] {
        guard let selectedIDs, !selectedIDs.isEmpty else { return active }
        let byID = Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return selectedIDs.compactMap { byID[$0] }
    }
    var habit: Habit? { active.first { $0.id == habitID } ?? (habitID == nil ? active.first : nil) }
    /// The chosen routine, or the first one until a routine is chosen.
    var routine: Routine? { data.routines.first { $0.id == routineID } ?? (routineID == nil ? data.routines.first : nil) }
}
struct BuddyProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BuddyEntry { entry(nil) }
    func snapshot(for configuration: ChooseHabitIntent, in context: Context) async -> BuddyEntry { entry(configuration.habit?.id,theme:configuration.theme) }
    func timeline(for configuration: ChooseHabitIntent, in context: Context) async -> Timeline<BuddyEntry> {
        Timeline(entries: [entry(configuration.habit?.id,theme:configuration.theme)], policy: .after(nextRefresh()))
    }
    private func entry(_ id: UUID?,theme:WidgetAppearance = .system) -> BuddyEntry {
        guard AppEnvironment.hasSharedContainer else { return BuddyEntry(date: Date(), data: BuddyData(), habitID: id, error: "Configure App Group storage in Xcode.") }
        do { return BuddyEntry(date: Date(), data: try AppEnvironment.repository.load(), habitID: id, error: nil,theme:theme) }
        catch { return BuddyEntry(date: Date(), data: BuddyData(), habitID: id, error: "Open Habit Buddy to recover your data.") }
    }
}
struct SingleHabitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BuddyEntry
    var body: some View {
        if let habit = entry.habit {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HabitIcon(habit: habit, size: 28)
                    VStack(alignment: .leading) { Text(habit.name).font(.caption.weight(.semibold)).lineLimit(1); if family != .systemSmall && !habit.detail.isEmpty { Text(habit.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) } }
                    Spacer(minLength: 0)
                    WidgetHabitAction(habit: habit, day: Day(entry.date), data: entry.data)
                }
                Heatmap(habit: habit, data: entry.data, weeks: family == .systemSmall ? 12 : 25, labels: false).frame(maxHeight: .infinity)
            }.widgetURL(URL(string: "habitbuddy://\(habit.id.uuidString)"))
        } else { VStack(alignment: .leading, spacing: 8) { Image(systemName: "square.grid.3x3.fill").foregroundStyle(Accent(entry.data.settings.accent).color); Text(entry.error ?? (entry.hidden ? BuddyEntry.hiddenMessage : "Create a habit, then choose it in Edit Widget.")).font(.caption) }.widgetURL(URL(string: "habitbuddy://home")) }
    }
}
struct CompactHabitsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BuddyEntry
    var body: some View {
        let count = family == .systemLarge ? 8 : 3
        let days = family == .systemLarge ? 11 : 10
        if entry.selectedHabits.isEmpty { Text(entry.error ?? "Create habits in Habit Buddy.").font(.caption).widgetURL(URL(string: "habitbuddy://home")) }
        else {
            VStack(spacing: 6) {
                ForEach(entry.selectedHabits.prefix(count)) { habit in
                    HStack(spacing: 5) {
                        Link(destination: URL(string: "habitbuddy://\(habit.id.uuidString)")!) { HabitIcon(habit: habit, size: 23) }
                        ForEach(Day.range(Day(entry.date).adding(-(days - 1)), Day(entry.date))) { day in
                            WidgetHabitAction(habit: habit, day: day, data: entry.data, compact: true).disabled(!habit.loggable(on: day, today: Day()))
                        }
                    }.frame(maxHeight: .infinity)
                }
            }
        }
    }
}
struct WidgetHabitAction: View {
    let habit: Habit
    let day: Day
    let data: BuddyData
    var compact = false
    var body: some View {
        let goal = habit.goal(on: day), p = Engine.progress(habit, day: day, data: data)
        if goal.tracking != .yesNo && (goal.mode == .quit || goal.tap == .enterTotal || p.success) {
            Link(destination: URL(string: "habitbuddy://\(habit.id.uuidString)?day=\(day.rawValue)")!) { label }
        } else {
            Button(intent: WidgetLogIntent(habit.id, day: day)) { label }.buttonStyle(.plain)
        }
    }
    @ViewBuilder private var label: some View {
        if compact { DayTile(habit: habit, day: day, data: data, size: 22) }
        else { CompletionBadge(habit: habit, data: data, day: day, size: 28).accessibilityLabel("Log \(habit.name)") }
    }
}

struct CompactBuddyProvider: AppIntentTimelineProvider {
    func placeholder(in context:Context)->BuddyEntry { entry(nil,.system) }
    func snapshot(for configuration:ChooseCompactHabitsIntent,in context:Context) async->BuddyEntry { entry(configuration.habits?.map(\.id),configuration.theme) }
    func timeline(for configuration:ChooseCompactHabitsIntent,in context:Context) async->Timeline<BuddyEntry> {Timeline(entries:[entry(configuration.habits?.map(\.id),configuration.theme)],policy:.after(nextRefresh()))}
    private func entry(_ ids:[UUID]?,_ theme:WidgetAppearance)->BuddyEntry {
        guard AppEnvironment.hasSharedContainer else{return BuddyEntry(date:Date(),data:BuddyData(),habitID:nil,error:"Open Habit Buddy to set up widgets.",selectedIDs:ids,theme:theme)}
        do{return BuddyEntry(date:Date(),data:try AppEnvironment.repository.load(),habitID:nil,error:nil,selectedIDs:ids,theme:theme)}catch{return BuddyEntry(date:Date(),data:BuddyData(),habitID:nil,error:"Open Habit Buddy to recover your data.",selectedIDs:ids,theme:theme)}
    }
}
struct WidgetSurface<Content:View>:View {
    @Environment(\.colorScheme) private var system
    let theme:WidgetAppearance
    @ViewBuilder var content:()->Content
    private var scheme:ColorScheme{theme == .dark ? .dark:theme == .light ? .light:system}
    var body:some View {content().environment(\.colorScheme,scheme).containerBackground(for:.widget){BuddyStyle.surface(scheme)}}
}
struct SmallHabitWidget:Widget {
    let kind="SingleHabit"
    var body:some WidgetConfiguration{AppIntentConfiguration(kind:kind,intent:ChooseHabitIntent.self,provider:BuddyProvider()){entry in WidgetSurface(theme:entry.theme){SingleHabitWidgetView(entry:entry)}}.configurationDisplayName("Small Habit Widget").description("Your habit grid and a quick check-in.").supportedFamilies([.systemSmall])}
}
struct MediumHabitWidget:Widget {
    let kind="MediumHabit"
    var body:some WidgetConfiguration{AppIntentConfiguration(kind:kind,intent:ChooseHabitIntent.self,provider:BuddyProvider()){entry in WidgetSurface(theme:entry.theme){SingleHabitWidgetView(entry:entry)}}.configurationDisplayName("Medium Habit Widget").description("A wide grid for one habit.").supportedFamilies([.systemMedium])}
}
struct CompactHabitsWidget:Widget {
    let kind="CompactHabits"
    var body:some WidgetConfiguration{AppIntentConfiguration(kind:kind,intent:ChooseCompactHabitsIntent.self,provider:CompactBuddyProvider()){entry in WidgetSurface(theme:entry.theme){CompactHabitsWidgetView(entry:entry)}}.configurationDisplayName("Compact Habit List").description("Three habits with ten recent days.").supportedFamilies([.systemMedium])}
}
struct LargeCompactHabitsWidget:Widget {
    let kind="CompactHabitsLarge"
    var body:some WidgetConfiguration{AppIntentConfiguration(kind:kind,intent:ChooseCompactHabitsIntent.self,provider:CompactBuddyProvider()){entry in WidgetSurface(theme:entry.theme){CompactHabitsWidgetView(entry:entry)}}.configurationDisplayName("Compact Habit List Large").description("Eight habits with eleven recent days.").supportedFamilies([.systemLarge])}
}
/// Home-screen versions of the dashboard designs, drawn by the same views as the in-app dashboard at the widget's size.
struct DashboardHomeWidget: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    @Environment(\.widgetFamily) private var family
    let entry: BuddyEntry
    let kind: DashboardKind
    var body: some View {
        let habit = kind.needsHabit ? entry.habit : nil, routine = kind == .routine ? entry.routine : nil, today = Day(entry.date)
        let tint = habit.map { BuddyStyle.color($0.color) } ?? routine.map { BuddyStyle.color($0.color) } ?? Accent(entry.data.settings.accent).color
        let size: WidgetSize = family == .systemLarge ? .large : family == .systemMedium ? .medium : .small
        // StandBy removes the background and shows widgets on black, so light styles switch to dark there.
        let palette = WidgetPalette(showsBackground ? entry.theme.style : .dark, scheme: showsBackground ? scheme : .dark, tint: tint)
        Group {
            if let error = entry.error { message(error, palette) }
            else if kind.needsHabit && habit == nil { message(entry.hidden ? BuddyEntry.hiddenMessage : "Create a habit, then choose it in Edit Widget.", palette) }
            else if kind == .routine && routine == nil { message(entry.hidden ? BuddyEntry.hiddenMessage : "Create a routine in Habit Buddy, then choose it in Edit Widget.", palette) }
            else { HabitWidgetContent(kind: kind, size: size, habit: habit, data: entry.data, habits: entry.selectedHabits, routine: routine, today: today, palette: palette) }
        }
        .containerBackground(for: .widget) { palette.background(Rectangle()) }
        .widgetURL(URL(string: link(habit)))
    }
    private func message(_ text: String, _ palette: WidgetPalette) -> some View {
        Text(text).font(BuddyFont.text(13)).foregroundStyle(palette.secondary).multilineTextAlignment(.center).padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func link(_ habit: Habit?) -> String {
        switch kind {
        case .today: "habitbuddy://today"
        case .week: "habitbuddy://recap"
        case .routine: "habitbuddy://routines"
        default: habit.map { "habitbuddy://\($0.id.uuidString)" } ?? "habitbuddy://home"
        }
    }
}
struct StreakHomeWidget: Widget {
    var body: some WidgetConfiguration { AppIntentConfiguration(kind: "Streak", intent: ChooseHabitIntent.self, provider: BuddyProvider()) { DashboardHomeWidget(entry: $0, kind: .streak) }.configurationDisplayName("Streak").description("Your streak, today's check and this week.").supportedFamilies([.systemSmall]).contentMarginsDisabled() }
}
struct MonthHomeWidget: Widget {
    var body: some WidgetConfiguration { AppIntentConfiguration(kind: "Month", intent: ChooseHabitIntent.self, provider: BuddyProvider()) { DashboardHomeWidget(entry: $0, kind: .month) }.configurationDisplayName("This Month").description("This month's days and a quick check-in. The large size numbers each day.").supportedFamilies([.systemSmall, .systemLarge]).contentMarginsDisabled() }
}
struct WeeksHomeWidget: Widget {
    var body: some WidgetConfiguration { AppIntentConfiguration(kind: "Weeks", intent: ChooseHabitIntent.self, provider: BuddyProvider()) { DashboardHomeWidget(entry: $0, kind: .weeks) }.configurationDisplayName("20 Weeks").description("The last 20 weeks with weekday rows.").supportedFamilies([.systemMedium]).contentMarginsDisabled() }
}
struct ThreeMonthsHomeWidget: Widget {
    var body: some WidgetConfiguration { AppIntentConfiguration(kind: "ThreeMonths", intent: ChooseHabitIntent.self, provider: BuddyProvider()) { DashboardHomeWidget(entry: $0, kind: .months) }.configurationDisplayName("Three Months").description("This month and the two before it.").supportedFamilies([.systemMedium]).contentMarginsDisabled() }
}
struct TodayListHomeWidget: Widget {
    var body: some WidgetConfiguration { AppIntentConfiguration(kind: "TodayList", intent: ChooseCompactHabitsIntent.self, provider: CompactBuddyProvider()) { DashboardHomeWidget(entry: $0, kind: .list) }.configurationDisplayName("Today List").description("Your habits with this week and their streaks: three in medium, six in large.").supportedFamilies([.systemMedium, .systemLarge]).contentMarginsDisabled() }
}
struct DashboardWidgetBundle: WidgetBundle {
    var body: some Widget { StreakHomeWidget(); MonthHomeWidget(); WeeksHomeWidget(); ThreeMonthsHomeWidget(); TodayListHomeWidget() }
}
@main struct HabitBuddyWidgetBundle:WidgetBundle {init(){_ = BuddyIcons.registered};var body:some Widget {SmallHabitWidget();MediumHabitWidget();CompactHabitsWidget();LargeCompactHabitsWidget();DashboardWidgetBundle().body;MoreWidgetBundle().body;DesignWidgetBundle().body}}
