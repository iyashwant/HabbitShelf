import SwiftUI
import UserNotifications

struct HabitEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var habit: Habit
    @State private var target = "1"
    @State private var emoji = ""
    @State private var symbolSearch = ""
    @State private var icons = false
    @State private var reminders = false
    @State private var validation: String?
    /// Icons matched to the name. While `autoIcon` holds, the first one becomes the habit's icon;
    /// choosing an icon (here or in the picker) ends it. `autoBase` is restored when nothing matches.
    @State private var suggestedIcons: [String] = []
    @State private var autoIcon = false
    @State private var autoBase = ""
    private var existing: Bool { store.habit(habit.id) != nil }
    private var goal: Binding<Goal> { Binding(get: { habit.goals[habit.goals.count - 1] }, set: { habit.goals[habit.goals.count - 1] = $0 }) }
    var body: some View {
        let named = !habit.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button { icons=true } label: { IconHero(habit:habit) }.buttonStyle(.plain).accessibilityLabel("Choose Icon").accessibilityValue(BuddyIcons.entry(habit.symbol)?.name ?? "").padding(.top, 13.8)
                    field("Name", inset: 5, gap: 6.7) {
                        TextField("", text: $habit.name).textInputAutocapitalization(.sentences).accessibilityLabel("Habit name").buddyField()
                        if !suggestedIcons.isEmpty {
                            IconSuggestions(icons: suggestedIcons, selection: habit.symbol, color: BuddyStyle.color(habit.color)) { id in autoIcon = false; withAnimation(motion) { habit.symbol = id } }
                                .padding(.top, 3).transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }.padding(.top, 16.7)
                    field("Description", inset: 5, gap: 6.7) { TextField("", text: $habit.detail, axis: .vertical).lineLimit(1...4).accessibilityLabel("Description").buddyField() }.padding(.top, 10.5)
                    field("Color", inset: 5) { ColorPalette(selection: $habit.color) }.padding(.top, 13.8)
                    field("Habit Type", inset: 0, gap: 7) {
                        SegmentedChoice(selection:goal.mode,options:[(.build,"Build A Habit"),(.quit,"Quit A Habit")])
                        Text(habit.currentGoal.mode == .quit ? "Clean days fill automatically. Log the days you slip." : "Mark each day you complete it.").font(BuddyFont.text(12.8)).foregroundStyle(BuddyStyle.tertiaryText(scheme)).frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, -2.6)
                    }.padding(.top, 21.5)
                    field("Tracking", inset: 0, gap: 7) {
                        SegmentedChoice(selection: goal.tracking, options: [(.yesNo, "Yes / No"), (.count, "Count"), (.measure, "Measure")])
                        if habit.currentGoal.tracking != .yesNo {
                            HStack {
                                Text(habit.currentGoal.mode == .quit ? "Stay below" : "Daily target").font(BuddyFont.text(15))
                                Spacer(); TextField("Target", text: $target).keyboardType(.decimalPad).multilineTextAlignment(.trailing).font(BuddyFont.mono(15)).frame(width: 90)
                            }.padding(.horizontal, 16).frame(height: 52).background(BuddyStyle.field(scheme), in: RoundedRectangle(cornerRadius: 15, style: .circular)).overlay { RoundedRectangle(cornerRadius: 15, style: .circular).strokeBorder(BuddyStyle.border(scheme, 0.1), lineWidth: 1) }
                            if habit.currentGoal.tracking == .measure { TextField("Unit (minutes, km, liters…)", text: goal.unit).buddyField() }
                            SegmentedChoice(selection: goal.tap, options: [(.addOne, "Tap Adds 1"), (.enterTotal, "Tap Enters Total")])
                        }
                    }.padding(.top, 21.5)
                    if habit.currentGoal.mode == .build {
                        field("Streak Goal", inset: 0, gap: 7) {
                            SegmentedChoice(selection: goal.cadence, options: Cadence.allCases.map { ($0, $0 == .none ? "None" : $0.rawValue.capitalized) })
                            if habit.currentGoal.cadence == .weekly || habit.currentGoal.cadence == .monthly {
                                Stepper("\(habit.currentGoal.days) successful days", value: goal.days, in: 1...(habit.currentGoal.cadence == .weekly ? 7 : 31)).font(BuddyFont.text(15)).padding(.horizontal, 16).frame(height: 52).background(BuddyStyle.field(scheme), in: RoundedRectangle(cornerRadius: 15, style: .circular))
                            }
                        }.padding(.top, 21.5)
                    }
                    if !store.data.categories.isEmpty {
                        field("Categories", inset: 0) {
                            VStack(spacing: 0) {
                                ForEach(store.data.categories) { category in
                                    Toggle(isOn: Binding(get: { habit.categories.contains(category.id) }, set: { included in habit.categories.removeAll { $0 == category.id }; if included { habit.categories.append(category.id) } })) { HStack(spacing: 10) { BuddyGlyph(symbol: category.symbol, size: 16); Text(category.name).font(BuddyFont.text(15)) } }
                                        .tint(accent.color).padding(.horizontal, 16).frame(height: 52)
                                }
                            }.panel(radius: 15, border: 0.1)
                        }.padding(.top, 21.5)
                    }
                    Button { reminders = true } label: {
                        HStack(spacing: 10) { LucideIcon("bell", size: 18); Text("Reminders").font(BuddyFont.text(15)); Spacer(); Text("\(habit.reminders.count)").font(BuddyFont.mono(13)).foregroundStyle(BuddyStyle.secondaryText(scheme)); LucideIcon("chevron-right", size: 15).foregroundStyle(BuddyStyle.secondaryText(scheme)) }
                            .foregroundStyle(BuddyStyle.text(scheme)).padding(.horizontal, 16).frame(height: 52).contentShape(Rectangle())
                    }.buttonStyle(.plain).panel(radius: 15, border: 0.1).padding(.top, 21.5)
                    if existing { Text("Goal changes take effect today. Earlier days keep their original rules. Changing mode or tracking resets today's amount and preserves its note.").font(BuddyFont.text(12)).foregroundStyle(BuddyStyle.tertiaryText(scheme)).padding(.top, 14) }
                    if let text = validation ?? store.error { Text(text).font(BuddyFont.text(12)).foregroundStyle(.red).accessibilityIdentifier("editor-error").padding(.top, 10) }
                }.padding(.horizontal, 16).padding(.bottom, 110)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(BuddyStyle.canvas(scheme))
            .toolbar(.hidden,for:.navigationBar)
            .topBar(backdrop:0){SheetHeader(title:existing ? "Edit Habit":"New Habit")}
            .overlay(alignment: .bottom) {
                PrimaryAction(title:"Save",action:save).disabled(!named).padding(.horizontal,24).padding(.bottom,6)
                    .background(alignment: .bottom) { LinearGradient(colors: [BuddyStyle.canvas(scheme).opacity(0), BuddyStyle.canvas(scheme).opacity(0.85)], startPoint: .top, endPoint: .bottom).frame(height: 120).ignoresSafeArea().allowsHitTesting(false) }
            }
            .sheet(isPresented:$icons){IconPickerView(selection:Binding(get:{habit.symbol},set:{habit.symbol=$0;autoIcon=false}),color:BuddyStyle.color(habit.color)).buddySheet()}
            .sheet(isPresented: $reminders) { ReminderEditorView(reminders: $habit.reminders).buddySheet() }
            .onAppear { target = Amount.text(habit.currentGoal.target); startIconSuggestions() }
            .task(id: habit.name) { try? await Task.sleep(for: .milliseconds(250)); if !Task.isCancelled { refreshIcons() } }
            .onChange(of: habit.currentGoal.mode) { refreshIcons() }
            .onChange(of: habit.currentGoal.cadence) { _, new in if new == .daily || new == .none { goal.wrappedValue.days = 1 } else if new == .weekly { goal.wrappedValue.days = min(7, habit.currentGoal.days) } }
        }
    }
    private var motion: Animation? { reduceMotion ? nil : .snappy(duration: 0.25) }
    /// New habits, and habits still on the default or on the icon their name suggests, follow the name.
    private func startIconSuggestions() {
        let quit = habit.currentGoal.mode == .quit
        autoBase = habit.symbol
        autoIcon = !existing || habit.symbol == Habit.draft().symbol || habit.symbol == Habit(name: "").symbol || BuddyIcons.suggester.suggest(habit.name, quit: quit, limit: 1).first == habit.symbol
        suggestedIcons = BuddyIcons.suggester.suggest(habit.name, quit: quit)
    }
    private func refreshIcons() {
        let icons = BuddyIcons.suggester.suggest(habit.name, quit: habit.currentGoal.mode == .quit)
        let symbol = autoIcon ? icons.first ?? autoBase : habit.symbol
        guard icons != suggestedIcons || symbol != habit.symbol else { return }
        withAnimation(motion) { suggestedIcons = icons; if symbol != habit.symbol { habit.symbol = symbol } }
    }
    private func field<Content: View>(_ title: String, inset: CGFloat, gap: CGFloat = 8, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: gap) { Text(title).fieldCaption().foregroundStyle(BuddyStyle.secondaryText(scheme)).padding(.leading, inset); content() }
    }
    private func save() {
        refreshIcons()
        do {
            var rule = habit.currentGoal
            rule.target = rule.tracking == .yesNo ? 1_000 : try Amount.parse(target)
            if rule.mode == .quit { rule.cadence = .daily; rule.days = 1 }
            if rule.cadence == .none || rule.cadence == .daily { rule.days = 1 }
            habit.name = habit.name.trimmingCharacters(in: .whitespacesAndNewlines)
            habit.goals[habit.goals.count - 1] = rule
            let saved = habit
            if store.change({ try Engine.saveHabit(saved, data: &$0) }) { dismiss() } else { validation=store.error; store.error=nil }
        } catch { validation = error.localizedDescription }
    }
}

