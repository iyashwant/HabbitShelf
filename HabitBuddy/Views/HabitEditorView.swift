import SwiftUI
import UserNotifications

struct HabitEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State var habit: Habit
    @State private var target = "1"
    @State private var emoji = ""
    @State private var symbolSearch = ""
    @State private var icons = false
    @State private var reminders = false
    @State private var validation: String?
    private var existing: Bool { store.habit(habit.id) != nil }
    private var goal: Binding<Goal> { Binding(get: { habit.goals[habit.goals.count - 1] }, set: { habit.goals[habit.goals.count - 1] = $0 }) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Button { icons=true } label: { IconHero(habit:habit) }.buttonStyle(.plain).accessibilityLabel("Choose Icon")
                    field("NAME") { TextField("Habit name", text: $habit.name).font(.system(size:14)).textInputAutocapitalization(.sentences).padding(14).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14)) }
                    field("DESCRIPTION") { TextField("What does this habit mean to you?", text: $habit.detail, axis: .vertical).font(.system(size:14)).lineLimit(2...4).padding(14).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14)) }
                    field("COLOR") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                            ForEach(BuddyStyle.colors, id: \.0) { token, _ in
                                Button { habit.color = token } label: {
                                    RoundedRectangle(cornerRadius: 10).fill(BuddyStyle.color(token)).frame(height: 36)
                                        .overlay { if habit.color == token { RoundedRectangle(cornerRadius: 10).stroke(Color.primary, lineWidth: 2).padding(-3) } }
                                }.buttonStyle(.plain).accessibilityLabel(token).accessibilityAddTraits(habit.color == token ? .isSelected : [])
                            }
                        }
                    }
                    field("HABIT TYPE") {
                        SegmentedChoice(selection:goal.mode,options:[(.build,"Build a habit"),(.quit,"Quit a habit")])
                        Text(habit.currentGoal.mode == .quit ? "Clean days fill automatically. Log the days you slip." : "Mark each day you make progress.").font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Advanced Options") {
                        VStack(alignment:.leading,spacing:20) {
                    field("TRACKING") {
                        Picker("Tracking", selection: goal.tracking) { Text("Yes / No").tag(Tracking.yesNo); Text("Count").tag(Tracking.count); Text("Measure").tag(Tracking.measure) }.pickerStyle(.segmented)
                        if habit.currentGoal.tracking != .yesNo {
                            HStack {
                                Text(habit.currentGoal.mode == .quit ? "Stay below" : "Daily target")
                                Spacer(); TextField("Target", text: $target).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                            }.padding(.vertical, 8)
                            if habit.currentGoal.tracking == .measure { TextField("Unit (minutes, km, liters…)", text: goal.unit).textFieldStyle(.roundedBorder) }
                            Picker("On tap", selection: goal.tap) { Text("Add 1").tag(TapAction.addOne); Text("Enter total").tag(TapAction.enterTotal) }.pickerStyle(.segmented)
                        }
                    }
                    if habit.currentGoal.mode == .build {
                        field("STREAK GOAL") {
                            Picker("Schedule", selection: goal.cadence) { ForEach(Cadence.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.pickerStyle(.segmented)
                            if habit.currentGoal.cadence == .weekly || habit.currentGoal.cadence == .monthly {
                                Stepper("\(habit.currentGoal.days) successful days", value: goal.days, in: 1...(habit.currentGoal.cadence == .weekly ? 7 : 31))
                            }
                        }
                    }
                    if !store.data.categories.isEmpty {
                        field("CATEGORIES") {
                            ForEach(store.data.categories) { category in
                                Toggle(category.name, isOn: Binding(get: { habit.categories.contains(category.id) }, set: { included in habit.categories.removeAll { $0 == category.id }; if included { habit.categories.append(category.id) } }))
                            }
                        }
                    }
                    Button { reminders = true } label: { HStack { Label("Reminders", systemImage: "bell"); Spacer(); Text("\(habit.reminders.count)").foregroundStyle(.secondary); Image(systemName: "chevron.right") } }.surface()
                        }.padding(.top,16)
                    }.font(.system(size:13)).foregroundStyle(.secondary)
                    if existing { Text("Goal changes take effect today. Earlier days keep their original rules. Changing mode or tracking resets today's amount and preserves its note.").font(.caption).foregroundStyle(.secondary) }
                    if let text = validation ?? store.error { Text(text).font(.caption).foregroundStyle(.red).accessibilityIdentifier("editor-error") }
                }.padding(20)
            }
            .background(BuddyStyle.canvas(scheme))
            .toolbar(.hidden,for:.navigationBar)
            .safeAreaInset(edge:.top){SheetHeader(title:existing ? "Edit Habit":"New Habit").background(BuddyStyle.canvas(scheme))}
            .safeAreaInset(edge:.bottom){PrimaryAction(title:"Save",action:save).padding(.horizontal,24).padding(.vertical,12).background(BuddyStyle.canvas(scheme))}
            .sheet(isPresented:$icons){IconPickerView(selection:$habit.symbol,color:BuddyStyle.color(habit.color))}
            .sheet(isPresented: $reminders) { ReminderEditorView(reminders: $habit.reminders) }
            .onAppear { target = Amount.text(habit.currentGoal.target) }
            .onChange(of: habit.currentGoal.cadence) { _, new in if new == .daily || new == .none { goal.wrappedValue.days = 1 } else if new == .weekly { goal.wrappedValue.days = min(7, habit.currentGoal.days) } }
        }
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(title).font(.system(size:10,weight:.medium)).foregroundStyle(.secondary); content() }
    }
    private func save() {
        do {
            var rule = habit.currentGoal
            rule.target = rule.tracking == .yesNo ? 1_000 : try Amount.parse(target)
            if rule.mode == .quit { rule.cadence = .daily; rule.days = 1 }
            if rule.cadence == .none || rule.cadence == .daily { rule.days = 1 }
            habit.name = habit.name.trimmingCharacters(in: .whitespacesAndNewlines)
            habit.goals[habit.goals.count - 1] = rule
            if store.change({ try Engine.saveHabit(habit, data: &$0) }) { dismiss() } else { validation=store.error; store.error=nil }
        } catch { validation = error.localizedDescription }
    }
}

