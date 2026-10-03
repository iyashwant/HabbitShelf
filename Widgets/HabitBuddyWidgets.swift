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
    var selectedHabits: [Habit] { guard let selectedIDs,!selectedIDs.isEmpty else{return data.active};return selectedIDs.compactMap{id in data.active.first{$0.id==id}} }
    var habit: Habit? { data.active.first { $0.id == habitID } ?? (habitID == nil ? data.active.first : nil) }
}
struct BuddyProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BuddyEntry { entry(nil) }
    func snapshot(for configuration: ChooseHabitIntent, in context: Context) async -> BuddyEntry { entry(configuration.habit?.id,theme:configuration.theme) }
    func timeline(for configuration: ChooseHabitIntent, in context: Context) async -> Timeline<BuddyEntry> {
        let current = entry(configuration.habit?.id,theme:configuration.theme)
        let midnight = Calendar.current.startOfDay(for: Date()).addingTimeInterval(25 * 3_600)
        let nextMidnight = Calendar.current.startOfDay(for: midnight)
        return Timeline(entries: [current], policy: .after(min(Date().addingTimeInterval(900), nextMidnight)))
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
        } else { VStack(alignment: .leading, spacing: 8) { Image(systemName: "square.grid.3x3.fill").foregroundStyle(BuddyStyle.purple); Text(entry.error ?? "Create a habit, then choose it in Edit Widget.").font(.caption) }.widgetURL(URL(string: "habitbuddy://home")) }
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
                            WidgetHabitAction(habit: habit, day: day, data: entry.data, compact: true).disabled(!habit.available(on: day, today: Day()))
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
    func timeline(for configuration:ChooseCompactHabitsIntent,in context:Context) async->Timeline<BuddyEntry> {Timeline(entries:[entry(configuration.habits?.map(\.id),configuration.theme)],policy:.after(Date().addingTimeInterval(900)))}
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
@main struct HabitBuddyWidgetBundle:WidgetBundle {var body:some Widget {SmallHabitWidget();MediumHabitWidget();CompactHabitsWidget();LargeCompactHabitsWidget()}}
