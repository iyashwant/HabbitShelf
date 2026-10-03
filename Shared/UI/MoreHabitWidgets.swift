import SwiftUI
import AppIntents

/// The goal ring, stats, year, next badge, quick check, week and routine designs, plus the large month.
/// Drawn by the in-app dashboard and the matching home-screen widgets.
extension HabitWidgetContent {
    func caption(_ text: String) -> some View {
        Text(text.uppercased()).font(BuddyFont.text(9.5, .semibold)).tracking(0.6).foregroundStyle(palette.secondary).lineLimit(1).minimumScaleFactor(0.8)
    }
    /// Today's amount toward a numeric goal, or this week's (or month's) days toward a yes/no goal.
    func ringTile(_ habit: Habit) -> some View {
        let goal = GoalProgress(habit, data: data, today: today)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Text(habit.name).font(BuddyFont.text(15, .semibold)).foregroundStyle(palette.primary).lineLimit(2).minimumScaleFactor(0.85)
                Spacer(minLength: 2)
                check(habit, 30)
            }
            ZStack {
                Circle().stroke(palette.missed, lineWidth: 9)
                Circle().trim(from: 0, to: goal.fraction).stroke(palette.tint, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(goal.value).font(BuddyFont.text(22, .heavy)).monospacedDigit().foregroundStyle(palette.primary).lineLimit(1).minimumScaleFactor(0.5)
                    caption(goal.caption)
                }.padding(.horizontal, 15)
                .accessibilityElement(children: .ignore).accessibilityLabel("\(habit.name), \(goal.value) \(goal.caption.lowercased())")
            }
            .padding(4.5).aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(14)
    }

    /// The kept rate over 30 days with the streak, best run and total; the medium size adds the 30 days as bars.
    @ViewBuilder func statsTile(_ habit: Habit) -> some View {
        let rate = DayRate(habit, days: 30, data: data, today: today), m = summaries.milestones(habit, data: data, today: today), streak = summaries.streak(habit, data: data, today: today)
        let percent = rate.eligible == 0 ? "–" : "\(Int((rate.rate * 100).rounded()))%", quit = habit.goal(on: today).mode == .quit
        let metrics = HStack(alignment: .top, spacing: 0) {
            metric("flame.fill", streak.value, streak.unit == .days ? "Streak" : streak.unit.rawValue)
            metric("trophy.fill", m.bestStreak, streak.unit == .days ? "Best" : "Best days")
            metric("checkmark", m.total, quit ? "Clean" : "Total")
        }
        if resolvedSize == .medium {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    check(habit, 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(habit.name).font(BuddyFont.text(17, .semibold)).foregroundStyle(palette.primary).lineLimit(1)
                        caption("Last 30 days")
                    }
                    Spacer(minLength: 4)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(percent).font(BuddyFont.text(32, .heavy)).monospacedDigit().foregroundStyle(palette.primary).lineLimit(1).minimumScaleFactor(0.7)
                        caption("Kept")
                    }.accessibilityElement(children: .ignore).accessibilityLabel("\(percent) kept in the last 30 days")
                    metrics.frame(maxWidth: .infinity)
                }
                RecentDays(habit: habit, data: data, today: today, palette: palette).frame(maxHeight: 22)
            }.padding(14)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 6) {
                    Text(habit.name).font(BuddyFont.text(15, .semibold)).foregroundStyle(palette.primary).lineLimit(2).minimumScaleFactor(0.85)
                    Spacer(minLength: 2)
                    check(habit, 30)
                }
                Spacer(minLength: 2)
                Text(percent).font(BuddyFont.text(34, .heavy)).monospacedDigit().foregroundStyle(palette.primary).lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityLabel("\(percent) kept in the last 30 days")
                caption("Kept · 30 days").accessibilityHidden(true)
                Spacer(minLength: 8)
                metrics
            }.padding(14)
        }
    }
    private func metric(_ symbol: String, _ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(palette.tint)
                Text("\(value)").font(BuddyFont.text(16, .bold)).monospacedDigit().foregroundStyle(palette.primary).lineLimit(1).minimumScaleFactor(0.6)
            }
            caption(label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore).accessibilityLabel("\(label) \(value)")
    }

    /// This calendar year: a contribution grid of weeks (medium) or twelve month grids (large).
    func yearTile(_ habit: Habit) -> some View {
        let year = Int(today.rawValue.prefix(4)) ?? 2026, stats = Engine.yearStats(habit, year: year, data: data, today: today)
        let summary = "\(stats.completions) \(stats.completions == 1 ? "day" : "days") · \(Int((stats.rate * 100).rounded()))%"
        let streak = summaries.streak(habit, data: data, today: today), month = DayRate(habit, days: today.startOfMonth.distance(to: today) + 1, data: data, today: today)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                check(habit, 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(habit.name).font(BuddyFont.text(17, .semibold)).foregroundStyle(palette.primary).lineLimit(1)
                    caption(summary)
                }
                Spacer(minLength: 4)
                Text(String(year)).font(BuddyFont.text(18, .heavy)).monospacedDigit().foregroundStyle(palette.secondary)
            }
            if resolvedSize == .large {
                let first = Day(rawValue: String(format: "%04d-01-01", year))!
                VStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(0..<4, id: \.self) { column in
                                let month = first.addingMonths(row * 4 + column)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Day.shortMonth.string(from: month.date)).font(BuddyFont.text(10.5, .semibold)).foregroundStyle(month.month == today.month ? palette.primary : palette.secondary)
                                    MonthDots(habit: habit, data: data, month: month, today: today, palette: palette, gap: 2)
                                }.frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        }
                    }
                }.frame(maxHeight: .infinity, alignment: .top)
            } else {
                YearWeeks(habit: habit, data: data, year: year, today: today, palette: palette).frame(maxHeight: .infinity)
            }
            HStack(alignment: .top, spacing: 0) {
                metric("flame.fill", streak.value, streak.unit == .days ? "Streak" : streak.unit.rawValue)
                metric("trophy.fill", stats.longestRun, "Longest run")
                metric("calendar", month.done, "This month")
            }
        }.padding(14)
    }

    /// Progress toward the next streak badge, or the next check-in badge once streak badges run out.
    func badgeTile(_ habit: Habit) -> some View {
        let m = summaries.milestones(habit, data: data, today: today), goal = habit.goal(on: today)
        // Build habits without a streak goal never grow a streak, so they work toward check-in badges.
        let streaks = !(goal.mode == .build && goal.cadence == .none)
        let next: (step: Int, value: Int, caption: String)? = streaks && m.nextStreak != nil ? (m.nextStreak!, m.currentStreak, "Days in a row")
            : m.nextTotal.map { ($0, m.total, goal.mode == .quit ? "Clean days" : "Check-ins") }
        let left = next.map { $0.step - $0.value } ?? 0
        let detail = next == nil ? "Every badge earned" : next!.caption == "Days in a row" ? "\(left) more \(left == 1 ? "day" : "days")" : "\(left) to go"
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Text(habit.name).font(BuddyFont.text(15, .semibold)).foregroundStyle(palette.primary).lineLimit(1)
                Spacer(minLength: 2)
                HStack(spacing: 3) { Image(systemName: "trophy.fill").font(.system(size: 11)); Text("\(m.earned)").font(BuddyFont.text(14, .bold)).monospacedDigit() }
                    .foregroundStyle(palette.tint).accessibilityElement(children: .ignore).accessibilityLabel("\(m.earned) badges earned")
            }
            ZStack {
                Circle().stroke(palette.missed, lineWidth: 7)
                Circle().trim(from: 0, to: next.map { min(1, Double($0.value) / Double(max(1, $0.step))) } ?? 1).stroke(palette.tint, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Image(systemName: "rosette").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.tint)
                    Text(next.map { "\($0.step)" } ?? "\(m.earned)").font(BuddyFont.text(24, .heavy)).monospacedDigit().foregroundStyle(palette.primary).lineLimit(1).minimumScaleFactor(0.6)
                    caption(next?.caption ?? "Badges")
                }.padding(.horizontal, 14)
            }
            .padding(3.5).aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore).accessibilityLabel(next.map { "Next badge \($0.step) \($0.caption.lowercased()), \(detail)" } ?? detail)
            Text(detail).font(BuddyFont.text(11.5, .medium)).foregroundStyle(palette.secondary).lineLimit(1).frame(maxWidth: .infinity).accessibilityHidden(true)
        }.padding(14)
    }

    /// Several habits as tappable icons: 4 in the small size, 8 in medium and 16 in large.
    var checksTile: some View {
        let size = resolvedSize, columns = size == .small ? 2 : 4, capacity = columns * (size == .large ? 4 : 2), names = size != .small
        let shown = Array(habits.prefix(habits.count > capacity ? capacity - 1 : capacity)), overflow = habits.count - shown.count
        let slots = shown.count + (overflow > 0 ? 1 : 0), rows = max(1, (slots + columns - 1) / columns)
        let iconSize: CGFloat = size == .small ? (rows == 1 ? 62 : 54) : size == .large ? 46 : 42
        let done = habits.filter { Engine.progress($0, day: today, data: data, today: today).success }.count
        return VStack(alignment: .leading, spacing: 10) {
            if size == .large {
                HStack(alignment: .firstTextBaseline) {
                    Text(heading("Today")).font(BuddyFont.text(22, .heavy)).foregroundStyle(palette.primary).lineLimit(1)
                    Spacer(minLength: 4)
                    caption("\(done)/\(habits.count) done")
                }
            }
            if habits.isEmpty { placeholder("Create habits in Habit Buddy.") }
            else {
                Grid(horizontalSpacing: 4, verticalSpacing: size == .large ? 12 : names ? 8 : 10) {
                    ForEach(0..<rows, id: \.self) { row in
                        GridRow {
                            ForEach(0..<columns, id: \.self) { column in
                                let index = row * columns + column
                                Group {
                                    if index < shown.count {
                                        let habit = shown[index]
                                        VStack(spacing: 4) {
                                            HabitCheck(habit: habit, data: data, today: today, size: iconSize, palette: rowPalette(habit), onTap: onCheck.map { action in { action(habit) } }, icon: true)
                                            if names { Text(habit.name).font(BuddyFont.text(11, .medium)).foregroundStyle(palette.primary).lineLimit(1).accessibilityHidden(true) }
                                        }
                                    } else if index == shown.count && overflow > 0 {
                                        VStack(spacing: 4) {
                                            Text("+\(overflow)").font(BuddyFont.text(iconSize * 0.34, .bold)).monospacedDigit().foregroundStyle(palette.secondary)
                                                .frame(width: iconSize, height: iconSize).overlay { Circle().strokeBorder(palette.outline, lineWidth: 1.5) }
                                            if names { Text("More").font(BuddyFont.text(11, .medium)).foregroundStyle(palette.secondary) }
                                        }.accessibilityElement(children: .ignore).accessibilityLabel("\(overflow) more habits")
                                    } else { Color.clear.frame(width: 1, height: 1) }
                                }.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.padding(14)
    }

    /// The kept share of each day this week as bars, with the week's total against last week.
    var weekTile: some View {
        let rates = WeekRates(habits: habits, data: data, week: today, today: today)
        let percent = Int((rates.total.rate * 100).rounded())
        let delta = rates.previous.eligible == 0 || rates.total.eligible == 0 ? nil : percent - Int((rates.previous.rate * 100).rounded())
        let end = rates.start.adding(6)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(heading("This Week")).font(BuddyFont.text(17, .bold)).foregroundStyle(palette.primary).lineLimit(1)
                    caption("\(Day.shortMonth.string(from: rates.start.date)) \(rates.start.dayNumber) – \(Day.shortMonth.string(from: end.date)) \(end.dayNumber)")
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(rates.total.eligible == 0 ? "–" : "\(percent)%").font(BuddyFont.text(22, .heavy)).monospacedDigit().foregroundStyle(palette.primary)
                    caption(delta.map { $0 == 0 ? "Same as last week" : "\($0 > 0 ? "+" : "−")\(abs($0)) vs last week" } ?? "Kept")
                }
            }
            HStack(alignment: .bottom, spacing: 9) {
                ForEach(0..<7, id: \.self) { i in
                    let day = rates.start.adding(i), rate = rates.days[i]
                    VStack(spacing: 5) {
                        GeometryReader { proxy in
                            let shape = RoundedRectangle(cornerRadius: min(7, proxy.size.width * 0.3), style: .continuous)
                            ZStack(alignment: .bottom) {
                                if day > today { shape.strokeBorder(palette.outline, lineWidth: 1) } else { shape.fill(palette.missed) }
                                if rate.done > 0 { shape.fill(palette.tint).frame(height: max(proxy.size.width * 0.6, proxy.size.height * rate.rate)) }
                            }
                        }
                        Text(Calendar.current.veryShortWeekdaySymbols[day.weekday - 1]).font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundStyle(day == today ? palette.primary : palette.secondary)
                    }
                }
            }.frame(maxHeight: .infinity)
        }.padding(14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(heading("This Week")), \(rates.total.eligible == 0 ? "nothing tracked yet" : "\(percent) percent kept")")
    }

    /// A routine's progress with Complete All; the medium size lists its habits with their checks.
    @ViewBuilder func routineTile(_ routine: Routine) -> some View {
        let members = routine.habitIDs.compactMap { data.activeHabit($0) }
        let progress = Engine.routineProgress(routine, data: data, day: today, today: today), complete = progress.total > 0 && progress.done == progress.total
        let summary = VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                BuddyGlyph(symbol: routine.symbol, size: 16).foregroundStyle(palette.tint).frame(width: 30, height: 30)
                    .background(palette.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .circular))
                Text(routine.name).font(BuddyFont.text(15, .semibold)).foregroundStyle(palette.primary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(progress.done)/\(progress.total)").font(BuddyFont.text(28, .heavy)).monospacedDigit().foregroundStyle(palette.primary)
            caption(progress.total == 0 ? "No active habits" : complete ? "All done today" : "Done today")
            HStack(spacing: 3) {
                ForEach(members) { h in Capsule().fill(Engine.progress(h, day: today, data: data, today: today).success ? BuddyStyle.color(h.color) : palette.missed) }
            }.frame(height: 5).padding(.top, 7)
            Spacer(minLength: 8)
            completeButton(routine, done: complete, empty: progress.total == 0)
        }
        .accessibilityElement(children: .contain)
        if resolvedSize == .medium {
            HStack(spacing: 14) {
                summary.frame(maxWidth: .infinity)
                palette.outline.frame(width: 1)
                VStack(alignment: .leading, spacing: 7) {
                    let shown = members.prefix(members.count > 4 ? 3 : 4)
                    ForEach(shown) { habit in
                        HStack(spacing: 8) {
                            HabitCheck(habit: habit, data: data, today: today, size: 26, palette: rowPalette(habit), onTap: onCheck.map { action in { action(habit) } })
                            Text(habit.name).font(BuddyFont.text(13.5, .medium)).foregroundStyle(palette.primary).lineLimit(1)
                        }
                    }
                    if members.count > shown.count { Text("+\(members.count - shown.count) more").font(BuddyFont.text(12)).foregroundStyle(palette.secondary).padding(.leading, 2) }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(14)
        } else { summary.padding(14) }
    }
    @ViewBuilder private func completeButton(_ routine: Routine, done: Bool, empty: Bool) -> some View {
        let label = HStack(spacing: 5) {
            Image(systemName: done ? "checkmark" : "checklist.checked").font(.system(size: 12, weight: .bold))
            Text(done ? "All Done" : "Complete All").font(BuddyFont.text(13, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(done || empty ? palette.tint : Color.white).frame(maxWidth: .infinity, minHeight: 30)
        .background(done || empty ? palette.tint.opacity(0.16) : palette.tint, in: Capsule())
        Group {
            if done || empty { label }
            else if let onRoutine { Button { onRoutine(routine) } label: { label }.buttonStyle(.plain) }
            else { Button(intent: CompleteRoutineIntent(RoutineEntity(routine))) { label }.buttonStyle(.plain) }
        }
        .accessibilityLabel(done ? "\(routine.name) is done" : "Complete All in \(routine.name)")
    }

    /// This month as a calendar with day numbers, for the large size.
    func monthLarge(_ habit: Habit) -> some View {
        let first = today.startOfMonth, rate = DayRate(habit, days: first.distance(to: today) + 1, data: data, today: today)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                check(habit, 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(habit.name).font(BuddyFont.text(17, .semibold)).foregroundStyle(palette.primary).lineLimit(1)
                    caption(Day.monthYear.string(from: first.date))
                }
                Spacer(minLength: 4)
                StreakBadge(summary: summaries.streak(habit, data: data, today: today), palette: palette, size: 20, trailing: true)
            }
            MonthCalendar(habit: habit, data: data, month: first, today: today, palette: palette).frame(maxHeight: .infinity)
            caption(rate.eligible == 0 ? "Nothing tracked yet" : "\(rate.done) of \(rate.eligible) days kept · \(Int((rate.rate * 100).rounded()))%")
        }.padding(14)
    }
}

/// What the goal ring shows. Numeric goals fill with today's amount; yes/no goals fill with this period's
/// kept days (the week's goal for weekly habits, the month's for monthly ones, seven days otherwise).
struct GoalProgress {
    var fraction: Double
    var value: String
    var caption: String
    init(_ habit: Habit, data: BuddyData, today: Day) {
        let g = habit.goal(on: today), p = Engine.progress(habit, day: today, data: data, today: today)
        if g.mode == .quit && g.tracking == .yesNo {
            fraction = p.available && !p.slip ? 1 : 0; value = p.slip ? "Slip" : "Clean"; caption = "Today"
        } else if g.tracking != .yesNo {
            fraction = g.mode == .quit ? min(1, Double(p.amount) / Double(max(1, g.target))) : p.fraction
            value = "\(Amount.text(p.amount))/\(Amount.text(g.target))"
            caption = g.mode == .quit ? "Limit" + (g.unit.isEmpty ? "" : " · \(g.unit)") : g.unit.isEmpty ? "Today" : g.unit
        } else {
            let monthly = g.cadence == .monthly, start = monthly ? today.startOfMonth : today.startOfWeek(data.settings.weekStart)
            let target = g.cadence == .weekly || monthly ? g.days : 7
            let done = Day.range(start, today).filter { Engine.progress(habit, day: $0, data: data, today: today).success }.count
            fraction = min(1, Double(done) / Double(max(1, target))); value = "\(done)/\(target)"; caption = monthly ? "This month" : "This week"
        }
    }
}

/// A calendar year as columns of weeks, with month names beneath.
struct YearWeeks: View {
    let habit: Habit
    let data: BuddyData
    let year: Int
    var today = Day()
    let palette: WidgetPalette
    var body: some View {
        let first = Day(rawValue: String(format: "%04d-01-01", year))!, last = Day(rawValue: String(format: "%04d-12-31", year))!
        let start = first.startOfWeek(data.settings.weekStart), columns = start.distance(to: last) / 7 + 1
        GeometryReader { proxy in
            let label: CGFloat = 13, pitch = min(proxy.size.width / CGFloat(columns), (proxy.size.height - label) / 7), cell = pitch * 0.8
            Canvas { context, _ in
                for column in 0..<columns {
                    for row in 0..<7 {
                        let day = start.adding(column * 7 + row)
                        guard day >= first && day <= last else { continue }
                        let mark = DayMark(habit, day, data, today: today)
                        let rect = CGRect(x: CGFloat(column) * pitch, y: CGFloat(row) * pitch, width: cell, height: cell)
                        context.fill(Path(roundedRect: rect, cornerRadius: cell * 0.3), with: .color(mark == .future || mark == .inactive ? palette.outline.opacity(0.6) : mark.fill(palette)))
                    }
                }
                for month in 0..<12 {
                    let day = first.addingMonths(month), x = CGFloat(start.distance(to: day) / 7) * pitch
                    context.draw(Text(Day.shortMonth.string(from: day.date)).font(BuddyFont.text(9, .medium)).foregroundStyle(palette.secondary), at: CGPoint(x: x, y: 7 * pitch + label / 2), anchor: .leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(habit.name), \(year)")
    }
}

/// The last days as a row of thin bars, oldest first.
struct RecentDays: View {
    let habit: Habit
    let data: BuddyData
    var days = 30
    var today = Day()
    let palette: WidgetPalette
    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 2.5, width = (size.width - gap * CGFloat(days - 1)) / CGFloat(days)
            for n in 0..<days {
                let mark = DayMark(habit, today.adding(n - days + 1), data, today: today)
                let rect = CGRect(x: CGFloat(n) * (width + gap), y: 0, width: width, height: size.height)
                context.fill(Path(roundedRect: rect, cornerRadius: min(width, size.height) * 0.4), with: .color(mark.fill(palette)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// One month as a calendar of numbered days, with weekday letters on top.
struct MonthCalendar: View {
    let habit: Habit
    let data: BuddyData
    let month: Day
    var today = Day()
    let palette: WidgetPalette
    var body: some View {
        let first = month.startOfMonth, offset = (first.weekday - data.settings.weekStart + 7) % 7
        let count = first.distance(to: first.endOfMonth) + 1, rows = (offset + count + 6) / 7
        let marks = (0..<count).map { DayMark(habit, first.adding($0), data, today: today) }
        GeometryReader { proxy in
            let gap: CGFloat = 5, header: CGFloat = 16, width = (proxy.size.width - 6 * gap) / 7
            let height = min(width, (proxy.size.height - header - CGFloat(rows - 1) * gap) / CGFloat(rows))
            Canvas { context, _ in
                for column in 0..<7 {
                    let symbol = Calendar.current.veryShortWeekdaySymbols[(data.settings.weekStart - 1 + column) % 7]
                    context.draw(Text(symbol).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(palette.secondary), at: CGPoint(x: CGFloat(column) * (width + gap) + width / 2, y: header / 2 - 2))
                }
                for n in 0..<count {
                    let slot = offset + n, day = first.adding(n), mark = marks[n]
                    let rect = CGRect(x: CGFloat(slot % 7) * (width + gap), y: header + CGFloat(slot / 7) * (height + gap), width: width, height: height)
                    let path = Path(roundedRect: rect, cornerRadius: min(width, height) * 0.3)
                    if mark == .future { context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: min(width, height) * 0.3), with: .color(palette.outline), lineWidth: 1) }
                    else { context.fill(path, with: .color(mark.fill(palette))) }
                    if day == today { context.stroke(Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: min(width, height) * 0.3 + 2), with: .color(palette.primary.opacity(0.85)), lineWidth: 1.5) }
                    let color = mark == .done ? Color.white : mark == .future || mark == .inactive ? palette.secondary : palette.primary
                    context.draw(Text("\(n + 1)").font(.system(size: min(13, height * 0.42), weight: .semibold, design: .rounded)).foregroundStyle(color), at: CGPoint(x: rect.midX, y: rect.midY))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Day.monthYear.string(from: first.date)), \(marks.filter { $0 == .done }.count) days done")
    }
}

extension Day {
    var dayNumber: Int { Int(rawValue.suffix(2)) ?? 1 }
}
