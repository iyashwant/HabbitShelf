import SwiftUI

/// Every day note across habits, newest first and grouped by month, with search and a habit filter.
struct NotesTimelineView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @State private var habit: UUID?
    @State private var selection: DaySelection?
    /// Every note, newest first, built off the main thread whenever the data changes.
    @State private var index: NoteIndex?
    /// The notes matching the search and filter, grouped by month.
    @State private var results: [(month: String, items: [Entry])] = []
    @State private var resultCount = 0
    struct Entry: Identifiable, Sendable { let habitID: UUID; let day: Day; let note: String; let name: String; let order: Int; var id: String { Record.keyPrefix(habitID) + day.rawValue } }
    struct NoteIndex: Sendable {
        var revision: Int
        var entries: [Entry]
        var habitIDs: Set<UUID>
        init(_ data: BuddyData, revision: Int) {
            self.revision = revision
            let habits = Dictionary(data.habits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            entries = data.records.values.compactMap { record in
                guard !record.note.isEmpty, let habit = habits[record.habitID] else { return nil }
                return Entry(habitID: habit.id, day: record.day, note: record.note, name: habit.name, order: habit.order)
            }.sorted { $0.day == $1.day ? $0.order < $1.order : $0.day > $1.day }
            habitIDs = Set(entries.map(\.habitID))
        }
    }
    /// A search waits briefly for typing to pause; a newer search cancels it.
    private struct Search: Equatable { var query: String; var habit: UUID?; var revision: Int? }
    var body: some View {
        let habits = Dictionary(store.visible.habits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let withNotes = store.visible.habits.filter { index?.habitIDs.contains($0.id) ?? false }.sorted { $0.order < $1.order }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                HStack(spacing: 8) {
                    LucideIcon("search", size: 17).foregroundStyle(BuddyStyle.secondaryText(scheme))
                    TextField("Search notes", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel("Search notes")
                    if !query.isEmpty { Button { query = "" } label: { LucideIcon("x", size: 15) }.buttonStyle(.plain).foregroundStyle(BuddyStyle.secondaryText(scheme)).accessibilityLabel("Clear search") }
                }.buddyField()
                if withNotes.count > 1 { HabitFilterBar(habits: withNotes, selection: $habit) }
                if let index {
                    if index.entries.isEmpty {
                        ContentUnavailableView("No notes yet", systemImage: "note.text", description: Text("Press and hold a day in a habit's calendar to add a note. Every note appears here."))
                    } else if resultCount == 0 {
                        ContentUnavailableView.search(text: text)
                    } else {
                        Text("\(resultCount) \(resultCount == 1 ? "note" : "notes")").font(BuddyFont.mono(11)).tracking(1).foregroundStyle(BuddyStyle.tertiaryText(scheme)).padding(.leading, 4)
                    }
                }
                ForEach(results, id: \.month) { month, items in
                    Section {
                        ForEach(items) { entry in if let habit = habits[entry.habitID] { card(entry, habit) } }
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
        .task(id: store.revision) {
            let data = store.visible, revision = store.revision
            if let value = await offMain({ NoteIndex(data, revision: revision) }) { index = value }
        }
        .task(id: Search(query: text, habit: habit, revision: index?.revision)) { await search(text) }
    }
    private func search(_ text: String) async {
        guard let entries = index?.entries else { return }
        // Typing waits for a pause; clearing the field or changing the filter shows results at once.
        if !text.isEmpty { try? await Task.sleep(for: .milliseconds(120)) }
        guard !Task.isCancelled else { return }
        let habit = habit
        guard let matches = await offMain({ () -> [Entry] in
            entries.filter { (habit == nil || $0.habitID == habit) && (text.isEmpty || $0.note.localizedCaseInsensitiveContains(text) || $0.name.localizedCaseInsensitiveContains(text)) }
        }) else { return }
        // Entries are already newest first, so months come out in order.
        var grouped: [(month: String, items: [Entry])] = []
        for entry in matches {
            let month = entry.day.month
            if grouped.last?.month == month { grouped[grouped.count - 1].items.append(entry) } else { grouped.append((month, [entry])) }
        }
        results = grouped; resultCount = matches.count
    }
    private func card(_ entry: Entry, _ habit: Habit) -> some View {
        Button { selection = DaySelection(habit: habit, day: entry.day) } label: {
            HStack(alignment: .top, spacing: 12) {
                HabitIcon(habit: habit, size: 34)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(habit.name).font(BuddyFont.text(14, .semibold)).foregroundStyle(BuddyStyle.text(scheme)).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(entry.day.noteTitle).font(BuddyFont.mono(10.5)).foregroundStyle(BuddyStyle.tertiaryText(scheme)).lineLimit(1)
                    }
                    Text(entry.note).font(BuddyFont.text(15)).foregroundStyle(BuddyStyle.text(scheme)).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(14).panel(radius: 18, border: 0.09).contentShape(Rectangle())
        }.buttonStyle(FlatButtonStyle()).disabled(habit.archived != nil)
        .accessibilityLabel("\(habit.name), \(entry.day.noteTitle): \(entry.note)")
    }
}
