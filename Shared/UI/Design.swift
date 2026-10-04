import SwiftUI
import CoreText

/// Tokens measured from the supplied HabitKit dark-mode screenshots (sRGB, 393-point iPhone).
enum BuddyStyle {
    /// The reference's violet: the default accent.
    static let violet:UInt32 = 0x8B8AF8
    static let colors: [(String,UInt32)] = [
        ("coral",0xF87171),("orange",0xFB923C),("amber",0xFBBF24),("yellow",0xFACC15),
        ("lime",0xA3E635),("green",0x4ADE80),("mint",0x34D399),("teal",0x2DD4BF),
        ("cyan",0x22D3EE),("sky",0x38BDF8),("blue",0x60A5FA),("indigo",0x818CF8),
        ("lavender",0xA78BFA),("violet",0xC084FC),("magenta",0xE879F9),("pink",0xF472B6),
        ("rose",0xFB7185),("slate",0x94A3B8),("steel",0x9CA3AF),("gray",0xA3A3A3),("stone",0xA8A29E)]
    static var symbols: [String] { BuddyIcons.all.map(\.id) }
    static func color(_ token:String)->Color { Color(hex:hex(token) ?? 0x34D399) }
    static func hex(_ token:String)->UInt32? { colors.first{$0.0==token}?.1 }
    static func canvas(_ s:ColorScheme)->Color { Color(hex:s == .dark ? 0x101013:0xF6F6F8) }
    /// Habit cards and the detail history card. Their tops take a faint tint of the habit color.
    static func surface(_ s:ColorScheme)->Color { Color(hex:s == .dark ? 0x1A1A1D:0xFFFFFF) }
    /// Flat panels: compact list, calendar and settings groups.
    static func panel(_ s:ColorScheme)->Color { Color(hex:s == .dark ? 0x161619:0xFFFFFF) }
    /// Text fields, the period pill and segmented tracks.
    static func field(_ s:ColorScheme)->Color { Color(hex:s == .dark ? 0x19191C:0xFFFFFF) }
    static func control(_ s:ColorScheme)->Color { Color(hex:s == .dark ? 0x2B2B30:0xFFFFFF) }
    static func controlBorder(_ s:ColorScheme)->Color { s == .dark ? Color(hex:0x3B3B40):Color.black.opacity(0.09) }
    static func border(_ s:ColorScheme,_ strength:Double = 0.075)->Color { (s == .dark ? Color.white:.black).opacity(s == .dark ? strength:strength*1.1) }
    static func divider(_ s:ColorScheme)->Color { s == .dark ? Color(hex:0x1E1E21):Color.black.opacity(0.06) }
    static func text(_ s:ColorScheme)->Color { Color(hex:s == .dark ? 0xF2F2F4:0x161618) }
    static func secondaryText(_ s:ColorScheme)->Color { Color(hex:s == .dark ? 0x8F8F94:0x6E6E75) }
    static func tertiaryText(_ s:ColorScheme)->Color { Color(hex:s == .dark ? 0x73737C:0x8E8E95) }
    /// Empty tiles inside a habit's tracked range, and tiles outside it (before the start or in the future).
    static let emptyTile = 0.09, inactiveTile = 0.047
    /// Ice blue for streak-frozen days.
    static let freeze = Color(hex:0x7DD3FC)
}
/// The app accent: buttons, switches, selections and multi-habit widgets. Habits keep their own colors.
struct Accent: Equatable, Sendable {
    let hex:UInt32
    /// A saved `Settings.accent`: nil, an unknown name or a malformed code is the default violet.
    init(_ code:String?) { hex=code.flatMap{AccentCode.hex($0) ?? BuddyStyle.hex($0)} ?? BuddyStyle.violet }
    var color:Color { Color(hex:hex) }
    /// Text and glyphs on an accent fill: white like the reference, dark on light accents such as yellow or mint.
    var foreground:Color { luminance > 0.4 ? Color.black.opacity(0.75):.white }
    /// WCAG relative luminance of the sRGB color.
    private var luminance:Double {
        func linear(_ shift:UInt32)->Double { let c=Double((hex>>shift)&255)/255; return c <= 0.04045 ? c/12.92:pow((c+0.055)/1.055,2.4) }
        return 0.2126*linear(16)+0.7152*linear(8)+0.0722*linear(0)
    }
}
extension EnvironmentValues { @Entry var accent=Accent(nil) }
extension Theme {
    /// nil follows the system appearance.
    var colorScheme:ColorScheme? { switch self { case .system:nil; case .light:.light; case .dark:.dark } }
}
/// Liquid Glass on the floating controls (see `GlassSettings`). Absent from the environment, controls keep the flat
/// HabitKit look. Glass stays on the control layer: cards and other content never take it.
struct GlassStyle: Equatable, Sendable {
    /// Clear glass below the middle of the transparency range, regular glass from it.
    let clear:Bool
    /// The control color laid inside the glass: up to 30% toward the middle on the clear side, up to 60% at Frosted.
    let frost:Double
    let tint:Color?
    let accent:Color
    init?(_ settings:GlassSettings?,accent:Accent) {
        guard let settings,settings.enabled else { return nil }
        let t=settings.transparency ?? 0.5
        clear=t<0.5
        frost=t<0.5 ? t/0.5*0.3:(t-0.5)/0.5*0.6
        let strength=settings.tintStrength ?? GlassSettings.defaultTintStrength
        tint=settings.tint.flatMap{$0 == "accent" ? accent.hex:AccentCode.hex($0) ?? BuddyStyle.hex($0)}.map{Color(hex:$0).opacity(strength)}
        self.accent=accent.color
    }
    /// Prominent controls (Create Habit, Save) are regular glass carrying the accent at full strength, as
    /// `glassProminent` is: clear glass turns a tint into a deep, saturated color. Reduce Transparency keeps regular
    /// glass, which iOS frosts.
    func glass(prominent:Bool,reduceTransparency:Bool)->Glass {
        prominent ? Glass.regular.tint(accent).interactive():(clear && !reduceTransparency ? Glass.clear:.regular).tint(tint).interactive()
    }
}
extension EnvironmentValues { @Entry var glass:GlassStyle?=nil }
/// A control's background: the flat fill and hairline, or Liquid Glass in that shape when the mode is on.
struct GlassChrome<S:InsettableShape>: ViewModifier {
    @Environment(\.glass) private var glass
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape:S
    var prominent=false
    let fill:AnyShapeStyle
    var border:AnyShapeStyle?
    func body(content:Content)->some View {
        if let glass {
            content.background { if !prominent && !reduceTransparency && glass.frost>0 { shape.fill(BuddyStyle.control(scheme).opacity(glass.frost)) } }
                .glassEffect(glass.glass(prominent:prominent,reduceTransparency:reduceTransparency),in:shape)
        } else {
            content.background { shape.fill(fill).overlay { if let border { shape.strokeBorder(border,lineWidth:1) } } }
        }
    }
}
/// Neighbouring glass controls share one container, so they sample what's behind them together and render once.
struct GlassGroup<Content:View>: View {
    @Environment(\.glass) private var glass
    var spacing:CGFloat
    @ViewBuilder var content:Content
    var body:some View { if glass != nil { GlassEffectContainer(spacing:spacing) { content } } else { content } }
}
extension Color { init(hex:UInt32) { self.init(red:Double((hex>>16)&255)/255,green:Double((hex>>8)&255)/255,blue:Double(hex&255)/255) } }

