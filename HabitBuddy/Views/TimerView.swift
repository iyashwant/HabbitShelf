import SwiftUI

/// Time a session for a habit: a countdown or a stopwatch that logs the elapsed time when finished.
struct TimerView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var timer: TimerController
    @Environment(\.colorScheme) private var scheme
    @State var habitID: UUID?
    @State private var countdown = true
    @State private var minutes = 10
    private var eligible: [Habit] { store.visible.active.filter { TimerUnit($0.currentGoal) != nil } }
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Timer")
            if let session = timer.session, let habit = store.habit(session.habitID) { running(session, habit) }
            else if eligible.isEmpty {
                ContentUnavailableView("No habits take a timer", systemImage: "timer", description: Text("Timers log time to habits measured in minutes, hours or seconds, and complete yes/no habits. Set a habit's unit to minutes to time it."))
                Spacer()
            } else { setup }
        }
        .background(BuddyStyle.canvas(scheme))
        // Habits measured in time come first; yes/no habits only take a timer when chosen.
        .onAppear { if habitID == nil || !eligible.contains(where: { $0.id == habitID }) { habitID = (eligible.first { TimerUnit($0.currentGoal) != .completion } ?? eligible.first)?.id }; preset() }
        .onChange(of: habitID) { _, _ in preset() }
    }
    private var habit: Habit? { eligible.first { $0.id == habitID } }
    /// A habit measured in time starts its countdown at the daily target.
    private func preset() {
        guard let habit, let unit = TimerUnit(habit.currentGoal), let seconds = unit.duration(target: habit.currentGoal.target) else { return }
        minutes = min(240, max(1, Int((seconds / 60).rounded())))
    }
    private var setup: some View {
        let color = habit.map { BuddyStyle.color($0.color) } ?? BuddyStyle.purple
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                clockFace(progress: 1, text: countdown ? Self.format(Double(minutes) * 60) : "00:00", caption: countdown ? "COUNTDOWN" : "STOPWATCH", color: color)
                    .frame(maxWidth: .infinity).padding(.top, 6)
                caption("Habit") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(eligible) { h in
                                Button { habitID = h.id } label: {
                                    HStack(spacing: 8) { HabitIcon(habit: h, size: 28); Text(h.name).font(BuddyFont.text(14, .medium)).lineLimit(1) }
                                        .foregroundStyle(BuddyStyle.text(scheme)).padding(.leading, 6).padding(.trailing, 12).frame(height: 42)
                                        .background(BuddyStyle.field(scheme), in: Capsule())
                                        .overlay { Capsule().strokeBorder(habitID == h.id ? BuddyStyle.color(h.color) : BuddyStyle.border(scheme, 0.1), lineWidth: habitID == h.id ? 1.5 : 1) }
                                }.buttonStyle(.plain).accessibilityAddTraits(habitID == h.id ? .isSelected : [])
                            }
                        }
                    }
                }
                caption("Mode") { SegmentedChoice(selection: $countdown, options: [(true, "Countdown"), (false, "Stopwatch")]) }
                if countdown {
                    caption("Length") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                            ForEach([5, 10, 15, 20, 25, 30, 45, 60, 90, 120], id: \.self) { value in
                                Button { minutes = value } label: {
                                    Text("\(value)").font(BuddyFont.mono(14, minutes == value ? .semibold : .regular)).foregroundStyle(BuddyStyle.text(scheme)).frame(maxWidth: .infinity, minHeight: 40)
                                        .background(minutes == value ? BuddyStyle.control(scheme) : BuddyStyle.field(scheme), in: RoundedRectangle(cornerRadius: 12, style: .circular))
                                        .overlay { RoundedRectangle(cornerRadius: 12, style: .circular).strokeBorder(minutes == value ? color : BuddyStyle.border(scheme, 0.1), lineWidth: minutes == value ? 1.5 : 1) }
                                }.buttonStyle(.plain).accessibilityLabel("\(value) minutes")
                            }
                        }
                        Stepper("\(minutes) minutes", value: $minutes, in: 1...240).font(BuddyFont.text(15)).padding(.horizontal, 16).frame(height: 52).background(BuddyStyle.field(scheme), in: RoundedRectangle(cornerRadius: 15, style: .circular))
                    }
                }
                if let habit { Text("\(TimerController.summary(habit)). It logs to the day the timer starts.").font(BuddyFont.text(12.5)).foregroundStyle(BuddyStyle.tertiaryText(scheme)) }
                if !timer.liveActivitiesEnabled { Text("Live Activities are off for Habit Buddy, so the timer shows only in the app. Turn them on in Settings to see it on the Lock Screen.").font(BuddyFont.text(12.5)).foregroundStyle(BuddyStyle.tertiaryText(scheme)) }
            }.padding(.horizontal, 16).padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            PrimaryAction(title: "Start Timer", symbol: "play") { if let habit { timer.start(habit, duration: countdown ? Double(minutes) * 60 : nil) } }
                .disabled(habit == nil).padding(.horizontal, 24).padding(.bottom, 6)
                .background(alignment: .bottom) { LinearGradient(colors: [BuddyStyle.canvas(scheme).opacity(0), BuddyStyle.canvas(scheme).opacity(0.9)], startPoint: .top, endPoint: .bottom).frame(height: 120).ignoresSafeArea().allowsHitTesting(false) }
        }
    }
    private func running(_ session: TimerSession, _ habit: Habit) -> some View {
        let color = BuddyStyle.color(habit.color)
        return VStack(spacing: 18) {
            HStack(spacing: 10) { HabitIcon(habit: habit, size: 36); Text(habit.name).font(BuddyFont.text(18, .semibold)).foregroundStyle(BuddyStyle.text(scheme)) }.padding(.top, 8)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = session.elapsed(context.date), done = session.finished(context.date)
                let progress = session.duration.map { elapsed / max(1, $0) } ?? elapsed.truncatingRemainder(dividingBy: 60) / 60
                clockFace(progress: progress, text: Self.format(session.duration.map { $0 - elapsed } ?? elapsed), caption: done ? "TIME'S UP" : session.duration == nil ? "ELAPSED" : "REMAINING", color: color)
            }
            Text("Started \(session.start.formatted(date: .omitted, time: .shortened)) · \(TimerController.summary(habit))").font(BuddyFont.text(13)).foregroundStyle(BuddyStyle.secondaryText(scheme)).multilineTextAlignment(.center).padding(.horizontal, 24)
            if let message = timer.message { Text(message).font(BuddyFont.text(12.5)).foregroundStyle(.orange).multilineTextAlignment(.center).padding(.horizontal, 24) }
            Spacer()
            PrimaryAction(title: "Finish & Log", symbol: "check") { timer.finish(store) }.padding(.horizontal, 24).accessibilityIdentifier("finish-timer")
            Button("Cancel Timer", role: .destructive) { timer.cancel() }.font(BuddyFont.text(15, .medium)).frame(minHeight: 44).padding(.bottom, 6)
        }
    }
    private func clockFace(progress: Double, text: String, caption: String, color: Color) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: 12)
            Circle().trim(from: 0, to: min(1, max(0, progress))).stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                Text(text).font(.system(size: 46, weight: .semibold, design: .monospaced)).monospacedDigit().foregroundStyle(BuddyStyle.text(scheme)).contentTransition(.numericText())
                Text(caption).font(BuddyFont.text(11, .semibold)).tracking(1.4).foregroundStyle(BuddyStyle.secondaryText(scheme))
            }
        }
        .frame(width: 236, height: 236)
        .accessibilityElement(children: .ignore).accessibilityLabel("\(caption.lowercased()), \(text)")
    }
    private func caption<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).fieldCaption().foregroundStyle(BuddyStyle.secondaryText(scheme)).padding(.leading, 5); content() }
    }
    static func format(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.up))), h = total / 3_600, m = total % 3_600 / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
