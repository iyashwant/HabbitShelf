import SwiftUI

struct HabitDetailView: View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let id:UUID
    @State private var editor:Habit?
    @State private var selection:DaySelection?
    @State private var share=false
    @State private var notes=false
    @State private var appearance=false
    @State private var jump=false
    @State private var month=Day().startOfMonth
    var body:some View {
        Group {
            if let habit=store.habit(id) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment:.leading,spacing:18) {
                            HStack(spacing:12){HabitIcon(habit:habit,size:48);VStack(alignment:.leading,spacing:4){Text(habit.name).font(.system(size:23,weight:.bold));if !habit.detail.isEmpty{Text(habit.detail).font(.system(size:13)).foregroundStyle(.secondary)}}}.id("calendar-top")
                            ContributionHistory(habit:habit,data:store.data).surface(tint:BuddyStyle.color(habit.color))
                            HStack{MetricChip(symbol:"flame.fill",text:String(Engine.stats(habit,data:store.data).currentStreak),color:BuddyStyle.color(habit.color));MetricChip(symbol:"target",text:habit.currentGoal.summary,color:BuddyStyle.color(habit.color))}
                            ForEach(months(habit),id:\.self){m in calendar(habit,m,proxy:proxy)}
                        }.padding(20)
                    }
                    .safeAreaInset(edge:.top){
                        HStack {
                            CircleControl(symbol:"chevron.left",label:"Back"){dismiss()};Spacer()
                            CircleControl(symbol:"square.and.pencil",label:"Edit Habit"){editor=habit}.disabled(habit.archived != nil)
                            Menu {
                                Button("Appearance",systemImage:"slider.horizontal.3"){appearance=true}
                                if store.data.settings.notes{Button("Notes",systemImage:"note.text"){notes=true}}
                                Button("Share Habit",systemImage:"square.and.arrow.up"){share=true}
                                Button(habit.archived == nil ? "Archive":"Restore",systemImage:"archivebox"){store.archive(habit.id,restore:habit.archived != nil)}
                            } label:{Image(systemName:"gearshape").font(.system(size:16)).frame(width:34,height:34).background(BuddyStyle.surface(scheme),in:Circle()).padding(5)}.accessibilityLabel("Habit Options")
                        }.padding(.horizontal,12).background(BuddyStyle.canvas(scheme))
                    }
                }
                .sheet(isPresented:$share){ShareHabitView(habit:habit)}
                .sheet(isPresented:$notes){NotesView(habitID:id)}
                .sheet(isPresented:$appearance){HabitAppearanceView(habitID:id)}
                .sheet(isPresented:$jump){MonthJumpView(month:$month,earliest:habit.created)}
            }else{ContentUnavailableView("Habit unavailable",systemImage:"archivebox")}
        }.background(BuddyStyle.canvas(scheme)).toolbar(.hidden,for:.navigationBar)
            .sheet(item:$editor){HabitEditorView(habit:$0)}.sheet(item:$selection){DayEditorView(selection:$0)}
    }
    private func months(_ h:Habit)->[Day] {
        var result:[Day]=[],m=month
        while m>=h.created.startOfMonth{result.append(m);m=m.addingMonths(-1)}
        return result
    }
    private func calendar(_ h:Habit,_ m:Day,proxy:ScrollViewProxy)->some View {
        VStack(spacing:14) {
            let first=m.startOfWeek(store.data.settings.weekStart)
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:5),count:7),spacing:5){
                ForEach(0..<7,id:\.self){i in Text(Calendar.current.shortWeekdaySymbols[(store.data.settings.weekStart-1+i)%7]).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary).frame(height:22)}
                ForEach(Day.range(first,first.adding(41))){day in
                    Button{tap(h,day)}label:{CalendarDay(habit:h,day:day,data:store.data,inMonth:day.month==m.month)}.buttonStyle(.plain).disabled(day.month != m.month || !h.available(on:day,today:Day()) || h.archived != nil)
                        .contextMenu{if store.data.settings.notes{Button("Add or Edit Note"){selection=DaySelection(habit:h,day:day)}};Button("Edit Progress"){selection=DaySelection(habit:h,day:day)}}
                }
            }
            HStack {
                Button{month=m;jump=true}label:{Label(m.monthTitle,systemImage:"calendar").font(.system(size:12,design:.monospaced)).padding(10).background(Color.primary.opacity(0.035),in:Capsule())}.buttonStyle(.plain)
                Spacer()
                CircleControl(symbol:"chevron.left",label:"Previous month"){month=m.addingMonths(-1);proxy.scrollTo("calendar-top",anchor:.top)}.disabled(m<=h.created.startOfMonth)
                CircleControl(symbol:"chevron.right",label:"Next month"){month=m.addingMonths(1);proxy.scrollTo("calendar-top",anchor:.top)}.disabled(m>=Day().startOfMonth)
            }
            if store.data.settings.notes{Text("Press and hold a day to add a note").font(.system(size:10)).foregroundStyle(.secondary)}
        }.surface(padding:12,radius:20)
    }
    private func tap(_ h:Habit,_ day:Day){let g=h.goal(on:day),p=Engine.progress(h,day:day,data:store.data);if g.mode != h.currentGoal.mode || g.mode == .quit || g.tap == .enterTotal || (g.tracking != .yesNo && p.success){selection=DaySelection(habit:h,day:day)}else{store.quickLog(h,day:day)}}
}
struct MonthJumpView:View {
    @Binding var month:Day
    let earliest:Day
    @Environment(\.dismiss) private var dismiss
    @State private var date=Day().localDate
    var body:some View {VStack{SheetHeader(title:"Choose Month");DatePicker("Month",selection:$date,in:earliest.localDate...Day().localDate,displayedComponents:.date).datePickerStyle(.graphical);PrimaryAction(title:"Go"){month=Day(date).startOfMonth;dismiss()}}.padding(20).onAppear{date=max(earliest,month).localDate}}
}
struct DayEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let selection: DaySelection
    @State private var amount = "0"
    @State private var note = ""
    @State private var complete = false
    @State private var message: String?
    private var habit: Habit { store.habit(selection.habit.id) ?? selection.habit }
    private var goal: Goal { habit.goal(on: selection.day) }
    private var locked: Bool { goal.mode != habit.currentGoal.mode }
    var body: some View {
        NavigationStack {
            Form {
                Section { HStack { HabitIcon(habit: habit); VStack(alignment: .leading) { Text(habit.name).font(.headline); Text(selection.day.rawValue).font(.caption).foregroundStyle(.secondary) } } }
                Section(goal.mode == .quit ? "Slip / amount" : "Progress") {
                    if goal.tracking == .yesNo { Toggle(goal.mode == .quit ? "I had a slip" : "Completed", isOn: $complete).disabled(locked) }
                    else { TextField("Amount in \(goal.unit)", text: $amount).keyboardType(.decimalPad).disabled(locked); Text(goal.mode == .quit ? "A clean day stays strictly below \(Amount.text(goal.target)) \(goal.unit)." : "Target: \(Amount.text(goal.target)) \(goal.unit)").font(.caption).foregroundStyle(.secondary) }
                    if locked { Text("This date belongs to an earlier habit mode. Its progress is preserved.").font(.caption).foregroundStyle(.secondary) }
                    else { Button("Clear Progress") { amount = "0"; complete = false } }
                }
                if store.data.settings.notes { Section("Day note") { TextEditor(text: $note).frame(minHeight: 140); Text("A note does not change progress.").font(.caption).foregroundStyle(.secondary) } }
                if let text = message ?? store.error { Text(text).foregroundStyle(.red) }
            }.navigationTitle("Edit Day").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } } }
                .onAppear { let record = store.data.record(habit.id, selection.day); amount = Amount.text(record.amount); note = record.note; complete = record.amount > 0 }
        }
    }
    private func save() {
        do {
            let value = goal.tracking == .yesNo ? (complete ? Int64(1_000) : 0) : try Amount.parse(amount)
            if store.change({ data in
                if !locked { try Engine.setAmount(value, habitID: habit.id, day: selection.day, data: &data) }
                if data.settings.notes { try Engine.note(note, habitID: habit.id, day: selection.day, data: &data) }
            }) { dismiss() }
        } catch { message = error.localizedDescription }
    }
}
