import SwiftUI

struct WelcomeView:View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.colorScheme) private var scheme
    private let features=[("square.grid.3x3.fill","See your progress","A tile for every day. A grid that grows with you.","mint"),("checkmark","One tap to check in","Log today's habit right from the overview.","cyan"),("paintbrush","Make it yours","Choose an icon, a color, and a goal.","violet"),("flame","Build a steady streak","Daily, weekly, or monthly goals at your pace.","orange"),("chart.xyaxis.line","Understand your habits","Look back at completions and consistency.","blue"),("bell","A gentle reminder","Choose the days and times that work for you.","yellow"),("rectangle.3.group","Home screen widgets","Keep your habits close at hand.","pink"),("lock","Private by design","Your habits stay on your device. No account needed.","teal")]
    var body:some View {
        VStack(spacing:0){ScrollView{VStack(alignment:.leading,spacing:12){Text("Welcome to\n\(Text("Habit Buddy").foregroundColor(BuddyStyle.purple))").font(.system(size:32,weight:.bold)).padding(.vertical,20);ForEach(features.indices,id:\.self){i in let f=features[i];HStack(spacing:14){Image(systemName:f.0).font(.system(size:20)).foregroundStyle(BuddyStyle.color(f.3)).frame(width:42,height:42).background(BuddyStyle.color(f.3).opacity(0.13),in:RoundedRectangle(cornerRadius:12));VStack(alignment:.leading,spacing:5){Text(f.1).font(.system(size:14,weight:.semibold));Text(f.2).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)};Spacer()}.surface()}}.padding(20)};PrimaryAction(title:"Continue"){store.change{$0.settings.onboarding=true}}.padding(24)}.background(BuddyStyle.canvas(scheme))
    }
}
