import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

struct ShareHabitView:View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let habit:Habit
    @State private var dark=true
    @State private var description=true
    @State private var streak=false
    @State private var indicator=true
    @State private var color="mint"
    @State private var export:HabitImageExport?
    @State private var message:String?
    @State private var rendering=false
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
            PrimaryAction(title:"Share Habit",symbol:"square.and.arrow.up",action:render).disabled(rendering).accessibilityIdentifier("share-habit-image").padding(24)
        }.background(BuddyStyle.canvas(scheme)).onAppear{color=habit.color}
            .sheet(item:$export){image in NativeShareSheet(items:[image.url])}
    }
    private var shareCard:some View {
        var a=habit.cardAppearance(store.settings);a.description=description;a.streak=streak;a.goal=streak;a.indicator=indicator;a.monthLabels=false;a.weekdayLabels=false
        return VStack(alignment:.trailing,spacing:12){HabitCard(habit:habit,data:store.data,appearance:a,interactive:false);Label("Habit Buddy",systemImage:"square.grid.3x3.fill").font(.system(size:10,weight:.semibold)).foregroundStyle(.white)}.padding(20).background(BuddyStyle.color(color)).environment(\.colorScheme,dark ? .dark:.light)
    }
    @MainActor private func render(){
        guard !rendering else{return}
        rendering=true;message=nil
        Task{
            defer{rendering=false}
            do{export=HabitImageExport(url:try await ImageExport.png(shareCard,width:390,scale:3,name:"habit-\(habit.id.uuidString).png"))}
            catch{message=error.localizedDescription}
        }
    }
}
private struct HabitImageExport:Identifiable {let id=UUID();let url:URL}
struct NativeShareSheet:UIViewControllerRepresentable {
    let items:[Any]
    func makeUIViewController(context:Context)->UIActivityViewController{UIActivityViewController(activityItems:items,applicationActivities:nil)}
    func updateUIViewController(_ uiViewController:UIActivityViewController,context:Context){}
}

/// Turns a SwiftUI view into a PNG file. Layout and rendering stay on the main actor; encoding and writing run
/// in the background. The layout is measured before any pixels are allocated, and the scale drops for very
/// large images so one never needs more than `maxPixels` (about 96 MB at four bytes a pixel).
enum ImageExport {
    static let maxPixels: CGFloat = 24_000_000
    struct Failed: LocalizedError { var errorDescription: String? { "Could not create the image. Please try again." } }
    @MainActor static func png<Content: View>(_ content: Content, width: CGFloat, scale: CGFloat, name: String) async throws -> URL {
        let renderer = ImageRenderer(content: content.frame(width: width))
        var size = CGSize.zero
        renderer.render { measured, _ in size = measured }
        guard size.width > 0, size.height > 0 else { throw Failed() }
        renderer.scale = min(scale, (maxPixels / (size.width * size.height)).squareRoot())
        guard let image = renderer.cgImage else { throw Failed() }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-")), box = Unchecked(image)
        try await Task.detached(priority: .userInitiated) {
            guard let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw Failed() }
            CGImageDestinationAddImage(destination, box.value, nil)
            guard CGImageDestinationFinalize(destination) else { throw Failed() }
        }.value
        return file
    }
}
