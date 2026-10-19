import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Refresh every 15 minutes and just after midnight, when "today" changes. Calendar day addition finds the next
/// midnight on 23- and 25-hour days too, where adding 86,400 seconds can land on the same day.
func nextRefresh(now: Date = Date(), calendar: Calendar = .current) -> Date {
    let today = calendar.startOfDay(for: now)
    let midnight = calendar.date(byAdding: .day, value: 1, to: today).map { calendar.startOfDay(for: $0.addingTimeInterval(3_600)) } ?? now.addingTimeInterval(86_400)
    return min(now.addingTimeInterval(900), midnight.addingTimeInterval(60))
}
func loadEntry(habitID: UUID? = nil, selectedIDs: [UUID]? = nil, routineID: UUID? = nil, theme: WidgetAppearance = .system) -> BuddyEntry {
    guard AppEnvironment.hasSharedContainer else { return BuddyEntry(date: Date(), data: BuddyData(), habitID: habitID, error: "Open HabitShelf to set up widgets.", selectedIDs: selectedIDs, theme: theme, routineID: routineID) }
    do { return BuddyEntry(date: Date(), data: try AppEnvironment.repository.load(), habitID: habitID, error: nil, selectedIDs: selectedIDs, theme: theme, routineID: routineID) }
    catch { return BuddyEntry(date: Date(), data: BuddyData(), habitID: habitID, error: "Open HabitShelf to recover your data.", selectedIDs: selectedIDs, theme: theme, routineID: routineID) }
}

// MARK: Home Screen and StandBy

struct TodayHomeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TodayRing", intent: ChooseCompactHabitsIntent.self, provider: CompactBuddyProvider()) { DashboardHomeWidget(entry: $0, kind: .today) }
            .configurationDisplayName("Today Ring").description("Today's habits as a ring of colors; the medium size lists what's left. Made for StandBy, too.").supportedFamilies([.systemSmall, .systemMedium]).contentMarginsDisabled()
    }
}

// MARK: Lock Screen

struct LockHabitProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BuddyEntry { loadEntry() }
    func snapshot(for configuration: ChooseLockHabitIntent, in context: Context) async -> BuddyEntry { loadEntry(habitID: configuration.habit?.id) }
    func timeline(for configuration: ChooseLockHabitIntent, in context: Context) async -> Timeline<BuddyEntry> { Timeline(entries: [loadEntry(habitID: configuration.habit?.id)], policy: .after(nextRefresh())) }
}
struct LockHabitsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BuddyEntry { loadEntry() }
    func snapshot(for configuration: ChooseLockHabitsIntent, in context: Context) async -> BuddyEntry { loadEntry(selectedIDs: configuration.habits?.map(\.id)) }
    func timeline(for configuration: ChooseLockHabitsIntent, in context: Context) async -> Timeline<BuddyEntry> { Timeline(entries: [loadEntry(selectedIDs: configuration.habits?.map(\.id))], policy: .after(nextRefresh())) }
}

/// One habit: a ring that fills as today is done, around the streak.
struct HabitLockView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BuddyEntry
    var body: some View {
        Group {
            if let habit = entry.habit {
                let today = Day(entry.date), p = Engine.progress(habit, day: today, data: entry.data, today: today)
                let streak = Engine.streak(habit, data: entry.data, today: today), unit = streak.value == 1 ? String(streak.unit.rawValue.dropLast()) : streak.unit.rawValue
                switch family {
                case .accessoryCircular:
                    ZStack {
                        AccessoryWidgetBackground()
                        Circle().stroke(.primary.opacity(0.22), lineWidth: 4.5).padding(2.5)
                        Circle().trim(from: 0, to: p.success ? 1 : p.fraction).stroke(.primary, style: StrokeStyle(lineWidth: 4.5, lineCap: .round)).rotationEffect(.degrees(-90)).padding(2.5).widgetAccentable()
                        VStack(spacing: -1) {
                            Image(systemName: p.success ? "checkmark" : "flame.fill").font(.system(size: 10, weight: .bold))
                            Text("\(streak.value)").font(.system(size: 19, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                        }.padding(.horizontal, 8)
                    }
                    .accessibilityElement(children: .ignore).accessibilityLabel("\(habit.name), streak \(streak.value) \(unit), \(p.success ? "done today" : "not done today")")
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) { Image(systemName: p.success ? "checkmark.circle.fill" : "circle"); Text(habit.name).lineLimit(1) }.font(.headline).widgetAccentable()
                        Text("\(Image(systemName: "flame.fill")) \(streak.value) \(unit) streak").font(.caption)
                        WeekDots(habit: habit, data: entry.data, today: today)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                default:
                    Label("\(streak.value) \(unit) · \(habit.name)", systemImage: p.success ? "checkmark.circle.fill" : "flame.fill")
                }
            } else {
                switch family {
                case .accessoryCircular: ZStack { AccessoryWidgetBackground(); Image(systemName: "flame") }
                case .accessoryRectangular: Text(entry.error ?? (entry.hidden ? BuddyEntry.hiddenMessage : "Choose a habit in Edit Widget.")).font(.caption)
                default: Text("Choose a habit")
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: entry.habit.map { "habitbuddy://\($0.id.uuidString)" } ?? "habitbuddy://home"))
    }
}
/// This week as seven small squares: filled when done, hollow ahead.
struct WeekDots: View {
    let habit: Habit
    @ViewData var data: BuddyData
    let today: Day
    var body: some View {
        let start = today.startOfWeek(data.settings.weekStart)
        HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { i in
                let mark = DayMark(habit, start.adding(i), data, today: today), shape = RoundedRectangle(cornerRadius: 2.5)
                Group {
                    if mark == .done { shape.fill(.primary) }
                    else if mark == .future { shape.strokeBorder(.primary.opacity(0.35), lineWidth: 1) }
                    else { shape.fill(.primary.opacity(0.25)) }
                }.frame(width: 11, height: 11)
            }
        }
    }
}

