import SwiftUI
import CoreText

enum BuddyStyle {
    static let purple = Color(hex:0x8F84F7)
    static let colors: [(String,UInt32)] = [
        ("coral",0xF87171),("orange",0xFB923C),("amber",0xFBBF24),("yellow",0xFACC15),
        ("lime",0xA3E635),("green",0x4ADE80),("mint",0x34D399),("teal",0x2DD4BF),
        ("cyan",0x22D3EE),("sky",0x38BDF8),("blue",0x60A5FA),("indigo",0x818CF8),
        ("lavender",0xA78BFA),("violet",0xC084FC),("magenta",0xE879F9),("pink",0xF472B6),
        ("rose",0xFB7185),("slate",0x94A3B8),("steel",0x9CA3AF),("gray",0xA3A3A3),("stone",0xA8A29E)]
    static var symbols: [String] { BuddyIcons.all.map(\.id) }
    static func color(_ token:String)->Color { Color(hex:colors.first{$0.0==token}?.1 ?? 0x34D399) }
    static func canvas(_ s:ColorScheme)->Color { Color(hex:s == .dark ? 0x101012:0xFAFAFC) }
    static func surface(_ s:ColorScheme)->Color { Color(hex:s == .dark ? 0x1B1B1D:0xFFFFFF) }
    static func border(_ s:ColorScheme)->Color { (s == .dark ? Color.white:.black).opacity(s == .dark ? 0.065:0.075) }
}
extension Color { init(hex:UInt32) { self.init(red:Double((hex>>16)&255)/255,green:Double((hex>>8)&255)/255,blue:Double(hex&255)/255) } }
struct Surface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var padding:CGFloat=14
    var radius:CGFloat=20
    var tint:Color = .clear
    func body(content:Content)->some View {
        content.padding(padding).background {
            RoundedRectangle(cornerRadius:radius).fill(BuddyStyle.surface(scheme))
                .overlay { RoundedRectangle(cornerRadius:radius).fill(LinearGradient(colors:[tint.opacity(0.075),.clear],startPoint:.top,endPoint:.bottom)) }
        }.overlay { RoundedRectangle(cornerRadius:radius).stroke(BuddyStyle.border(scheme),lineWidth:1) }
    }
}
extension View { func surface(padding:CGFloat=14,radius:CGFloat=20,tint:Color = .clear)->some View { modifier(Surface(padding:padding,radius:radius,tint:tint)) } }
struct HabitIconEntry: Decodable, Identifiable {
    let id:String
    let name:String
    let unicode:String
    let regular:Bool
    let keywords:[String]
    var glyph:String { UInt32(unicode,radix:16).flatMap(UnicodeScalar.init).map(String.init) ?? "" }
}
enum BuddyIcons {
    static let registered:Void = {
        for name in ["FontAwesome-Solid","FontAwesome-Regular"] {
            if let url=Bundle.main.url(forResource:name,withExtension:"otf") { CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil) }
        }
    }()
    static let all:[HabitIconEntry] = {
        _ = registered
        guard let url=Bundle.main.url(forResource:"habit-icons",withExtension:"json"),let bytes=try? Data(contentsOf:url),let icons=try? JSONDecoder().decode([HabitIconEntry].self,from:bytes) else { return [] }
        return icons
    }()
    static let byID=Dictionary(uniqueKeysWithValues:all.map{($0.id,$0)})
    static let aliases=["leaf.fill":"leaf","heart.fill":"heart-circle-bolt","dumbbell.fill":"dumbbell","book.closed.fill":"book","drop.fill":"glass-water","figure.walk":"person-walking","moon.fill":"moon","sun.max.fill":"sun","pencil.tip":"pen-nib","laptopcomputer":"laptop","cup.and.saucer.fill":"mug-saucer","fork.knife":"utensils","brain.head.profile":"brain","guitars.fill":"guitar","music.note":"music","paintbrush.fill":"paintbrush","flame.fill":"fire","bolt.fill":"bolt","bed.double.fill":"bed","figure.mind.and.body":"spa","cross.case.fill":"kit-medical","pill.fill":"pills","carrot.fill":"carrot","bicycle":"bicycle","figure.run":"person-running","code":"code","wallet.pass.fill":"wallet","phone.down.fill":"phone-slash","nosign":"ban","smoke.fill":"smoking","gamecontroller.fill":"gamepad","camera.fill":"camera","dog.fill":"dog","house.fill":"house","star.fill":"star","globe":"globe","water.waves":"water"]
    static func entry(_ symbol:String)->HabitIconEntry? { byID[symbol] ?? aliases[symbol].flatMap{byID["fa:"+$0]} }
    static func search(_ text:String)->[HabitIconEntry] { text.isEmpty ? all:all.filter{([$0.id,$0.name]+$0.keywords).joined(separator:" ").localizedCaseInsensitiveContains(text)} }
}
struct BuddyGlyph: View {
    let symbol:String
    var size:CGFloat=18
    var outline=false
    var body:some View {
        Group {
            if let entry=BuddyIcons.entry(symbol) { Text(entry.glyph).font(.custom(outline && entry.regular ? "FontAwesome7Free-Regular":"FontAwesome7Free-Solid",size:size)) }
            else if symbol.unicodeScalars.contains(where:{$0.properties.isEmojiPresentation}) || symbol.contains("\u{FE0F}") { Text(symbol).font(.system(size:size)) }
            else { Image(systemName:symbol.hasPrefix("fa:") ? "questionmark":symbol).font(.system(size:size)) }
        }.accessibilityHidden(true)
    }
}
struct HabitIcon: View {
    let habit:Habit
    var size:CGFloat=38
    var circular=false
    var body:some View { BuddyGlyph(symbol:habit.symbol,size:size*0.48).foregroundStyle(BuddyStyle.color(habit.color)).frame(width:size,height:size).background(BuddyStyle.color(habit.color).opacity(0.13),in:RoundedRectangle(cornerRadius:circular ? size/2:size*0.28)).accessibilityHidden(true) }
}
struct MetricChip: View {
    var symbol:String
    var text:String
    var color:Color
    var body:some View { HStack(spacing:5){Image(systemName:symbol).font(.system(size:10));Text(text).font(.system(size:11,weight:.medium,design:.monospaced))}.padding(.horizontal,9).padding(.vertical,5).foregroundStyle(color).background(color.opacity(0.12),in:Capsule()) }
}
struct CircleControl: View {
    @Environment(\.colorScheme) private var scheme
    let symbol:String
    let label:String
    var filled=false
    var action:()->Void
    var body:some View { Button(action:action){Image(systemName:symbol).font(.system(size:16,weight:.medium)).frame(width:34,height:34).background(filled ? BuddyStyle.purple:BuddyStyle.surface(scheme),in:Circle()).overlay{if !filled {Circle().stroke(BuddyStyle.border(scheme),lineWidth:1)}}.foregroundStyle(filled ? Color.white:Color.primary).padding(5)}.buttonStyle(.plain).accessibilityLabel(label) }
}
struct SheetHeader: View {
    @Environment(\.dismiss) private var dismiss
    let title:String
    var trailingSymbol:String?
    var trailingAction:(()->Void)?
    var body:some View { HStack{CircleControl(symbol:"xmark",label:"Close \(title)"){dismiss()};Spacer();Text(title).font(.system(size:18,weight:.semibold));Spacer();if let trailingSymbol,let trailingAction {CircleControl(symbol:trailingSymbol,label:title,filled:true,action:trailingAction)}else{Color.clear.frame(width:44,height:44)}}.padding(.horizontal,12).padding(.top,8) }
}
struct PrimaryAction: View {
    let title:String
    var symbol:String?
    var action:()->Void
    var body:some View { Button(action:action){HStack{if let symbol{Image(systemName:symbol)};Text(title)}.font(.system(size:16,weight:.semibold)).frame(maxWidth:.infinity,minHeight:48)}.buttonStyle(.plain).foregroundStyle(.white).background(BuddyStyle.purple,in:Capsule()) }
}
struct ColorPalette: View {
    @Binding var selection:String
    var body:some View { LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:7),spacing:8){ForEach(BuddyStyle.colors,id:\.0){token,_ in Button{selection=token}label:{RoundedRectangle(cornerRadius:10).fill(BuddyStyle.color(token)).aspectRatio(1,contentMode:.fit).overlay{if selection==token{RoundedRectangle(cornerRadius:13).stroke(BuddyStyle.color(token),lineWidth:2).padding(-3)}}}.buttonStyle(.plain).accessibilityLabel(token).accessibilityAddTraits(selection==token ? .isSelected:[])}} }
}
struct CompletionBadge: View {
    let habit:Habit
    let data:BuddyData
    var day=Day()
    var size:CGFloat=40
    var body:some View {
        let p=Engine.progress(habit,day:day,data:data),g=habit.goal(on:day),color=BuddyStyle.color(habit.color)
        ZStack {
            if g.tracking == .yesNo { RoundedRectangle(cornerRadius:size*0.3).fill(color.opacity(p.success ? 1:0.13)) }
            else if g.tracking == .count && g.target <= 12_000 {
                let count=max(1,Int(g.target/1_000))
                ForEach(0..<count,id:\.self){n in Circle().trim(from:CGFloat(n)/CGFloat(count)+0.017,to:CGFloat(n+1)/CGFloat(count)-0.017).stroke(color.opacity(Int(p.amount/1_000)>n ? 1:0.18),style:StrokeStyle(lineWidth:2,lineCap:.round)).rotationEffect(.degrees(-90)) }
            } else { Circle().stroke(color.opacity(0.16),lineWidth:2);Circle().trim(from:0,to:p.fraction).stroke(color,style:StrokeStyle(lineWidth:2,lineCap:.round)).rotationEffect(.degrees(-90)) }
            Image(systemName:p.slip ? "xmark":p.success || g.tracking == .yesNo ? "checkmark":"plus").font(.system(size:size*0.42,weight:.medium)).foregroundStyle(p.success && g.tracking == .yesNo ? Color.black.opacity(0.7):color.opacity(g.tracking == .yesNo ? 0.5:1))
        }.frame(width:size,height:size)
    }
}
extension Goal {
    var summary:String {
        if mode == .quit{return tracking == .yesNo ? "Daily":"Below \(Amount.text(target)) \(unit)"}
        switch cadence {case .none:return "No Streak Goal";case .daily:return "Daily";case .weekly:return "\(days) / Week";case .monthly:return "\(days) / Month"}
    }
}
extension Habit {
    func cardAppearance(_ s:Settings)->CardAppearance {
        if let appearance{return appearance}
        var a=CardAppearance();a.description=s.showDescriptions;a.streak=s.showStreak;a.goal=s.showGoal;a.indicator=s.showCompletionIndicator;a.monthLabels=s.showMonthLabels;a.weekdayLabels=s.showWeekdayLabels;a.categoryIcons=s.showCategoryIcons;return a
    }
}
