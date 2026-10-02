import SwiftUI

struct ShareHabitView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let habit: Habit
    @State private var dark = true
    @State private var description = true
    @State private var streak = true
    @State private var indicator = true
    @State private var color = "mint"
    @State private var shareFile: URL?
    @State private var message: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    shareCard.frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 22))
                    VStack(spacing: 18) {
                        Toggle("Dark Theme", isOn: $dark)
                        Toggle("Show Description", isOn: $description)
                        Toggle("Show Streak", isOn: $streak)
                        Toggle("Show Completion Indicator", isOn: $indicator)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                            ForEach(BuddyStyle.colors, id: \.0) { token, _ in Button { color = token } label: { RoundedRectangle(cornerRadius: 9).fill(BuddyStyle.color(token)).frame(height: 32).overlay { if color == token { Image(systemName: "checkmark").foregroundStyle(.black) } } }.buttonStyle(.plain).accessibilityLabel(token) }
                        }
                    }.surface()
                    Button("Create Share Image", systemImage: "square.and.arrow.up") { render() }.buttonStyle(.borderedProminent)
                    if let shareFile { ShareLink(item: shareFile) { Label("Share PNG", systemImage: "square.and.arrow.up") } }
                    if let message { Text(message).foregroundStyle(.red) }
                }.padding(20)
            }.navigationTitle("Share Habit").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .onAppear { color = habit.color }
        }
    }
    private var shareCard: some View {
        VStack(alignment: .trailing, spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                HStack { HabitIcon(habit: habit); VStack(alignment: .leading, spacing: 3) { Text(habit.name).font(.headline); if description { Text(habit.detail).font(.caption).foregroundStyle(.secondary) } }; Spacer(); if indicator { Image(systemName: Engine.progress(habit, day: Day(), data: store.data).success ? "checkmark" : "plus").foregroundStyle(BuddyStyle.color(habit.color)).padding(12).background(BuddyStyle.color(habit.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 12)) } }
                Heatmap(habit: habit, data: store.data)
                if streak { MetricChip(symbol: "flame.fill", text: "\(Engine.stats(habit, data: store.data).currentStreak) day streak", color: BuddyStyle.color(habit.color)) }
            }.surface()
            Label("Habit Buddy", systemImage: "square.grid.3x3.fill").font(.caption.weight(.semibold)).foregroundStyle(.white)
        }.padding(20).background(BuddyStyle.color(color)).environment(\.colorScheme, dark ? .dark : .light)
    }
    @MainActor private func render() {
        let renderer = ImageRenderer(content: shareCard.frame(width: 390))
        renderer.scale = 3
        guard let image = renderer.uiImage, let bytes = image.pngData() else { message = "Could not create the image. Please try again."; return }
        do {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("habit-\(habit.id.uuidString).png")
            try bytes.write(to: file, options: .atomic); shareFile = file
        } catch { message = error.localizedDescription }
    }
}
