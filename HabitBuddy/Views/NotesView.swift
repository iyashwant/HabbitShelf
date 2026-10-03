import SwiftUI

struct NotesView:View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let habitID:UUID
    @State private var selection:DaySelection?
    private var records:[Record]{store.data.records.values.filter{$0.habitID==habitID && !$0.note.isEmpty}.sorted{$0.day>$1.day}}
    var body:some View {
        VStack(spacing:12) {
            if let h=store.habit(habitID){
                let records=self.records
                HStack{CircleControl(symbol:"chevron.left",label:"Close Notes"){dismiss()};HabitIcon(habit:h,size:32);VStack(alignment:.leading){Text("Notes").font(.system(size:16,weight:.semibold));Text(h.name).font(.system(size:12)).foregroundStyle(.secondary)};Spacer();CircleControl(symbol:"plus",label:"Add Note",filled:true){selection=DaySelection(habit:h,day:Day())}.disabled(h.archived != nil)}.padding(.horizontal,12).padding(.top,8)
                ScrollView {
                    LazyVStack(spacing:12){
                        ContributionHistory(habit:h,data:store.data).padding(.bottom,8)
                        if records.isEmpty{ContentUnavailableView("No notes yet",systemImage:"note.text",description:Text("Add a thought about your day."))}
                        ForEach(records,id:\.key){r in Button{selection=DaySelection(habit:h,day:r.day)}label:{VStack(alignment:.leading,spacing:8){HStack{Circle().fill(BuddyStyle.color(h.color)).frame(width:5,height:5);Text(r.day.noteTitle).font(.system(size:11,weight:.medium));Spacer()};Text(r.note).font(.system(size:13)).frame(maxWidth:.infinity,alignment:.leading)}.foregroundStyle(.primary).surface(padding:13,radius:13).overlay{if r.day==Day(){RoundedRectangle(cornerRadius:13).stroke(BuddyStyle.color(h.color),lineWidth:1)}}}.buttonStyle(.plain).disabled(h.archived != nil)}
                    }.padding(20)
                }
            }
        }.background(BuddyStyle.canvas(scheme)).sheet(item:$selection){DayEditorView(selection:$0)}
    }
}
struct HabitAppearanceView:View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.colorScheme) private var scheme
    let habitID:UUID
    private func option(_ key:WritableKeyPath<CardAppearance,Bool>)->Binding<Bool>{Binding(get:{store.habit(habitID)?.cardAppearance(store.data.settings)[keyPath:key] ?? true},set:{value in store.change{data in if let i=data.habits.firstIndex(where:{$0.id==habitID}){var a=data.habits[i].cardAppearance(data.settings);a[keyPath:key]=value;data.habits[i].appearance=a}}})}
    var body:some View {
        VStack(spacing:0){SheetHeader(title:"Appearance");ScrollView{VStack(spacing:20){if let h=store.habit(habitID){HabitCard(habit:h,data:store.data,interactive:false)};VStack(spacing:14){Toggle("Description",isOn:option(\.description));Toggle("Streak",isOn:option(\.streak));Toggle("Streak Goal",isOn:option(\.goal));Toggle("Completion Indicator",isOn:option(\.indicator));Toggle("Month Labels",isOn:option(\.monthLabels));Toggle("Weekday Labels",isOn:option(\.weekdayLabels));Toggle("Category Icons",isOn:option(\.categoryIcons))}.font(.system(size:14)).surface();Button("Use Overview Defaults"){store.change{data in if let i=data.habits.firstIndex(where:{$0.id==habitID}){data.habits[i].appearance=nil}}}}.padding(20)}}.background(BuddyStyle.canvas(scheme))
    }
}
