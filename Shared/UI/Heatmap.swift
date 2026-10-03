import SwiftUI

struct Heatmap: View {
    let habit: Habit
    let data: BuddyData
    var weeks = 24
    var end: Day = Day()
    var labels = true
    var monthLabels = true
    var weekdayLabels = true
    var body: some View {
        GeometryReader { proxy in
            let first = end.startOfWeek(data.settings.weekStart).adding(-(weeks - 1) * 7)
            let labelWidth: CGFloat = labels && weekdayLabels ? 22 : 0
            let top: CGFloat = labels && monthLabels ? 17 : 0
            let gap: CGFloat = 3
            let tile = max(2, (proxy.size.width - labelWidth - CGFloat(weeks - 1) * gap) / CGFloat(weeks))
            Canvas { context, _ in
                for col in 0..<weeks {
                    for row in 0..<7 {
                        let day = first.adding(col * 7 + row)
                        let progress = Engine.progress(habit, day: day, data: data)
                        let rect = CGRect(x: labelWidth + CGFloat(col) * (tile + gap), y: top + CGFloat(row) * (tile + gap), width: tile, height: tile)
                        let path = Path(roundedRect: rect, cornerRadius: tile * 0.25)
                        let color = BuddyStyle.color(habit.color)
                        let alpha = !progress.available ? 0.05 : progress.success ? 1 : progress.slip ? 0.13 : 0.12 + progress.fraction * 0.62
                        context.fill(path, with: .color(color.opacity(alpha)))
                        if day == Day() && data.settings.showToday { context.stroke(path, with: .color(color.opacity(0.85)), lineWidth: 1) }
                        if day.rawValue.hasSuffix("-01"), labels && monthLabels {
                            let f = DateFormatter(); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "MMM"
                            let text = Text(f.string(from: day.date)).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                            context.draw(text, at: CGPoint(x: rect.minX + 3, y: 6))
                        }
                    }
                }
                if labels && weekdayLabels {
                    let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                    for row in [1, 3, 5] {
                        let name = names[(data.settings.weekStart - 1 + row) % 7]
                        context.draw(Text(name).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary), at: CGPoint(x: 6, y: top + CGFloat(row) * (tile + gap) + tile / 2))
                    }
                }
            }
        }
        .frame(height: labels && monthLabels ? 106 : 88)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(habit.name), contribution grid, last \(weeks) weeks. Open the calendar to edit individual days.")
    }
}

struct DayTile: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    let habit: Habit
    let day: Day
    let data: BuddyData
    var size: CGFloat = 32
    var showNumber = false
    var body: some View {
        let p = Engine.progress(habit, day: day, data: data)
        let color = BuddyStyle.color(habit.color)
        RoundedRectangle(cornerRadius: size * 0.28)
            .fill(color.opacity(!p.available ? 0.04 : p.success ? 1 : 0.12 + p.fraction * 0.5))
            .overlay {
                if showNumber { Text(String(day.rawValue.suffix(2)).replacingOccurrences(of: "^0", with: "", options: .regularExpression)).font(.caption).foregroundStyle(p.success ? Color.black.opacity(0.8) : .secondary) }
                else if p.slip { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(color) }
                else if p.success && differentiate { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.black.opacity(0.6)) }
                else if habit.goal(on: day).tracking != .yesNo && !p.success && p.fraction > 0 {
                    Circle().trim(from: 0, to: p.fraction).stroke(color, lineWidth: 2).rotationEffect(.degrees(-90)).padding(4)
                }
            }
            .overlay { if day == Day() && data.settings.showToday { RoundedRectangle(cornerRadius: size * 0.28).stroke(color, lineWidth: 1.5) } }
            .overlay(alignment: .bottom) { if data.settings.notes && !data.record(habit.id, day).note.isEmpty { Circle().fill(Color.primary).frame(width: 3, height: 3).padding(.bottom, 3) } }
            .frame(width: size, height: size)
            .opacity(p.available ? 1 : 0.4)
            .accessibilityLabel("\(day.rawValue), \(p.success ? "complete" : p.slip ? "slip" : "incomplete"), \(Amount.text(p.amount)) \(habit.goal(on: day).unit)")
    }
}

struct ContributionHistory: View {
    let habit: Habit
    let data: BuddyData
    var start: Day?
    var end = Day()
    var monthLabels = true
    var weekdayLabels = true
    private var weeks: Int { max(24, (start ?? habit.created).startOfWeek(data.settings.weekStart).distance(to:end.startOfWeek(data.settings.weekStart))/7+1) }
    var body: some View {
        GeometryReader { proxy in
            let left: CGFloat = weekdayLabels ? 22 : 0
            let tile = max(2,(proxy.size.width-left-23*3)/24)
            ScrollView(.horizontal,showsIndicators:false) {
                Heatmap(habit:habit,data:data,weeks:weeks,end:end,monthLabels:monthLabels,weekdayLabels:weekdayLabels)
                    .frame(width:left+CGFloat(weeks)*(tile+3)-3)
            }.defaultScrollAnchor(.trailing)
        }.frame(height:monthLabels ? 106:88)
    }
}
struct CalendarDay: View {
    let habit: Habit
    let day: Day
    let data: BuddyData
    var inMonth = true
    var body: some View {
        let p=Engine.progress(habit,day:day,data:data),c=BuddyStyle.color(habit.color)
        VStack(spacing:3) {
            Text(String(Int(day.rawValue.suffix(2))!)).font(.system(size:13,weight:day==Day() ? .semibold:.regular,design:.monospaced))
                .foregroundStyle(p.success ? Color.primary:Color.secondary)
            if p.success || p.slip { Image(systemName:p.slip ? "xmark":"circle.fill").font(.system(size:4)).foregroundStyle(c) }
            else { Color.clear.frame(height:4) }
        }.frame(maxWidth:.infinity).frame(height:42)
            .background(c.opacity(p.success ? 0.17:p.fraction*0.12),in:RoundedRectangle(cornerRadius:12))
            .overlay{if day==Day() && data.settings.showToday{RoundedRectangle(cornerRadius:12).stroke(c,lineWidth:1.3)}}
            .opacity(!inMonth ? 0.45:day>Day() ? 0.3:1)
            .accessibilityLabel("\(day.rawValue), \(p.success ? "complete":p.slip ? "slip":"incomplete"), \(Amount.text(p.amount))")
    }
}