struct SegmentedChoice<Value:Hashable>: View {
    @Binding var selection:Value
    let options:[(Value,String)]
    var body:some View {
        HStack(spacing:4){ForEach(options.indices,id:\.self){i in Button{selection=options[i].0}label:{Text(options[i].1).font(.system(size:12,weight:.semibold)).foregroundStyle(selection==options[i].0 ? .primary:.secondary).frame(maxWidth:.infinity,minHeight:36).background(selection==options[i].0 ? Color.primary.opacity(0.075):.clear,in:RoundedRectangle(cornerRadius:11))}.buttonStyle(.plain).accessibilityAddTraits(selection==options[i].0 ? .isSelected:[])}}
            .padding(4).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:14)).overlay{RoundedRectangle(cornerRadius:14).stroke(Color.primary.opacity(0.06),lineWidth:1)}
    }
}
struct IconHero: View {
    let habit:Habit
    private var cloud:[HabitIconEntry]{Array(BuddyIcons.all.filter{["wallet","leaf","moon","globe","utensils","bicycle","guitar","book","mug-saucer","carrot","dumbbell","pen-nib","camera","dog","brain","heart","spa","fish","stethoscope","flask"].contains(String($0.id.dropFirst(3)))}.prefix(40))}
    var body:some View {
        ZStack {
            LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:10),spacing:18){ForEach(0..<40,id:\.self){i in if !cloud.isEmpty{BuddyGlyph(symbol:cloud[i%cloud.count].id,size:16,outline:true).rotationEffect(.degrees(Double((i*7)%30)-15))}}.foregroundStyle(BuddyStyle.color(habit.color).opacity(0.2))
            HabitIcon(habit:habit,size:88,circular:true)
        }.frame(height:140)
    }
}
struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Binding var selection:String
    let color:Color
    @State private var query=""
    @State private var emojiMode=false
    @State private var customEmoji=""
    private let emojis=["💪","🏃","📖","💧","🚶","🌙","☀️","✍️","💻","☕️","🥗","🧠","🎸","🎵","🎨","🔥","⚡️","🛏️","🧘","💊","🥕","🚴","💰","📵","🚭","🎮","📷","🐶","🏡","⭐️","🌍","🌊","🍎","🏋️","📝","🎯","🦷","❤️","🌿","🛁","🧹","🧺","🎾","🏊","🎓","🧑‍🍳","🫶","🌱"]
    var body:some View {
        VStack(spacing:16) {
            SheetHeader(title:"Choose Icon")
            SegmentedChoice(selection:$emojiMode,options:[(false,"Icons"),(true,"Emoji")])
            TextField("Search icons or emoji",text:$query).textInputAutocapitalization(.never).autocorrectionDisabled().padding(12).background(Color.primary.opacity(0.06),in:RoundedRectangle(cornerRadius:13))
            if emojiMode {
                HStack{TextField("Enter any emoji",text:$customEmoji);Button("Use"){useEmoji()}.disabled(customEmoji.isEmpty)}
            }
            ScrollView {
                LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:7),spacing:8) {
                    if emojiMode { ForEach(emojis.filter{query.isEmpty || $0.contains(query)},id:\.self){e in Button{selection=e;dismiss()}label:{Text(e).font(.system(size:22)).frame(maxWidth:.infinity,minHeight:44)}.buttonStyle(.plain).accessibilityLabel(e)} }
                    else { ForEach(BuddyIcons.search(query)){icon in Button{selection=icon.id;dismiss()}label:{BuddyGlyph(symbol:icon.id,size:22,outline:true).foregroundStyle(color).frame(maxWidth:.infinity,minHeight:44).background(selection==icon.id ? color.opacity(0.14):.clear,in:RoundedRectangle(cornerRadius:10))}.buttonStyle(.plain).accessibilityLabel(icon.name)} }
                }
            }
        }.padding(.horizontal,20).background(BuddyStyle.canvas(scheme))
    }
    private func useEmoji(){if let c=customEmoji.first,c.unicodeScalars.contains(where:{$0.properties.isEmojiPresentation}) || String(c).contains("\u{FE0F}"){selection=String(c);dismiss()}}
}

