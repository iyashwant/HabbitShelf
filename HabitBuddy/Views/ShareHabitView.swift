import SwiftUI
import UIKit

struct ShareHabitView:View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.colorScheme) private var scheme
    let habit:Habit
    @State private var dark=true
    @State private var description=true
    @State private var streak=false
    @State private var indicator=true
    @State private var color="mint"
    @State private var shareFile:URL?
    @State private var message:String?
    var body:some View {
        VStack(spacing:0){
            SheetHeader(title:"Share Habit",trailingSymbol:"square.and.arrow.up",trailingAction:render)
            ScrollView {
                VStack(spacing:20){
                    shareCard.clipShape(RoundedRectangle(cornerRadius:20))
                    VStack(alignment:.leading,spacing:18){
                        Text("Appearance").font(.system(size:16,weight:.semibold))
                        HStack{Text("Theme").font(.system(size:14));Spacer();SegmentedChoice(selection:$dark,options:[(false,"Light"),(true,"Dark")]).frame(width:150)}
                        ColorPalette(selection:$color)
                        Toggle("Completion Indicator",isOn:$indicator).font(.system(size:14))
                        DisclosureGroup("More Options"){Toggle("Description",isOn:$description);Toggle("Streak",isOn:$streak)}.font(.system(size:13))
                    }.surface()
                    if let message{Text(message).foregroundStyle(.red)}
                }.padding(20)
            }
            PrimaryAction(title:"Share Habit",symbol:"square.and.arrow.up",action:render).padding(24)
        }.background(BuddyStyle.canvas(scheme)).onAppear{color=habit.color}
            .sheet(isPresented:Binding(get:{shareFile != nil},set:{if !$0{shareFile=nil}})){if let shareFile{NativeShareSheet(items:[shareFile])}}
    }
    private var shareCard:some View {
        var a=habit.cardAppearance(store.data.settings);a.description=description;a.streak=streak;a.goal=streak;a.indicator=indicator;a.monthLabels=false;a.weekdayLabels=false
        return VStack(alignment:.trailing,spacing:12){HabitCard(habit:habit,data:store.data,appearance:a,interactive:false);Label("Habit Buddy",systemImage:"square.grid.3x3.fill").font(.system(size:10,weight:.semibold)).foregroundStyle(.white)}.padding(20).background(BuddyStyle.color(color)).environment(\.colorScheme,dark ? .dark:.light)
    }
    @MainActor private func render(){let renderer=ImageRenderer(content:shareCard.frame(width:390));renderer.scale=3;guard let image=renderer.uiImage,let bytes=image.pngData()else{message="Could not create the image. Please try again.";return};do{let file=FileManager.default.temporaryDirectory.appendingPathComponent("habit-\(habit.id.uuidString).png");try bytes.write(to:file,options:.atomic);shareFile=file}catch{message=error.localizedDescription}}
}
struct NativeShareSheet:UIViewControllerRepresentable {
    let items:[Any]
    func makeUIViewController(context:Context)->UIActivityViewController{{ let controller=UIActivityViewController(activityItems:items,applicationActivities:nil);controller.view.accessibilityIdentifier="native-share-sheet";return controller }()}
    func updateUIViewController(_ uiViewController:UIActivityViewController,context:Context){}
}
