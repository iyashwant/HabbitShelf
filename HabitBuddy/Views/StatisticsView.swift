import SwiftUI
import Charts

struct StatisticsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var selected: UUID?
    @State private var year = Int(Day().rawValue.prefix(4))!
    @State private var review = false
    @State private var summary=StatisticsSummary()
    private var habits: [Habit] { store.data.habits.filter { selected == nil || $0.id == selected! } }
    private var start: Day { Day(rawValue: "\(year)-01-01")! }
    private var end: Day { min(Day(), Day(rawValue: "\(year)-12-31")!) }
    private var days: [Day] { Day.range(start, end) }
    private var completions:Int { summary.completions }
    private var eligible:Int { summary.eligible }
    private var accent: Color { BuddyStyle.color(habits.first?.color ?? "mint") }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    HStack(spacing:10){if let h=store.data.habits.first(where:{$0.id==selected}){HabitIcon(habit:h,size:34);VStack(alignment:.leading,spacing:3){Text(h.name).font(.system(size:14,weight:.semibold));Text(h.detail).font(.system(size:11)).foregroundStyle(.secondary)}}else{Text("All Habits").font(.system(size:14,weight:.semibold))};Spacer()}.surface()
                    HStack { Button { year -= 1 } label: { Image(systemName: "chevron.left") }.disabled(year <= 1970); Spacer(); Text(String(year)).font(.system(size:15,weight:.semibold)); Spacer(); Button { year += 1 } label: { Image(systemName: "chevron.right") }.disabled(year >= Int(Day().rawValue.prefix(4))!) }.font(.system(size:12,design:.monospaced)).padding(.horizontal,12).padding(.vertical,8).background(Color.primary.opacity(0.035),in:Capsule())
                    if let h = habits.first { ContributionHistory(habit:visualHabit(h),data:aggregateHeatmap(h),start:start,end:end).surface() }
                    HStack { metric("Completions", "\(completions)", "number"); metric("Completion Rate", "\(eligible == 0 ? 0 : Int(Double(completions) / Double(eligible) * 100))", "percent") }
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Completions / Month").font(.system(size:15,weight:.semibold))
                        Chart(1...12, id: \.self) { month in
                            let count = monthlyCount(month)
                            AreaMark(x: .value("Month", month), y: .value("Completions", count)).foregroundStyle(accent.opacity(0.2)).interpolationMethod(.monotone)
                            LineMark(x: .value("Month", month), y: .value("Completions", count)).foregroundStyle(accent).lineStyle(StrokeStyle(lineWidth:1.5)).interpolationMethod(.monotone)
                            PointMark(x:.value("Month",month),y:.value("Completions",count)).foregroundStyle(accent).symbolSize(9)
                        }.chartXAxis { AxisMarks(values: Array(1...12)) { value in AxisValueLabel { if let month = value.as(Int.self) { Text(Calendar.current.shortMonthSymbols[month - 1]).font(.caption2) } } } }.chartYAxis(.hidden).frame(height:140)
                            .accessibilityLabel("Monthly habit completions for \(year)")
                    }.surface()
                    HStack { metric("Current Streak", "\(summary.currentStreak)", "flame.fill"); metric("Best Streak", "\(summary.bestStreak)", "flame") }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Completion Time").font(.system(size:15,weight:.semibold))
                        Chart(0..<24, id: \.self) { hour in
                            BarMark(x: .value("Hour", hour), y: .value("Completions", hourlyCount(hour))).foregroundStyle(accent)
                        }.chartYAxis(.hidden).frame(height:140).chartXAxis { AxisMarks(values: [0, 6, 12, 18]) { value in AxisValueLabel { if let hour = value.as(Int.self) { Text("\(hour):00").font(.caption2) } } } }
                    }.surface()
                    Button("Year Review",systemImage:"square.and.arrow.up"){review=true}.buttonStyle(.bordered)
                    DisclosureGroup("Monthly totals") { ForEach(1...12, id: \.self) { m in HStack { Text(Calendar.current.monthSymbols[m - 1]); Spacer(); Text("\(monthlyCount(m))").monospacedDigit() }.font(.caption).padding(.vertical, 3) } }
                }.padding(20)
            }.background(BuddyStyle.canvas(scheme)).toolbar(.hidden,for:.navigationBar)
                .safeAreaInset(edge:.top) {
                    HStack(spacing:8) {
                        ScrollView(.horizontal,showsIndicators:false) {
                            HStack(spacing:8) {
                                Button { selected=nil } label: {Image(systemName:"square.grid.3x3.fill").frame(width:36,height:36).background(Color.primary.opacity(0.06),in:Circle())}.buttonStyle(.plain).accessibilityLabel("All Habits")
                                ForEach(store.data.habits) { h in Button { selected=h.id } label: {HabitIcon(habit:h,size:36,circular:true).overlay{if selected==h.id{Circle().stroke(BuddyStyle.color(h.color),lineWidth:1.5)}}}.buttonStyle(.plain).accessibilityLabel(h.name).accessibilityAddTraits(selected==h.id ? .isSelected:[]) }
                            }
                        }
                        Button("Done"){dismiss()}.font(.system(size:13,weight:.semibold)).foregroundStyle(.white).padding(.horizontal,14).padding(.vertical,10).background(BuddyStyle.purple,in:Capsule())
                    }.padding(.horizontal,20).padding(.vertical,8).background(BuddyStyle.canvas(scheme))
                }
                .onAppear {
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["BUDDY_VISUAL_SCREEN"] == "statistics" { selected=store.data.active.first?.id }
                    #endif
                    refreshSummary()
                }
                .onChange(of:selected){_,_ in refreshSummary()}
                .onChange(of:year){_,_ in refreshSummary()}
                .onChange(of:store.data){_,_ in refreshSummary()}
                .sheet(isPresented: $review) { YearReviewView(year: year, habits: habits) }
        }
    }
    private func refreshSummary(){summary=StatisticsSummary(data:store.data,habitIDs:selected.map{[$0]},year:year)}
    private func monthlyCount(_ month:Int)->Int { summary.monthly[month-1] }
    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 13) { HStack { Spacer(); Image(systemName: icon).foregroundStyle(accent).padding(7).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8)) }; Text(value).font(.system(size:25,weight:.bold)).monospacedDigit(); Text(title).font(.system(size:11)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).surface()
    }
    private func aggregateHeatmap(_ sample: Habit) -> BuddyData {
        guard selected == nil else { return store.data }
        var result = store.data
        result.records = result.records.filter { $0.value.habitID != sample.id }
        for day in days {
            var record = Record(habitID: sample.id, day: day)
            record.amount = habits.contains { $0.goal(on: day).mode == .build && Engine.progress($0, day: day, data: store.data).success } ? 1_000 : 0
            result.records[record.key] = record
        }
        return result
    }
    private func visualHabit(_ sample: Habit) -> Habit {
        guard selected == nil else { return sample }
        var h = sample; h.created = start; h.archived = nil; h.pauses = []; h.goals = [Goal(from: start)]; return h
    }
    private func hourlyCount(_ hour:Int)->Int { summary.hourly[hour] }
}
