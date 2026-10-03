import SwiftUI

struct YearReviewView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let year: Int
    let habits: [Habit]
    @State private var format = "Cards"
    @State private var dark = true
    @State private var outputs: [URL] = []
    @State private var message: String?
    @State private var rendering = false
    @State private var total: Int?
    private let formats = ["Cards", "Compact", "Grid", "Poster"]
    private var end: Day { min(Day(), Day(rawValue: "\(year)-12-31")!) }
    private var start: Day { Day(rawValue: "\(year)-01-01")! }
    /// Many habits share as several images, so no single image grows without limit.
    private var perImage: Int { format == "Grid" ? 24 : 12 }
    private var pages: [[Habit]] { stride(from: 0, to: habits.count, by: perImage).map { Array(habits[$0..<min($0 + perImage, habits.count)]) } }
    var body: some View {
        let pages = pages
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Format", selection: $format) { ForEach(formats, id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                    Toggle("Dark Theme", isOn: $dark)
                    review(pages.first ?? [], page: 0, of: pages.count).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 20))
                    if pages.count > 1 { Text("Shares as \(pages.count) images of up to \(perImage) habits each.").font(.footnote).foregroundStyle(.secondary) }
                    Button { render(pages) } label: {
                        HStack(spacing: 8) { if rendering { ProgressView() } else { Image(systemName: "square.and.arrow.up") }; Text(pages.count > 1 ? "Create Year Images" : "Create Year Image") }
                    }.buttonStyle(.borderedProminent).disabled(habits.isEmpty || rendering)
                    if !outputs.isEmpty { ShareLink(items: outputs) { Label(outputs.count > 1 ? "Share \(outputs.count) PNGs" : "Share PNG", systemImage: "square.and.arrow.up") } }
                    if let message { Text(message).foregroundStyle(.red) }
                }.padding(20)
            }.navigationTitle("Year in Review").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task(id: store.revision) {
            let data = store.data, habits = habits, start = start, end = end
            total = await offMain {
                habits.reduce(0) { result, h in result + Day.range(max(start, h.created), end).filter { h.goal(on: $0).mode == .build && Engine.progress(h, day: $0, data: data, today: end).success }.count }
            } ?? total
        }
        .onChange(of: format) { _, _ in outputs = [] }
        .onChange(of: dark) { _, _ in outputs = [] }
    }
    private func review(_ shown: [Habit], page: Int, of count: Int) -> some View {
        VStack(alignment: .leading, spacing: format == "Compact" ? 12 : 20) {
            HStack(alignment: .lastTextBaseline) {
                Text(String(year)).font(.system(size: format == "Poster" ? 72 : 42, weight: .bold)); Spacer()
                VStack(alignment: .trailing, spacing: 2) { Text("Habit Buddy").font(.caption.weight(.semibold)); if count > 1 { Text("\(page + 1) of \(count)").font(.caption2).foregroundStyle(.secondary) } }
            }
            Text(total.map { "\($0) completions" } ?? " ").font(format == "Poster" ? .title2.bold() : .headline).foregroundStyle(BuddyStyle.purple).monospacedDigit()
            if format == "Grid" {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) { ForEach(shown) { h in VStack(alignment: .leading, spacing: 7) { header(h); Heatmap(habit: h, data: store.data, weeks: 26, end: end, labels: false) }.surface() } }
            } else {
                ForEach(shown) { h in
                    VStack(alignment: .leading, spacing: 9) {
                        header(h)
                        Heatmap(habit: h, data: store.data, weeks: 53, end: end, labels: format != "Compact")
                    }.padding(format == "Cards" ? 12 : 0).background(format == "Cards" ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }.padding(24).background(dark ? Color(white: 0.06) : .white).environment(\.colorScheme, dark ? .dark : .light)
    }
    private func header(_ habit: Habit) -> some View { HStack { HabitIcon(habit: habit, size: 28); Text(habit.name).font(.subheadline.weight(.semibold)); Spacer() } }
    /// One image per page, rendered in turn; a second tap while it runs does nothing.
    @MainActor private func render(_ pages: [[Habit]]) {
        guard !rendering, !pages.isEmpty else { return }
        rendering = true; message = nil; outputs = []
        Task {
            defer { rendering = false }
            do {
                var files: [URL] = []
                for (n, page) in pages.enumerated() {
                    let name = pages.count == 1 ? "habit-buddy-\(year).png" : "habit-buddy-\(year)-\(n + 1).png"
                    files.append(try await ImageExport.png(review(page, page: n, of: pages.count), width: format == "Grid" ? 720 : 540, scale: 2, name: name))
                }
                outputs = files
            } catch { message = error.localizedDescription }
        }
    }
}
