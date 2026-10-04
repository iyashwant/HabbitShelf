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
    @State private var years=false
    @State private var yearCalendar=false
    @State private var milestones=false
    @State private var timing=false
    @State private var month=Day().startOfMonth
    var body:some View {
        Group {
            if let habit=store.habit(id) {
                let c=BuddyStyle.color(habit.color)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment:.leading,spacing:0) {
                            HStack(spacing:14.4) {
                                HabitIcon(habit:habit,size:52)
                                VStack(alignment:.leading,spacing:8.3) {
                                    Text(habit.name).font(BuddyFont.text(23,.heavy)).tracking(1.6).foregroundStyle(BuddyStyle.text(scheme)).lineLimit(2)
                                    Text(habit.detail.isEmpty ? "No Description":habit.detail).font(BuddyFont.text(13.75)).foregroundStyle(Color(hex:scheme == .dark ? 0xA0A0A8:0x6E6E75))
                                }
                            }.id("calendar-top")
                            ContributionHistory(habit:habit,data:store.data,shade:.detail,labelWidth:23.3,fade:15,shadeEdge:true)
                                .padding(.leading,12.7).padding(.trailing,11).padding(.top,11).padding(.bottom,8)
                                .surface(padding:0,radius:22,tint:c).padding(.top,16.7)
                            HStack(spacing:8){MetricChip(symbol:"flame",text:String(store.summaries.stats(habit,data:store.data).currentStreak),color:c);MetricChip(symbol:"target",text:habit.currentGoal.summary,color:c)}.padding(.top,12)
                            ForEach(months(habit),id:\.self){m in calendar(habit,m,proxy:proxy).padding(.top,20)}
                        }.padding(.horizontal,18).padding(.top,20.8).padding(.bottom,60)
                    }
                    .scrollIndicators(.hidden)
                    .safeAreaInset(edge:.top,spacing:0){
                        HStack(spacing:8) {
                            CircleControl(symbol:"chevron-left",label:"Back",size:38,glyph:12.5){dismiss()};Spacer()
                            CircleControl(symbol:"square-pen",label:"Edit Habit",size:38,glyph:16.8){editor=habit}.disabled(habit.archived != nil)
                            Menu {
                                Button("Year History",systemImage:"square.grid.3x3"){years=true}
                                Button("Year Calendar",systemImage:"calendar"){yearCalendar=true}
                                Button("Milestones",systemImage:"trophy"){milestones=true}
                                if TimerUnit(habit.currentGoal) != nil && habit.archived == nil {Button("Start Timer",systemImage:"timer"){timing=true}}
                                Button("Appearance",systemImage:"slider.horizontal.3"){appearance=true}
                                if store.data.settings.notes{Button("Notes",systemImage:"note.text"){notes=true}}
                                Button("Share Habit",systemImage:"square.and.arrow.up"){share=true}
                                Button(habit.archived == nil ? "Archive":"Restore",systemImage:"archivebox"){store.archive(habit.id,restore:habit.archived != nil)}
                            } label:{LucideIcon("settings",size:17).frame(width:38,height:38).background(BuddyStyle.control(scheme),in:Circle()).overlay{Circle().strokeBorder(BuddyStyle.controlBorder(scheme),lineWidth:1)}.foregroundStyle(BuddyStyle.text(scheme))}.accessibilityLabel("Habit Options")
                        }.padding(.horizontal,12).padding(.top,8.8).padding(.bottom,4).background(BuddyStyle.canvas(scheme))
                    }
                    .overlay{BottomFade()}
                }
                .sheet(isPresented:$share){ShareHabitView(habit:habit).buddySheet()}
                .sheet(isPresented:$notes){NotesView(habitID:id).buddySheet()}
                .sheet(isPresented:$appearance){HabitAppearanceView(habitID:id).buddySheet()}
                .sheet(isPresented:$jump){MonthJumpView(month:$month,earliest:Habit.earliestStart).buddySheet()}
                .navigationDestination(isPresented:$years){YearHistoryView(habitID:id)}
                .navigationDestination(isPresented:$yearCalendar){YearCalendarView(habitID:id)}
                .navigationDestination(isPresented:$milestones){MilestonesView(habitID:id)}
                .sheet(isPresented:$timing){TimerView(habitID:id).buddySheet()}
                .task {
                    #if DEBUG
                    let screen=ProcessInfo.processInfo.environment["BUDDY_VISUAL_SCREEN"]
                    if screen == "years" { years=true } else if screen == "year-calendar" { yearCalendar=true }
                    #endif
                }
            }else{ContentUnavailableView("Habit unavailable",systemImage:"archivebox")}
        }.background(BuddyStyle.canvas(scheme)).toolbar(.hidden,for:.navigationBar)
            .sheet(item:$editor){HabitEditorView(habit:$0).buddySheet()}.sheet(item:$selection){DayEditorView(selection:$0)}
    }
    private func months(_ h:Habit)->[Day] {
        // History scrolls back to the start month; earlier months open one at a time for backfilling.
        var result:[Day]=[],m=month
        while m>=min(month,h.created.startOfMonth){result.append(m);m=m.addingMonths(-1)}
        return result
    }
    private func calendar(_ h:Habit,_ m:Day,proxy:ScrollViewProxy)->some View {
        VStack(spacing:0) {
            let first=m.startOfWeek(store.data.settings.weekStart),today=Day()
            HStack(spacing:6.33){ForEach(0..<7,id:\.self){i in Text(Heatmap.weekday(store.data.settings.weekStart,i)).font(BuddyFont.mono(11.6)).foregroundStyle(Color(hex:scheme == .dark ? 0xA0A0A8:0x6E6E75)).frame(maxWidth:.infinity)}}
                .padding(.top,16.5).padding(.bottom,8.3)
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:6.33),count:7),spacing:5.33){
                ForEach(Day.range(first,first.adding(41))){day in
                    Button{tap(h,day)}label:{CalendarDay(habit:h,day:day,data:store.data,inMonth:day.month==m.month)}.buttonStyle(FlatButtonStyle()).disabled(!h.loggable(on:day,today:today))
                        .contextMenu{if store.data.settings.notes{Button("Add or Edit Note"){selection=DaySelection(habit:h,day:day)}};Button("Edit Progress"){selection=DaySelection(habit:h,day:day)}}
                }
            }
            HStack(spacing:10.3) {
                Button{month=m;jump=true}label:{
                    HStack(spacing:6){DrawnIcon(glyph:.calendar,size:21);Text(m.monthTitle).font(BuddyFont.mono(13))}
                        .foregroundStyle(BuddyStyle.text(scheme)).padding(.leading,14.5).padding(.trailing,17).frame(height:35)
                        .background(BuddyStyle.field(scheme),in:Capsule()).overlay{Capsule().strokeBorder(BuddyStyle.border(scheme,0.1),lineWidth:1)}
                }.buttonStyle(.plain).accessibilityLabel("Choose month, \(m.monthTitle)")
                Spacer()
                MonthArrow(next:false){month=m.addingMonths(-1);proxy.scrollTo("calendar-top",anchor:.top)}.disabled(m<=Habit.earliestStart.startOfMonth)
                MonthArrow(next:true){month=m.addingMonths(1);proxy.scrollTo("calendar-top",anchor:.top)}.disabled(m>=Day().startOfMonth.addingMonths(12))
            }.padding(.leading,1.7).padding(.trailing,2.4).padding(.top,14.3)
            if store.data.settings.notes{Text("Press and hold a day to add a note").font(BuddyFont.text(13)).tracking(-0.17).foregroundStyle(BuddyStyle.tertiaryText(scheme)).padding(.top,9.5)}
        }.padding(.horizontal,13.5).padding(.bottom,11.5).panel(radius:24,border:0.09)
    }
    private func tap(_ h:Habit,_ day:Day){let g=h.goal(on:day),p=Engine.progress(h,day:day,data:store.data);if g.mode != h.currentGoal.mode || g.mode == .quit || g.tap == .enterTotal || (g.tracking != .yesNo && p.success){selection=DaySelection(habit:h,day:day)}else{store.quickLog(h,day:day)}}
}
/// Outlined month arrow with the reference's thin chevron.
struct MonthArrow:View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    let next:Bool
    var action:()->Void
    var body:some View {
        Button(action:action){
            Path{p in p.move(to:CGPoint(x:next ? 0.75:7.25,y:0.75));p.addLine(to:CGPoint(x:next ? 7.25:0.75,y:7.5));p.addLine(to:CGPoint(x:next ? 0.75:7.25,y:14.25))}
                .stroke(style:StrokeStyle(lineWidth:1.5,lineCap:.round,lineJoin:.round)).frame(width:8,height:15).offset(x:next ? 1.6:-1.6)
                .foregroundStyle(BuddyStyle.text(scheme).opacity(enabled ? 1:0.3)).frame(width:43,height:33)
                .overlay{Capsule().strokeBorder(BuddyStyle.border(scheme,0.1),lineWidth:1)}.contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityLabel(next ? "Next month":"Previous month")
    }
}
/// Content fades into the canvas above the home indicator.
struct BottomFade:View {
    @Environment(\.colorScheme) private var scheme
    var body:some View {
        GeometryReader { _ in
            LinearGradient(stops:[.init(color:BuddyStyle.canvas(scheme).opacity(0),location:0),.init(color:BuddyStyle.canvas(scheme),location:0.67),.init(color:BuddyStyle.canvas(scheme),location:1)],startPoint:.top,endPoint:.bottom)
                .frame(height:52).frame(maxHeight:.infinity,alignment:.bottom)
        }.ignoresSafeArea().allowsHitTesting(false)
    }
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
    @State private var freeze = false
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
                if store.data.settings.freezesPerMonth > 0 && (Engine.canFreeze(habit, day: selection.day, data: store.data) || store.data.record(habit.id, selection.day).frozen == true) {
                    let used = Engine.freezesUsed(habit, month: selection.day, data: store.data), allowance = store.data.settings.freezesPerMonth
                    Section {
                        Toggle("Freeze Streak", isOn: $freeze).disabled(!freeze && used >= allowance)
                    } header: { Text("Streak freeze") } footer: {
                        Text("\(max(0, allowance - used)) of \(allowance) freezes left in \(Calendar.current.monthSymbols[Int(selection.day.rawValue.dropFirst(5).prefix(2))! - 1]). A frozen day keeps the streak going but still counts as missed in your completion rate.")
                    }
                }
                if store.data.settings.notes { Section("Day note") { TextEditor(text: $note).frame(minHeight: 140); Text("A note does not change progress.").font(.caption).foregroundStyle(.secondary) } }
                if let text = message ?? store.error { Text(text).foregroundStyle(.red) }
            }.navigationTitle("Edit Day").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } } }
                .onAppear { let record = store.data.record(habit.id, selection.day); amount = Amount.text(record.amount); note = record.note; complete = record.amount > 0; freeze = record.frozen == true }
        }
    }
    private func save() {
        do {
            let value = goal.tracking == .yesNo ? (complete ? Int64(1_000) : 0) : try Amount.parse(amount)
            let locked = self.locked, id = habit.id, day = selection.day, note = self.note, freeze = self.freeze
            if store.change(touching: [id], { data in
                if !locked { try Engine.setAmount(value, habitID: id, day: day, data: &data) }
                if data.settings.notes { try Engine.note(note, habitID: id, day: day, data: &data) }
                // Logging the day as done replaces a freeze, so a freeze applies only to a day that stays missed.
                if freeze != (data.record(id, day).frozen == true), let h = data.activeHabit(id), !freeze || Engine.canFreeze(h, day: day, data: data) {
                    try Engine.setFreeze(freeze, habitID: id, day: day, data: &data)
                }
            }) { dismiss() }
        } catch { message = error.localizedDescription }
    }
}
