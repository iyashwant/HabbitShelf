import SwiftUI

struct YearReviewView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let year: Int
    let habits: [Habit]
    @State private var format = "Cards"
    @State private var dark = true
    @State private var output: URL?
    @State private var message: String?
    private let formats = ["Cards", "Compact", "Grid", "Poster"]
    private var end: Day { min(Day(), Day(rawValue: "\(year)-12-31")!) }
    private var start: Day { Day(rawValue: "\(year)-01-01")! }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Format", selection: $format) { ForEach(formats, id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                    Toggle("Dark Theme", isOn: $dark)
                    review.frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 20))
                    Button("Create Year Image", systemImage: "square.and.arrow.up") { render() }.buttonStyle(.borderedProminent).disabled(habits.isEmpty)
                    if let output { ShareLink(item: output) { Label("Share PNG", systemImage: "square.and.arrow.up") } }
                    if let message { Text(message).foregroundStyle(.red) }
                }.padding(20)
            }.navigationTitle("Year in Review").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private var review: some View {
        VStack(alignment: .leading, spacing: format == "Compact" ? 12 : 20) {
            HStack(alignment: .lastTextBaseline) { Text(String(year)).font(.system(size: format == "Poster" ? 72 : 42, weight: .bold)); Spacer(); Text("Habit Buddy").font(.caption.weight(.semibold)) }
            Text("\(total) completions").font(format == "Poster" ? .title2.bold() : .headline).foregroundStyle(BuddyStyle.purple).monospacedDigit()
            if format == "Grid" {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) { ForEach(habits) { h in VStack(alignment: .leading, spacing: 7) { header(h); Heatmap(habit: h, data: store.data, weeks: 26, end: end, labels: false) }.surface() } }
            } else {
                ForEach(habits) { h in
                    VStack(alignment: .leading, spacing: 9) {
                        header(h)
                        Heatmap(habit: h, data: store.data, weeks: 53, end: end, labels: format != "Compact")
                    }.padding(format == "Cards" ? 12 : 0).background(format == "Cards" ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }.padding(24).background(dark ? Color(white: 0.06) : .white).environment(\.colorScheme, dark ? .dark : .light)
    }
    private var total: Int {
        habits.reduce(0) { result, h in result + Day.range(max(start, h.created), end).filter { h.goal(on: $0).mode == .build && Engine.progress(h, day: $0, data: store.data).success }.count }
    }
    private func header(_ habit: Habit) -> some View { HStack { HabitIcon(habit: habit, size: 28); Text(habit.name).font(.subheadline.weight(.semibold)); Spacer() } }
    @MainActor private func render() {
        let renderer = ImageRenderer(content: review.frame(width: format == "Grid" ? 720 : 540))
        renderer.scale = 2
        guard let bytes = renderer.uiImage?.pngData() else { message = "Could not create the image. Try fewer habits."; return }
        do { let file = FileManager.default.temporaryDirectory.appendingPathComponent("habit-buddy-\(year).png"); try bytes.write(to: file, options: .atomic); output = file }
        catch { message = error.localizedDescription }
    }
}