/// Figtree for text, SF Mono for dates and counts, matching the reference's two type families.
enum BuddyFont {
    /// Sizes scale with Dynamic Type, which rounds them to whole points.
    static func text(_ size:CGFloat,_ weight:Font.Weight = .regular,relativeTo style:Font.TextStyle = .body)->Font {
        _ = BuddyIcons.registered
        let face = switch weight { case .medium:"Medium"; case .semibold:"SemiBold"; case .bold:"Bold"; case .heavy,.black:"ExtraBold"; default:"Regular" }
        return .custom("Figtree-"+face,size:size,relativeTo:style)
    }
    static func mono(_ size:CGFloat,_ weight:Font.Weight = .regular)->Font { .system(size:size,weight:weight,design:.monospaced) }
}

struct Surface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var padding:CGFloat=14
    var radius:CGFloat=24
    var tint:Color = .clear
    func body(content:Content)->some View {
        let shape=RoundedRectangle(cornerRadius:radius,style:.circular)
        content.padding(padding).background {
            shape.fill(BuddyStyle.surface(scheme))
                .overlay { shape.fill(LinearGradient(stops:[.init(color:tint.opacity(scheme == .dark ? 0.05:0.06),location:0),.init(color:.clear,location:0.65)],startPoint:.top,endPoint:.bottom)) }
        }.overlay { shape.strokeBorder(BuddyStyle.border(scheme),lineWidth:1) }
    }
}
struct Panel: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var padding:CGFloat=0
    var radius:CGFloat=20
    var border:Double=0.07
    func body(content:Content)->some View {
        let shape=RoundedRectangle(cornerRadius:radius,style:.circular)
        content.padding(padding).background(BuddyStyle.panel(scheme),in:shape).overlay { shape.strokeBorder(BuddyStyle.border(scheme,border),lineWidth:1) }
    }
}
/// Rounded input field with the reference's dark fill and hairline border.
struct BuddyField: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent
    func body(content:Content)->some View {
        let shape=RoundedRectangle(cornerRadius:15,style:.circular)
        content.font(BuddyFont.text(15.5)).foregroundStyle(BuddyStyle.text(scheme)).tint(accent.color).padding(.horizontal,16).padding(.vertical,14).frame(minHeight:52)
            .background(BuddyStyle.field(scheme),in:shape).overlay{shape.strokeBorder(BuddyStyle.border(scheme,0.1),lineWidth:1)}
    }
}
/// Buttons whose disabled state is drawn by the label itself (no system dimming).
/// Dims and presses in slightly while touched, so a tap is felt before the screen changes.
struct FlatButtonStyle: ButtonStyle {
    func makeBody(configuration:Configuration)->some View { Pressable(label:configuration.label,pressed:configuration.isPressed) }
    private struct Pressable<Label:View>: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let label:Label
        let pressed:Bool
        // Reduce Motion keeps the dimming and drops the scale.
        var body:some View {
            label.opacity(pressed ? 0.7:1).scaleEffect(pressed && !reduceMotion ? 0.97:1)
                .animation(.timingCurve(0.23,1,0.32,1,duration:0.16),value:pressed)
        }
    }
}
/// HabitKit-style sheets: visible grabber over the dark canvas. With Liquid Glass, a half-height sheet (`partial`)
/// keeps iOS's glass sheet instead, which turns opaque at full height.
struct BuddySheet: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.glass) private var glass
    var partial=false
    var background:Color?
    func body(content:Content)->some View {
        if partial && glass != nil { content.presentationDragIndicator(.visible) }
        else { content.presentationDragIndicator(.visible).presentationBackground(background ?? BuddyStyle.canvas(scheme)) }
    }
}
extension View {
    func buddySheet(partial:Bool=false,background:Color?=nil)->some View { modifier(BuddySheet(partial:partial,background:background)) }
    func buddyField()->some View { modifier(BuddyField()) }
    func surface(padding:CGFloat=14,radius:CGFloat=24,tint:Color = .clear)->some View { modifier(Surface(padding:padding,radius:radius,tint:tint)) }
    func panel(padding:CGFloat=0,radius:CGFloat=20,border:Double=0.07)->some View { modifier(Panel(padding:padding,radius:radius,border:border)) }
    func glassChrome(in shape:some InsettableShape,prominent:Bool=false,fill:some ShapeStyle,border:AnyShapeStyle?=nil)->some View { modifier(GlassChrome(shape:shape,prominent:prominent,fill:AnyShapeStyle(fill),border:border)) }
    /// A screen's floating top controls, over `backdrop` (the canvas opacity) in the flat look. With Liquid Glass the
    /// backdrop goes and iOS softens the content scrolling under them instead.
    func topBar(backdrop:Double=1,@ViewBuilder _ bar:()->some View)->some View { modifier(TopBar(backdrop:backdrop,bar:bar())) }
    /// Uppercase field caption used by the editor and settings.
    func fieldCaption()->some View { font(BuddyFont.text(11.5,.medium)).tracking(1.3).textCase(.uppercase) }
}
struct HabitIconEntry: Decodable, Identifiable {
    let id:String
    let name:String
    let unicode:String
    let regular:Bool
    let keywords:[String]
    var glyph:String { UInt32(unicode,radix:16).flatMap(UnicodeScalar.init).map(String.init) ?? "" }
    var lucide:Bool { id.hasPrefix("lu:") }
}
enum BuddyIcons {
    static let registered:Void = {
        for name in ["FontAwesome-Solid.otf","FontAwesome-Regular.otf","Lucide.ttf","Figtree-Regular.ttf","Figtree-Medium.ttf","Figtree-SemiBold.ttf","Figtree-Bold.ttf","Figtree-ExtraBold.ttf"] {
            if let url=Bundle.main.url(forResource:name,withExtension:nil) { CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil) }
        }
    }()
    private static func load(_ file:String)->[HabitIconEntry] {
        guard let url=Bundle.main.url(forResource:file,withExtension:"json"),let bytes=try? Data(contentsOf:url) else { return [] }
        return (try? JSONDecoder().decode([HabitIconEntry].self,from:bytes)) ?? []
    }
    /// The catalogs load separately: controls and most habits need only Lucide, so the first icon drawn doesn't decode both.
    private static let lucideEntries:[HabitIconEntry] = { _ = registered; return load("lucide-icons") }()
    private static let fontAwesomeEntries:[HabitIconEntry] = { _ = registered; return load("habit-icons") }()
    private static let lucideByID=Dictionary(uniqueKeysWithValues:lucideEntries.map{($0.id,$0)})
    private static let fontAwesomeByID=Dictionary(uniqueKeysWithValues:fontAwesomeEntries.map{($0.id,$0)})
    /// Lucide line icons first (the reference's style), then the Font Awesome set kept for existing habits.
    static let all:[HabitIconEntry] = lucideEntries+fontAwesomeEntries
    /// Each icon's ID, name and keywords, joined once for picker searches.
    private static let searchText=all.map{([$0.id,$0.name]+$0.keywords).joined(separator:" ")}
    static let aliases=["leaf.fill":"leaf","heart.fill":"heart-circle-bolt","dumbbell.fill":"dumbbell","book.closed.fill":"book","drop.fill":"glass-water","figure.walk":"person-walking","moon.fill":"moon","sun.max.fill":"sun","pencil.tip":"pen-nib","laptopcomputer":"laptop","cup.and.saucer.fill":"mug-saucer","fork.knife":"utensils","brain.head.profile":"brain","guitars.fill":"guitar","music.note":"music","paintbrush.fill":"paintbrush","flame.fill":"fire","bolt.fill":"bolt","bed.double.fill":"bed","figure.mind.and.body":"spa","cross.case.fill":"kit-medical","pill.fill":"pills","carrot.fill":"carrot","bicycle":"bicycle","figure.run":"person-running","code":"code","wallet.pass.fill":"wallet","phone.down.fill":"phone-slash","nosign":"ban","smoke.fill":"smoking","gamecontroller.fill":"gamepad","camera.fill":"camera","dog.fill":"dog","house.fill":"house","star.fill":"star","globe":"globe","water.waves":"water"]
    /// SF Symbol names used by controls, mapped to the matching Lucide outline.
    static let chrome=["gearshape":"settings","chart.xyaxis.line":"chart-no-axes-combined","plus":"plus","chevron.left":"chevron-left","chevron.right":"chevron-right","square.and.pencil":"square-pen","xmark":"x","square.and.arrow.up":"share","flame.fill":"flame","flame":"flame","target":"target","checkmark":"check","calendar":"calendar","bell":"bell","note.text":"notebook-pen","archivebox":"archive","slider.horizontal.3":"sliders-horizontal","arrow.up.arrow.down":"arrow-up-down","trash":"trash","clock":"clock","folder.fill":"folder","square.grid.3x3.fill":"grid-3x3","pencil":"pencil","eraser":"eraser","timer":"timer","sparkles":"sparkles","trophy":"trophy","snowflake":"snowflake"]
    static func entry(_ symbol:String)->HabitIconEntry? { symbol.hasPrefix("lu:") ? lucideByID[symbol] : fontAwesomeByID[symbol] ?? aliases[symbol].flatMap{fontAwesomeByID["fa:"+$0]} }
    static func lucide(_ name:String)->String? { (lucideByID["lu:"+name] ?? chrome[name].flatMap{lucideByID["lu:"+$0]})?.glyph }
    /// Ranks icons for a habit name: the curated keyword catalog, then Lucide's own names and keywords.
    static let suggester=IconSuggester(icons:lucideEntries.map{IconSuggester.Entry(id:$0.id,name:$0.name,keywords:$0.keywords)})
    /// Picker search: icons the habit-name matcher ranks for the query, then every other icon whose name or keywords contain it.
    static func search(_ text:String)->[HabitIconEntry] {
        guard !text.isEmpty else { return all }
        let ranked=suggester.suggest(text,limit:12),first=Set(ranked)
        return ranked.compactMap{lucideByID[$0]}+zip(all,searchText).filter{!first.contains($0.0.id) && $0.1.localizedCaseInsensitiveContains(text)}.map(\.0)
    }
}
/// Outlines from the reference that differ from Lucide, drawn on a 24-point grid.
enum DrawnGlyph: String {
    case stats, check, calendar
    func path(in r:CGRect)->Path {
        let s=r.width/24
        func p(_ x:CGFloat,_ y:CGFloat)->CGPoint { CGPoint(x:r.minX+x*s,y:r.minY+y*s) }
        var path=Path()
        switch self {
        case .stats:
            path.move(to:p(1.4,10.3));path.addLine(to:p(8.5,5.1));path.addLine(to:p(13.9,10.1));path.addLine(to:p(21.9,3.4))
            for (x,top) in [(3.4,15.4),(8.7,11.4),(14.5,14.3),(19.8,11.4)] as [(CGFloat,CGFloat)] { path.move(to:p(x,top));path.addLine(to:p(x,21.5)) }
        case .check:
            path.move(to:p(0.8,15.1));path.addLine(to:p(8.5,21.3));path.addLine(to:p(22.7,2.4))
        case .calendar:
            path.addRoundedRect(in:CGRect(origin:p(3.7,6.3),size:CGSize(width:16.6*s,height:14.6*s)),cornerSize:CGSize(width:2.9*s,height:2.9*s))
            for x:CGFloat in [7.7,16.2] { path.move(to:p(x,3.1));path.addLine(to:p(x,8)) }
            path.addRoundedRect(in:CGRect(origin:p(8,12),size:CGSize(width:5.7*s,height:4.9*s)),cornerSize:CGSize(width:1.1*s,height:1.1*s))
        }
        return path
    }
    /// Stroke widths measured in the reference, in points.
    var lineWidth:CGFloat { switch self { case .stats:1.25; case .check:1.6; case .calendar:1.5 } }
}
struct DrawnIcon: View {
    let glyph:DrawnGlyph
    var size:CGFloat
    var body:some View {
        Canvas { context,canvas in context.stroke(glyph.path(in:CGRect(x:0,y:0,width:canvas.width,height:canvas.width)),with:.foreground,style:StrokeStyle(lineWidth:glyph.lineWidth,lineCap:.round,lineJoin:.round)) }
            .frame(width:size,height:size).accessibilityHidden(true)
    }
}
/// A Lucide outline icon, or an SF Symbol when no Lucide match exists.
struct LucideIcon: View {
    let name:String
    var size:CGFloat
    init(_ name:String,size:CGFloat=20) { self.name=name; self.size=size }
    var body:some View {
        Group {
            if let drawn=DrawnGlyph(rawValue:name) { DrawnIcon(glyph:drawn,size:size) }
            else if let glyph=BuddyIcons.lucide(name) { Text(glyph).font(.custom("lucide",size:size)).fixedSize() }
            else { Image(systemName:name).font(.system(size:size*0.78)) }
        }.frame(width:size,height:size).accessibilityHidden(true)
    }
}
struct BuddyGlyph: View {
    let symbol:String
    var size:CGFloat=18
    var outline=false
    var body:some View {
        Group {
            if let entry=BuddyIcons.entry(symbol) {
                if entry.lucide { Text(entry.glyph).font(.custom("lucide",size:size)).fixedSize().frame(width:size,height:size) }
                else { Text(entry.glyph).font(.custom(outline && entry.regular ? "FontAwesome7Free-Regular":"FontAwesome7Free-Solid",size:size*0.85)) }
            }
            else if symbol.unicodeScalars.contains(where:{$0.properties.isEmojiPresentation}) || symbol.contains("\u{FE0F}") { Text(symbol).font(.system(size:size*0.85)) }
            else { Image(systemName:symbol.hasPrefix("fa:") || symbol.hasPrefix("lu:") ? "questionmark":symbol).font(.system(size:size*0.85)) }
        }.accessibilityHidden(true)
    }
}
struct HabitIcon: View {
    let habit:Habit
    var size:CGFloat=46
    var circular=false
    var body:some View {
        let c=BuddyStyle.color(habit.color)
        BuddyGlyph(symbol:habit.symbol,size:size*(circular ? 0.48:0.55)).foregroundStyle(c).frame(width:size,height:size)
            .background(c.opacity(0.14),in:RoundedRectangle(cornerRadius:circular ? size/2:size*0.29,style:.circular)).accessibilityHidden(true)
    }
}
struct TopBar<Bar:View>: ViewModifier {
    @Environment(\.glass) private var glass
    @Environment(\.colorScheme) private var scheme
    let backdrop:Double
    let bar:Bar
    func body(content:Content)->some View {
        content.safeAreaBar(edge:.top,spacing:0){ bar.background(BuddyStyle.canvas(scheme).opacity(glass == nil ? backdrop:0)) }
            .scrollEdgeEffectHidden(glass == nil,for:.top)
    }
}
struct MetricChip: View {
    var symbol:String
    var text:String
    var color:Color
    var body:some View {
        HStack(spacing:2.7){LucideIcon(symbol,size:15.2);Text(text).font(BuddyFont.mono(12.2)).contentTransition(.numericText())}
            .padding(.leading,8.5).padding(.trailing,11).frame(height:29).foregroundStyle(color).background(color.opacity(0.12),in:Capsule())
    }
}
struct CircleControl: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent
    let symbol:String
    let label:String
    var filled=false
    var size:CGFloat=42
    var glyph:CGFloat=21
    var action:()->Void
    var body:some View {
        Button(action:action) {
            LucideIcon(symbol,size:glyph).frame(width:size,height:size)
                .glassChrome(in:Circle(),prominent:filled,fill:filled ? accent.color:BuddyStyle.control(scheme),border:filled ? nil:AnyShapeStyle(BuddyStyle.controlBorder(scheme)))
                .foregroundStyle(filled ? accent.foreground:BuddyStyle.text(scheme)).contentShape(Circle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}
/// Sheet title row: a close control at the leading edge and a centered bold title.
struct SheetHeader: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let title:String
    var trailingSymbol:String?
    var trailingAction:(()->Void)?
    var body:some View {
        ZStack {
            Text(title).font(BuddyFont.text(20,.bold)).tracking(1.7).foregroundStyle(BuddyStyle.text(scheme)).lineLimit(1).padding(.horizontal,56)
            GlassGroup(spacing:8) {
                HStack {
                    CircleControl(symbol:"x",label:"Close \(title)",size:38,glyph:16){dismiss()}
                    Spacer()
                    if let trailingSymbol,let trailingAction { CircleControl(symbol:trailingSymbol,label:title,filled:true,size:38,glyph:17,action:trailingAction) }
                }
            }
        }.padding(.horizontal,12).padding(.top,25).padding(.bottom,10)
    }
}
struct PrimaryAction: View {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accent) private var accent
    let title:String
    var symbol:String?
    var action:()->Void
    var body:some View {
        Button(action:action) {
            HStack(spacing:8){if let symbol{LucideIcon(symbol,size:18)};Text(title)}.font(BuddyFont.text(18,.semibold))
                .frame(maxWidth:.infinity,minHeight:54).contentShape(Capsule())
        }.buttonStyle(.plain).foregroundStyle(enabled ? accent.foreground:Color(hex:0x88888A))
            .glassChrome(in:Capsule(),prominent:enabled,fill:accent.color.opacity(enabled ? 1:0.5))
    }
}
/// The 7 × 3 color grid. Swatches are centered in seven equal columns, with a ring around the selection.
struct ColorPalette: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var selection:String
    /// What VoiceOver calls each swatch, for telling two palettes on one page apart.
    var label:(String)->String={$0}
    var body:some View {
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:0),count:7),spacing:8) {
            ForEach(BuddyStyle.colors,id:\.0){token,_ in
                Button{selection=token}label:{
                    RoundedRectangle(cornerRadius:10,style:.circular).fill(BuddyStyle.color(token)).frame(width:37,height:37)
                        .overlay{if selection==token{RoundedRectangle(cornerRadius:14,style:.circular).strokeBorder(BuddyStyle.color(token),lineWidth:2).padding(-5)}}
                        .frame(maxWidth:.infinity).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(label(token)).accessibilityAddTraits(selection==token ? .isSelected:[])
            }
        }
    }
}
struct CompletionBadge: View {
    @Environment(\.colorScheme) private var scheme
    let habit:Habit
    @ViewData var data:BuddyData
    var day=Day()
    var size:CGFloat=48
    var body:some View {
        let p=Engine.progress(habit,day:day,data:data),g=habit.goal(on:day),color=BuddyStyle.color(habit.color)
        let shape=RoundedRectangle(cornerRadius:size/3,style:.circular),ring=size*0.62,line=max(1.5,size*0.045)
        ZStack {
            shape.fill(p.success && g.tracking == .yesNo ? color:(scheme == .dark ? Color.white.opacity(0.05):Color.black.opacity(0.035)))
            if !(p.success && g.tracking == .yesNo) { shape.strokeBorder(scheme == .dark ? Color.white.opacity(0.13):Color.black.opacity(0.09),lineWidth:1) }
            if g.tracking == .count && g.target <= 12_000 && !p.slip {
                let count=max(1,Int(g.target/1_000))
                ForEach(0..<count,id:\.self){n in Circle().trim(from:CGFloat(n)/CGFloat(count)+0.02,to:CGFloat(n+1)/CGFloat(count)-0.02).stroke(color.opacity(Int(p.amount/1_000)>n ? 1:0.2),style:StrokeStyle(lineWidth:line,lineCap:.round)).rotationEffect(.degrees(-90)).frame(width:ring,height:ring) }
            } else if g.tracking != .yesNo && !p.slip {
                Circle().stroke(color.opacity(0.2),lineWidth:line).frame(width:ring,height:ring)
                Circle().trim(from:0,to:p.fraction).stroke(color,style:StrokeStyle(lineWidth:line,lineCap:.round)).rotationEffect(.degrees(-90)).frame(width:ring,height:ring)
            }
            Group {
                if g.tracking == .yesNo && !p.slip { DrawnIcon(glyph:.check,size:size*0.34).offset(y:size*0.02) }
                else { LucideIcon(p.slip ? "x":p.success ? "check":"plus",size:size*(p.slip ? 0.46:0.32)) }
            }
                .foregroundStyle(p.success && g.tracking == .yesNo ? Color.black.opacity(0.75):g.tracking == .yesNo ? Color(hex:0x898989):color)
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
    /// A new habit starts with the first palette color and a pulse icon, like the reference editor.
    static func draft()->Habit { var h=Habit(name:"");h.color="coral";h.symbol="lu:activity";return h }
}
