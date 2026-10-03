import SwiftUI

/// Every day note across habits, newest first and grouped by month, with search and a habit filter.
struct NotesTimelineView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @State private var habit: UUID?
    @State private var selection: DaySelection?
    private struct Entry: Identifiable { let habit: Habit; let record: Record; var id: String { record.key } }
    var body: some View {
        let order = Dictionary(uniqueKeysWithValues: store.data.habits.map { ($0.id, $0) })
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = store.data.records.values.filter { !$0.note.isEmpty }.compactMap { record in order[record.habitID].map { Entry(habit: $0, record: record) } }
        let entries = all.filter { (habit == nil || $0.habit.id == habit) && (text.isEmpty || $0.record.note.localizedCaseInsensitiveContains(text) || $0.habit.name.localizedCaseInsensitiveContains(text)) }
            .sorted { $0.record.day == $1.record.day ? $0.habit.order < $1.habit.order : $0.record.day > $1.record.day }
        let months = Dictionary(grouping: entries) { $0.record.day.month }.sorted { $0.key > $1.key }
        let withNotes = store.data.habits.filter { h in all.contains { $0.habit.id == h.id } }.sorted { $0.order < $1.order }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                HStack(spacing: 8) {
                    LucideIcon("search", size: 17).foregroundStyle(BuddyStyle.secondaryText(scheme))
                    TextField("Search notes", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel("Search notes")
                    if !query.isEmpty { Button { query = "" } label: { LucideIcon("x", size: 15) }.buttonStyle(.plain).foregroundStyle(BuddyStyle.secondaryText(scheme)).accessibilityLabel("Clear search") }
                }.buddyField()
                if withNotes.count > 1 { HabitFilterBar(habits: withNotes, selection: $habit) }
                if all.isEmpty {
                    ContentUnavailableView("No notes yet", systemImage: "note.text", description: Text("Press and hold a day in a habit's calendar to add a note. Every note appears here."))
                } else if entries.isEmpty {
                    ContentUnavailableView.search(text: text)
                } else {
                    Text("\(entries.count) \(entries.count == 1 ? "note" : "notes")").font(BuddyFont.mono(11)).tracking(1).foregroundStyle(BuddyStyle.tertiaryText(scheme)).padding(.leading, 4)
                }
                ForEach(months, id: \.key) { month, items in
                    Section {
                        ForEach(items) { entry in card(entry) }
                    } header: {
                        Text(Day(rawValue: month + "-01")!.monthTitle).fieldCaption().foregroundStyle(BuddyStyle.secondaryText(scheme))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).padding(.leading, 4).background(BuddyStyle.canvas(scheme))
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        .background(BuddyStyle.canvas(scheme)).toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { PageBar(title: "Notes") { dismiss() } }
        .sheet(item: $selection) { DayEditorView(selection: $0) }
    }
    private func card(_ entry: Entry) -> some View {
        Button { selection = DaySelection(habit: entry.habit, day: entry.record.day) } label: {
            HStack(alignment: .top, spacing: 12) {
                HabitIcon(habit: entry.habit, size: 34)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.habit.name).font(BuddyFont.text(14, .semibold)).foregroundStyle(BuddyStyle.text(scheme)).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(entry.record.day.noteTitle).font(BuddyFont.mono(10.5)).foregroundStyle(BuddyStyle.tertiaryText(scheme)).lineLimit(1)
                    }
                    Text(entry.record.note).font(BuddyFont.text(15)).foregroundStyle(BuddyStyle.text(scheme)).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(14).panel(radius: 18, border: 0.09).contentShape(Rectangle())
        }.buttonStyle(FlatButtonStyle()).disabled(entry.habit.archived != nil)
        .accessibilityLabel("\(entry.habit.name), \(entry.record.day.noteTitle): \(entry.record.note)")
    }
}