struct SegmentedChoice<Value:Hashable>: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var selection:Value
    let options:[(Value,String)]
    var body:some View {
        HStack(spacing:0){ForEach(options.indices,id:\.self){i in
            let on=selection==options[i].0
            Button{selection=options[i].0}label:{
                Text(options[i].1).font(BuddyFont.text(14,.medium)).tracking(0.28).lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(on ? BuddyStyle.text(scheme):Color(hex:scheme == .dark ? 0x8B8B94:0x77777E))
                    .frame(maxWidth:.infinity,minHeight:40).background(on ? (scheme == .dark ? Color(hex:0x2B2B31):Color.black.opacity(0.07)):.clear,in:RoundedRectangle(cornerRadius:10.5,style:.circular)).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected:[])}}
            .padding(5).background(scheme == .dark ? Color(hex:0x171719):BuddyStyle.field(scheme),in:RoundedRectangle(cornerRadius:15,style:.circular)).overlay{RoundedRectangle(cornerRadius:15,style:.circular).strokeBorder(BuddyStyle.border(scheme,0.1),lineWidth:1)}
    }
}
/// The faint icon cloud around the selected icon, laid out like the reference editor.
struct IconHero: View {
    @Environment(\.colorScheme) private var scheme
    let habit:Habit
    private static let rows:[(CGFloat,[(CGFloat,String)])] = [
        (-55.5,[(40,"wallet"),(68,"fan"),(103,"cloud-moon"),(133,"cookie"),(163,"camera"),(196,"tag"),(226,"badge-dollar-sign"),(262,"send"),(292,"cup-soda"),(319,"popcorn"),(358,"carrot")]),
        (-18,[(40,"coffee"),(68,"notebook-text"),(104,"ship"),(134,"volleyball"),(260,"salad"),(290,"soup"),(321,"clapperboard"),(353,"wrench")]),
        (20,[(39,"image"),(67,"trash"),(100,"mountain-snow"),(135,"cookie"),(260,"chef-hat"),(292,"cake-slice"),(321,"notebook-pen"),(349,"flame-kindling")]),
        (56,[(38,"apple"),(72,"crown"),(104,"bike"),(132,"braces"),(169,"stethoscope"),(195,"trophy"),(227,"target"),(258,"gem"),(288,"utensils"),(322,"pill"),(353,"utensils-crossed")])]
    var body:some View {
        let c=BuddyStyle.color(habit.color)
        GeometryReader { proxy in
            let scale=proxy.size.width/361,mid=proxy.size.height/2
            ZStack {
                ForEach(Self.rows.indices,id:\.self){r in
                    ForEach(Self.rows[r].1,id:\.1){x,name in LucideIcon(name,size:20).position(x:(x-16)*scale,y:mid+Self.rows[r].0)}
                }.foregroundStyle(c.opacity(0.25))
                ZStack { BuddyGlyph(symbol:habit.symbol,size:46).id(habit.symbol).transition(.scale(scale:0.6).combined(with:.opacity)) }.foregroundStyle(c).frame(width:96,height:96)
                    .background(Circle().fill(c.opacity(0.14)).background(Circle().fill(BuddyStyle.canvas(scheme)))).position(x:proxy.size.width/2,y:mid)
            }
        }.frame(height:140)
    }
}
/// Icons matched to the habit name as it is typed; the selected one is outlined in the habit color.
struct IconSuggestions: View {
    @Environment(\.colorScheme) private var scheme
    let icons:[String]
    let selection:String
    let color:Color
    let pick:(String)->Void
    var body:some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:8) {
                LucideIcon("sparkles",size:15).foregroundStyle(BuddyStyle.tertiaryText(scheme)).frame(width:22)
                ForEach(icons,id:\.self) { id in
                    let on=id==selection,shape=RoundedRectangle(cornerRadius:12,style:.circular)
                    Button { pick(id) } label: {
                        BuddyGlyph(symbol:id,size:19).foregroundStyle(color).frame(width:42,height:42)
                            .background(on ? color.opacity(0.14):BuddyStyle.field(scheme),in:shape)
                            .overlay { shape.strokeBorder(on ? color.opacity(0.6):BuddyStyle.border(scheme,0.1),lineWidth:1) }
                            .contentShape(shape)
                    }.buttonStyle(FlatButtonStyle()).transition(.scale(scale:0.8).combined(with:.opacity))
                        .accessibilityLabel("Use \(BuddyIcons.entry(id)?.name ?? "Suggested") Icon").accessibilityAddTraits(on ? .isSelected:[])
                }
            }.padding(.horizontal,5).padding(.vertical,1)
        }.scrollClipDisabled().accessibilityElement(children:.contain).accessibilityLabel("Suggested Icons")
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
    @Environment(\.accent) private var accent
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
                        VStack(spacing:12){Image(systemName:"bell.badge").font(.system(size:25)).foregroundStyle(accent.color);Text("Allow notifications").font(.system(size:16,weight:.semibold));Text("Get a reminder when it is time for your habit.").font(.system(size:12)).foregroundStyle(.secondary)
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
    @Environment(\.accent) private var accent
    @Binding var days:[Int]
    var body:some View {
        HStack(spacing:4){ForEach(0..<7,id:\.self){index in let day=(index+1)%7+1
            Button{if days.contains(day){if days.count>1{days.removeAll{$0==day}}}else{days.append(day)}}label:{Text(String(Calendar.current.shortWeekdaySymbols[day-1].prefix(3))).font(.system(size:10,weight:.medium,design:.monospaced)).frame(maxWidth:.infinity,minHeight:39).background(days.contains(day) ? accent.color:Color.secondary.opacity(0.12),in:RoundedRectangle(cornerRadius:11)).foregroundStyle(days.contains(day) ? accent.foreground:.primary)}.buttonStyle(.plain).accessibilityLabel(Calendar.current.weekdaySymbols[day-1]).accessibilityAddTraits(days.contains(day) ? .isSelected:[])
        }}
    }
}