/// Today's count across habits.
struct TodayLockView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BuddyEntry
    var body: some View {
        let today = Day(entry.date), habits = entry.selectedHabits.filter { $0.available(on: today, today: today) }
        let open = habits.filter { !Engine.progress($0, day: today, data: entry.data, today: today).success }, done = habits.count - open.count
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(done), in: 0...Double(max(1, habits.count))) { Image(systemName: "checkmark") } currentValueLabel: { Text("\(done)/\(habits.count)").font(.system(.body, design: .rounded).weight(.bold)) }
                    .gaugeStyle(.accessoryCircularCapacity).widgetAccentable()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 3) {
                    Text(habits.isEmpty ? "No habits today" : done == habits.count ? "All done today" : "\(done) of \(habits.count) done").font(.headline).widgetAccentable()
                    Gauge(value: Double(done), in: 0...Double(max(1, habits.count))) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
                    if let next = open.first { Text("Next: \(next.name)").font(.caption).lineLimit(1) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            default:
                Label("\(done)/\(habits.count) habits done", systemImage: done == habits.count && !habits.isEmpty ? "checkmark.circle.fill" : "circle.dashed")
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "habitbuddy://today"))
    }
}
struct HabitLockWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HabitLock", intent: ChooseLockHabitIntent.self, provider: LockHabitProvider()) { HabitLockView(entry: $0) }
            .configurationDisplayName("Habit Streak").description("A habit's streak, with a ring that fills when today is done.").supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
struct TodayLockWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TodayLock", intent: ChooseLockHabitsIntent.self, provider: LockHabitsProvider()) { TodayLockView(entry: $0) }
            .configurationDisplayName("Today's Habits").description("How many of today's habits are done.").supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: Controls (Control Center, Lock Screen and the Action button)

struct HabitControlValue { var habit: HabitEntity?; var done = false }
struct HabitControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: ChooseControlHabitIntent) -> HabitControlValue { HabitControlValue(habit: configuration.habit) }
    func currentValue(configuration: ChooseControlHabitIntent) async throws -> HabitControlValue {
        guard let id = configuration.habit?.id, let data = try? AppEnvironment.repository.load(), let habit = data.active.first(where: { $0.id == id }) else { return previewValue(configuration: configuration) }
        return HabitControlValue(habit: HabitEntity(habit), done: Engine.progress(habit, day: Day(), data: data).success)
    }
}
struct LogHabitControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "LogHabitControl", provider: HabitControlProvider()) { value in
            ControlWidgetButton(action: ControlLogIntent(value.habit)) { Label(value.habit?.name ?? "Choose Habit", systemImage: value.done ? "checkmark.circle.fill" : "circle") }
        }
        .displayName("Log Habit").description("Check off a yes/no habit, or add one to a count.").promptsForUserConfiguration()
    }
}
struct RoutineControlValue { var routine: RoutineEntity?; var done = 0; var total = 0 }
struct RoutineControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: ChooseControlRoutineIntent) -> RoutineControlValue { RoutineControlValue(routine: configuration.routine) }
    func currentValue(configuration: ChooseControlRoutineIntent) async throws -> RoutineControlValue {
        guard let id = configuration.routine?.id, let data = try? AppEnvironment.repository.load(), let routine = data.routines.first(where: { $0.id == id }) else { return previewValue(configuration: configuration) }
        let progress = Engine.routineProgress(routine, data: data)
        return RoutineControlValue(routine: RoutineEntity(routine), done: progress.done, total: progress.total)
    }
}
struct CompleteRoutineControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "CompleteRoutineControl", provider: RoutineControlProvider()) { value in
            ControlWidgetButton(action: CompleteRoutineIntent(value.routine)) {
                Label(value.routine?.name ?? "Choose Routine", systemImage: value.total > 0 && value.done == value.total ? "checklist.checked" : "checklist")
            }
        }
        .displayName("Complete Routine").description("Check off every open habit in a routine.").promptsForUserConfiguration()
    }
}
struct TimerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "HabitTimerControl") { ControlWidgetButton(action: OpenTimerIntent()) { Label("Habit Timer", systemImage: "timer") } }
            .displayName("Habit Timer").description("Open the habit timer.")
    }
}