struct ReminderEditorView: View {
    @Binding var reminders:[Reminder]
    @Environment(\.colorScheme) private var scheme
    @State private var needsPermission=true
    @State private var denied=false
    @State private var message:String?
    @State private var editing:UUID?
    var body:some View {
        VStack(spacing:0) {
            SheetHeader(title:"Reminder (\(reminders.count) / 3)")
            ScrollView {
                VStack(spacing:20) {
                    if needsPermission {
                        VStack(spacing:12){Image(systemName:"bell.badge").font(.system(size:25)).foregroundStyle(BuddyStyle.purple);Text("Allow notifications").font(.system(size:16,weight:.semibold));Text("Get a reminder when it is time for your habit.").font(.system(size:12)).foregroundStyle(.secondary)
                            if denied{Link("Open System Settings",destination:URL(string:UIApplication.openSettingsURLString)!)}else{Button("Give permission"){Task{do{denied=try await !NotificationService.request();needsPermission=denied}catch{message=error.localizedDescription}}}}
                        }.frame(maxWidth:.infinity).surface()
                    }
                    ForEach($reminders){$r in
                        VStack(alignment:.leading,spacing:12) {
                            Text("Reminder #\((reminders.firstIndex(where:{$0.id==r.id}) ?? 0)+1)").font(.system(size:13,weight:.medium))
                            WeekdayPicker(days:$r.weekdays)
                            HStack {
                                Button{editing=r.id}label:{HStack{Image(systemName:"clock");Text(String(format:"%02d:%02d",r.hour,r.minute)).monospacedDigit();Spacer()}.frame(height:48)}.buttonStyle(.plain)
                                Button(role:.destructive){reminders.removeAll{$0.id==r.id}}label:{Image(systemName:"trash").frame(width:48,height:48)}.buttonStyle(.plain).accessibilityLabel("Remove Reminder")
                            }.surface(padding:0,radius:13)
                            Toggle("Enabled",isOn:$r.enabled).font(.system(size:12))
                        }
                    }
                    if let message{Text(message).foregroundStyle(.red)}
                }.padding(20)
            }
            if reminders.count<3{PrimaryAction(title:"Add Reminder",symbol:"plus"){reminders.append(Reminder())}.padding(24)}
        }.background(BuddyStyle.canvas(scheme))
        .sheet(isPresented:Binding(get:{editing != nil},set:{if !$0{editing=nil}})) {
            if let i=reminders.firstIndex(where:{$0.id==editing}) { ReminderTimePicker(reminder:$reminders[i]) }
        }
        .task { let settings=await UNUserNotificationCenter.current().notificationSettings();denied=settings.authorizationStatus == .denied;needsPermission=settings.authorizationStatus != .authorized && settings.authorizationStatus != .provisional }
    }
}
struct ReminderTimePicker: View {
    @Binding var reminder:Reminder
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        VStack{DatePicker("Time",selection:Binding(get:{Calendar.current.date(from:DateComponents(hour:reminder.hour,minute:reminder.minute)) ?? Date()},set:{reminder.hour=Calendar.current.component(.hour,from:$0);reminder.minute=Calendar.current.component(.minute,from:$0)}),displayedComponents:.hourAndMinute).datePickerStyle(.wheel);Button("Done"){dismiss()}}.padding(20).presentationDetents([.medium])
    }
}
struct WeekdayPicker: View {
    @Binding var days:[Int]
    var body:some View {
        HStack(spacing:4){ForEach(0..<7,id:\.self){index in let day=(index+1)%7+1
            Button{if days.contains(day){if days.count>1{days.removeAll{$0==day}}}else{days.append(day)}}label:{Text(String(Calendar.current.shortWeekdaySymbols[day-1].prefix(3))).font(.system(size:10,weight:.medium,design:.monospaced)).frame(maxWidth:.infinity,minHeight:39).background(days.contains(day) ? BuddyStyle.purple:Color.secondary.opacity(0.12),in:RoundedRectangle(cornerRadius:11)).foregroundStyle(days.contains(day) ? Color.white:.primary)}.buttonStyle(.plain).accessibilityLabel(Calendar.current.weekdaySymbols[day-1]).accessibilityAddTraits(days.contains(day) ? .isSelected:[])
        }}
    }
}
