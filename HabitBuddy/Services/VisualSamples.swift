import Foundation

enum VisualSamples {
    /// Ten habits with `days` of history (220 for the sample habits and the screenshots).
    static func populate(_ data:inout BuddyData,days:Int=220) {
        guard data.habits.isEmpty else{return}
        let definitions=[("Gym Day","Every other day, no excuses.","heart.fill","mint"),("Push-Ups","A little stronger every day.","dumbbell.fill","rose"),("Journal","Three lines to clear my mind.","pencil.tip","teal"),("Deep Work","Four focused blocks.","laptopcomputer","blue"),("Drink Water","Stay hydrated.","drop.fill","sky"),("Read","One chapter at a time.","book.closed.fill","amber"),("Meditate","Ten quiet minutes.","figure.mind.and.body","violet"),("Coding","Make something every day.","code","yellow"),("No Doomscrolling","Put the phone down.","phone.down.fill","pink"),("Daily Walk","Get outside.","figure.walk","cyan")]
        for (n,item) in definitions.enumerated() {
            var h=Habit(name:item.0,created:Day().adding(-days));h.id=UUID(uuidString:String(format:"00000000-0000-0000-0000-%012d",n+1))!;h.detail=item.1;h.symbol=item.2;h.color=item.3;h.order=n;h.goals[0].cadence = .daily
            if n==0{h.goals[0].cadence = .weekly;h.goals[0].days=3}
            if n==2{h.goals[0].cadence = .monthly;h.goals[0].days=20}
            if [1,3,4].contains(n){h.goals[0].tracking = .count;h.goals[0].target=Int64(n==1 ? 3:n==3 ? 4:8)*1_000}
            if n==6{h.goals[0].tracking = .measure;h.goals[0].target=10_000;h.goals[0].unit="minutes";h.goals[0].tap = .enterTotal}
            if n==8{h.goals[0].mode = .quit}
            data.habits.append(h)
            for offset in 0...days {
                let day=Day().adding(-offset);var r=Record(habitID:h.id,day:day)
                let complete=(offset*13+n*7)%11<8
                r.amount=h.currentGoal.mode == .quit ? (complete ? 0:1_000):complete ? h.currentGoal.target:0
                if offset==0 { r.amount=n==2 ? 1_000:n==4 ? 3_000:0 }
                if r.amount>=h.currentGoal.target && h.currentGoal.mode == .build { r.completedAt=day.date.addingTimeInterval(Double(10+n)*3_600);r.completionHour=10+n }
                if n==0 && [0,3,7,15,28].contains(offset){r.note=["A short session still counts.","More energy after moving.","Made time before work.","Kept a steady pace.","Glad I showed up."][offset==0 ? 0:offset==3 ? 1:offset==7 ? 2:offset==15 ? 3:4]}
                if n==2 && [1,9,40].contains(offset){r.note=offset==1 ? "Wrote about the weekend trip.":offset==9 ? "Hard to focus, still wrote three lines.":"Started a gratitude list."}
                if n==6 && [2,20].contains(offset){r.note=offset==2 ? "Breathing exercise before bed.":"Ten minutes felt short today."}
                if r.amount>0 || !r.note.isEmpty {data.records[r.key]=r}
            }
        }
        if data.routines.isEmpty {
            var routine=Routine(name:"Morning");routine.id=UUID(uuidString:"00000000-0000-0000-0004-000000000001")!;routine.habitIDs=[2,4,6].map{data.habits[$0].id}
            data.routines=[routine]
        }
    }
    #if DEBUG
    /// The two habits from the owner's HabitKit screenshots (captured 2026-10-03), for side-by-side comparison.
    static func reference(_ data:inout BuddyData) {
        func day(_ text:String)->Day { Day(rawValue:text)! }
        let habits:[(String,String,String,String,[ClosedRange<Day>])]=[
            ("No smoking","lu:cigarette","stone","2026-09-14",[day("2026-09-14")...day("2026-09-24"),day("2026-09-26")...day("2026-09-26"),day("2026-09-28")...day("2026-10-01")]),
            ("No dope","lu:activity","coral","2026-09-13",[day("2026-09-13")...day("2026-10-01")])]
        for (n,item) in habits.enumerated() {
            var h=Habit(name:item.0,created:day(item.3));h.id=UUID(uuidString:String(format:"00000000-0000-0000-0001-%012d",n+1))!;h.symbol=item.1;h.color=item.2;h.order=n
            h.goals[0].cadence = .none // Preserve the original reference fixture when new-habit defaults change.
            if n==1 { h.goals[0].cadence = .weekly;h.goals[0].days=5 }
            data.habits.append(h)
            for range in item.4 { for d in Day.range(range.lowerBound,range.upperBound) {
                var r=Record(habitID:h.id,day:d);r.amount=1_000;r.completedAt=d.date.addingTimeInterval(20*3_600);r.completionHour=20;data.records[r.key]=r
            } }
        }
    }
    /// `on`, or `transparency:tint:strength` with any part left empty (e.g. `0:teal:0.4`); empty is off.
    static func visualGlass(_ text:String)->GlassSettings? {
        guard !text.isEmpty else{return nil}
        var glass=GlassSettings(enabled:true)
        guard text != "on" else{return glass}
        let parts=text.split(separator:":",omittingEmptySubsequences:false).map(String.init)
        glass.transparency=parts.first.flatMap{Double($0)}
        glass.tint=parts.count>1 && !parts[1].isEmpty ? parts[1]:nil
        glass.tintStrength=parts.count>2 ? Double(parts[2]):nil
        return glass
    }
    /// The sample habits and twenty more daily habits over five years, about 40,000 logged days, for the performance
    /// tests (`BUDDY_VISUAL_FIXTURE=large`).
    static func large(_ data:inout BuddyData) {
        populate(&data,days:1_826)
        let colors=["mint","rose","teal","blue","sky","amber","violet","yellow","pink","cyan"]
        for n in 10..<30 {
            var h=Habit(name:"Habit \(n+1)",created:Day().adding(-1_826));h.id=UUID(uuidString:String(format:"00000000-0000-0000-0000-%012d",n+1))!;h.symbol="book.closed.fill";h.color=colors[n%10];h.order=n;h.goals[0].cadence = .daily
            data.habits.append(h)
            for offset in 0...1_826 where (offset*13+n*7)%11<8 { var r=Record(habitID:h.id,day:Day().adding(-offset));r.amount=1_000;data.records[r.key]=r }
        }
    }
    /// Synthetic regression: twelve successes through yesterday, Daily enabled only today.
    /// Uses the isolated VisualAudit store, never the owner's habit data.
    static func streakHistory(_ data: inout BuddyData) {
        let today = Day()
        var habit = Habit(name: "Streak history", created: today.adding(-20))
        habit.id = UUID(uuidString: "00000000-0000-0000-0005-000000000001")!
        habit.symbol = "lu:leaf"; habit.color = "green"
        habit.goals[0].cadence = .none
        var daily = habit.currentGoal
        daily.from = today; daily.cadence = .daily
        habit.goals.append(daily)
        data.habits = [habit]
        for offset in Array(1...12) + Array(17...20) {
            var record = Record(habitID: habit.id, day: today.adding(-offset))
            record.amount = 1_000
            data.records[record.key] = record
        }
    }
    static func audit(_ screen:String)->BuddyData {
        var data=BuddyData()
        switch ProcessInfo.processInfo.environment["BUDDY_VISUAL_FIXTURE"] { case "reference": reference(&data); case "large": large(&data); case "streak-history": streakHistory(&data); default: populate(&data) }
data.settings.onboarding=screen != "welcome";data.settings.theme=ProcessInfo.processInfo.environment["BUDDY_VISUAL_THEME"] == "light" ? .light:.dark
        data.settings.accent=ProcessInfo.processInfo.environment["BUDDY_VISUAL_ACCENT"].flatMap{$0.isEmpty ? nil:$0}
        data.settings.glass=ProcessInfo.processInfo.environment["BUDDY_VISUAL_GLASS"].flatMap(visualGlass)
        data.settings.layout=Layout(rawValue:screen) ?? (screen=="compact-settings" ? .compact:.cards)
        if screen=="today-ring" { data.settings.dashboard=[DashboardWidget(kind:.today,style:.dark),DashboardWidget(kind:.today,style:.light),DashboardWidget(kind:.today,style:.tinted),DashboardWidget(kind:.streak,habitID:data.habits[6].id,style:.automatic)] }
        // Every design in the sizes and options the default dashboard doesn't show.
        if screen=="widgets", data.habits.count>=8, let routine=data.routines.first {
            func habit(_ kind:DashboardKind,_ n:Int,_ style:WidgetStyle,_ size:WidgetSize?=nil)->DashboardWidget { DashboardWidget(kind:kind,habitID:data.habits[n].id,style:style,size:size) }
            var routineSmall=DashboardWidget(kind:.routine,style:.light);routineSmall.routineID=routine.id
            var routineMedium=DashboardWidget(kind:.routine,style:.tinted,size:.medium);routineMedium.routineID=routine.id
            var evening=DashboardWidget(kind:.checks,style:.tinted,size:.large);evening.title="Evening";evening.habitIDs=[2,5,6,7,9].map{data.habits[$0].id};evening.color="violet"
            var week=DashboardWidget(kind:.week,style:.light);week.color="green"
            data.settings.dashboard=[habit(.ring,6,.dark),habit(.ring,0,.light),habit(.badge,1,.automatic),habit(.stats,3,.tinted),habit(.stats,5,.dark,.medium),
                                     DashboardWidget(kind:.today,style:.automatic,size:.medium),routineSmall,DashboardWidget(kind:.checks,style:.dark,size:.small),routineMedium,
                                     habit(.year,0,.dark,.large),habit(.month,7,.light,.large),evening,DashboardWidget(kind:.list,style:.dark,size:.medium),week]
        }
        return data
    }
    #endif
}