// MARK: Live Activity

struct HabitTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HabitTimerAttributes.self) { context in
            TimerActivityView(context: context)
                .activityBackgroundTint(Color(hex: 0x101013))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "habitbuddy://timer"))
        } dynamicIsland: { context in
            let color = BuddyStyle.color(context.attributes.color)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { TimerGlyph(attributes: context.attributes, size: 46).padding(.leading, 4) }
                DynamicIslandExpandedRegion(.trailing) { TimerClock(state: context.state).font(.system(size: 30, weight: .semibold, design: .monospaced)).foregroundStyle(color).frame(maxWidth: 130, alignment: .trailing).padding(.trailing, 4) }
                DynamicIslandExpandedRegion(.center) { Text(context.attributes.name).font(BuddyFont.text(16, .semibold)).foregroundStyle(.white).lineLimit(1) }
                DynamicIslandExpandedRegion(.bottom) { TimerButtons(color: color).padding(.top, 6) }
            } compactLeading: {
                BuddyGlyph(symbol: context.attributes.symbol, size: 16).foregroundStyle(color)
            } compactTrailing: {
                TimerClock(state: context.state).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(color).frame(maxWidth: 56)
            } minimal: {
                BuddyGlyph(symbol: context.attributes.symbol, size: 14).foregroundStyle(color)
            }
            .keylineTint(color)
            .widgetURL(URL(string: "habitbuddy://timer"))
        }
    }
}
struct TimerActivityView: View {
    let context: ActivityViewContext<HabitTimerAttributes>
    var body: some View {
        let color = BuddyStyle.color(context.attributes.color), up = context.state.end.map { Date() >= $0 } ?? false
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                TimerGlyph(attributes: context.attributes, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.name).font(BuddyFont.text(17, .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(context.isStale || up ? "Time's up" : context.attributes.summary).font(BuddyFont.text(12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 8)
                TimerClock(state: context.state).font(.system(size: 32, weight: .semibold, design: .monospaced)).foregroundStyle(color).frame(maxWidth: 130, alignment: .trailing)
            }
            TimerButtons(color: color)
        }.padding(16)
    }
}
struct TimerGlyph: View {
    let attributes: HabitTimerAttributes
    var size: CGFloat
    var body: some View {
        let color = BuddyStyle.color(attributes.color)
        BuddyGlyph(symbol: attributes.symbol, size: size * 0.52).foregroundStyle(color).frame(width: size, height: size).background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: size * 0.29, style: .circular))
    }
}
/// The system draws these clocks, so they keep time while the app is closed.
struct TimerClock: View {
    let state: HabitTimerAttributes.ContentState
    var body: some View {
        Group {
            if let end = state.end { Text(timerInterval: state.start...max(end, state.start), countsDown: true) }
            else { Text(state.start, style: .timer) }
        }.monospacedDigit().multilineTextAlignment(.trailing).lineLimit(1).minimumScaleFactor(0.6)
    }
}
struct TimerButtons: View {
    let color: Color
    var body: some View {
        HStack(spacing: 10) {
            Button(intent: CancelTimerIntent()) { Label("Cancel", systemImage: "xmark").frame(maxWidth: .infinity, minHeight: 36) }.tint(Color(hex: 0x3B3B40))
            Button(intent: FinishTimerIntent()) { Label("Finish & Log", systemImage: "checkmark").frame(maxWidth: .infinity, minHeight: 36) }.tint(color)
        }
        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).font(BuddyFont.text(15, .semibold)).foregroundStyle(.white)
    }
}

struct MoreWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayHomeWidget()
        HabitLockWidget()
        TodayLockWidget()
        LogHabitControl()
        CompleteRoutineControl()
        TimerControl()
        HabitTimerLiveActivity()
    }
}
