import Foundation

enum VisualSamples {
    static func populate(_ data:inout BuddyData) {
        guard data.habits.isEmpty else{return}
        let definitions=[("Gym Day","Every other day, no excuses.","heart.fill","mint"),("Push-Ups","A little stronger every day.","dumbbell.fill","rose"),("Journal","Three lines to clear my mind.","pencil.tip","teal"),("Deep Work","Four focused blocks.","laptopcomputer","blue"),("Drink Water","Stay hydrated.","drop.fill","sky"),("Read","One chapter at a time.","book.closed.fill","amber"),("Meditate","Ten quiet minutes.","figure.mind.and.body","violet"),("Coding","Make something every day.","code","yellow"),("No Doomscrolling","Put the phone down.","phone.down.fill","pink"),("Daily Walk","Get outside.","figure.walk","cyan")]
        for (n,item) in definitions.enumerated() {
            var h=Habit(name:item.0,created:Day().adding(-220));h.id=UUID(uuidString:String(format:"00000000-0000-0000-0000-%012d",n+1))!;h.detail=item.1;h.symbol=item.2;h.color=item.3;h.order=n;h.goals[0].cadence = .daily
            if n==0{h.goals[0].cadence = .weekly;h.goals[0].days=3}
            if n==2{h.goals[0].cadence = .monthly;h.goals[0].days=20}
            if [1,3,4].contains(n){h.goals[0].tracking = .count;h.goals[0].target=Int64(n==1 ? 3:n==3 ? 4:8)*1_000}
            if n==6{h.goals[0].tracking = .measure;h.goals[0].target=10_000;h.goals[0].unit="minutes";h.goals[0].tap = .enterTotal}
            if n==8{h.goals[0].mode = .quit}
            data.habits.append(h)
            for offset in 0...220 {
                let day=Day().adding(-offset);var r=Record(habitID:h.id,day:day)
                let complete=(offset*13+n*7)%11<8
                r.amount=h.currentGoal.mode == .quit ? (complete ? 0:1_000):complete ? h.currentGoal.target:0
                if offset==0 { r.amount=n==2 ? 1_000:n==4 ? 3_000:0 }
                if r.amount>=h.currentGoal.target && h.currentGoal.mode == .build { r.completedAt=day.date.addingTimeInterval(Double(10+n)*3_600);r.completionHour=10+n }
                if n==0 && [0,3,7,15,28].contains(offset){r.note=["A short session still counts.","More energy after moving.","Made time before work.","Kept a steady pace.","Glad I showed up."][offset==0 ? 0:offset==3 ? 1:offset==7 ? 2:offset==15 ? 3:4]}
                if r.amount>0 || !r.note.isEmpty {data.records[r.key]=r}
            }
        }
    }
    #if DEBUG
    static func audit(_ screen:String)->BuddyData {
        var data=BuddyData();populate(&data);data.settings.onboarding=screen != "welcome";data.settings.theme=ProcessInfo.processInfo.environment["BUDDY_VISUAL_THEME"] == "light" ? .light:.dark
        data.settings.layout=screen=="compact" ? .compact:screen=="month" ? .month:.cards
        return data
    }
    #endif
}
