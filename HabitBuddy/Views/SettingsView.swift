import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var bytes: Data
    init(bytes: Data) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws { bytes = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: bytes) }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var exporting = false
    @State private var importing = false
    @State private var document: BackupDocument?
    @State private var replacement: Data?
    @State private var restoreDescription = ""
    @State private var confirm = false
    @State private var result: String?
    @State private var backups: [URL] = []
    @State private var categoryName = ""
    @State private var denied = false
    @State private var deleteHabit: Habit?
    private func setting<T>(_ key: WritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(get: { store.data.settings[keyPath: key] }, set: { value in store.change { $0.settings[keyPath: key] = value } })
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    Picker("Theme", selection: setting(\.theme)) { ForEach(Theme.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                    Picker("First day of week", selection: setting(\.weekStart)) { ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) } }
                    Toggle("Outline Today", isOn: setting(\.showToday))
                    Toggle("Day Notes", isOn: setting(\.notes))
                    Toggle("Haptic Feedback", isOn: setting(\.haptics))
                }
                Section("Categories") {
                    ForEach(store.data.categories) { category in
                        HStack { Label(category.name, systemImage: category.symbol); Spacer(); Button("Delete", role: .destructive) { store.change { Engine.deleteCategory(category.id, data: &$0) } }.font(.caption) }
                    }
                    HStack { TextField("New category", text: $categoryName); Button("Add") { let name = categoryName.trimmingCharacters(in: .whitespacesAndNewlines); if store.change({ $0.categories.append(Category(name: name)) }) { categoryName = "" } }.disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
                Section("Overview") {
                    Picker("Default View",selection:setting(\.layout)){Text("Classic").tag(Layout.cards);Text("Compact").tag(Layout.compact);Text("Month").tag(Layout.month)}
                    Stepper("Compact view: \(store.data.settings.recentDays) days", value: setting(\.recentDays), in: 1...7)
                    Toggle("Compact Habit Names",isOn:setting(\.compactNames))
                    Toggle("Layout Switcher",isOn:setting(\.showLayoutSwitcher))
                    Toggle("Category Filter",isOn:setting(\.showCategoryFilter))
                    Toggle("Drag to Reorder",isOn:setting(\.dragToReorder))
                    Toggle("Month Labels",isOn:setting(\.showMonthLabels))
                    Toggle("Weekday Labels",isOn:setting(\.showWeekdayLabels))
                    Toggle("Category Icons",isOn:setting(\.showCategoryIcons))
                    Toggle("Show Descriptions", isOn: setting(\.showDescriptions))
                    Toggle("Show Streak", isOn: setting(\.showStreak))
                    Toggle("Show Goal", isOn: setting(\.showGoal))
                    Toggle("Show Completion Indicator", isOn: setting(\.showCompletionIndicator))
                }
                Section("Daily Check-in") {
                    Toggle("Daily Check-in Reminder", isOn: Binding(get: { store.data.settings.checkIn != nil }, set: { enabled in store.change { $0.settings.checkIn = enabled ? Reminder() : nil }; if enabled { askNotifications() } }))
                    if let reminder = store.data.settings.checkIn {
                        DatePicker("Time", selection: Binding(get: { Calendar.current.date(from: DateComponents(hour: reminder.hour, minute: reminder.minute)) ?? Date() }, set: { date in store.change { $0.settings.checkIn?.hour = Calendar.current.component(.hour, from: date); $0.settings.checkIn?.minute = Calendar.current.component(.minute, from: date) } }), displayedComponents: .hourAndMinute)
                        TextField("Title", text: setting(\.checkInTitle))
                        TextField("Message", text: setting(\.checkInBody))
                    }
                    Button("Enable Notifications") { askNotifications() }
                    if denied { Link("Allow notifications in System Settings", destination: URL(string: UIApplication.openSettingsURLString)!) }
                    let plan = ReminderPlanner.plan(store.data)
                    Text("\(plan.requests.count) scheduled reminders in the next 7 days.\(plan.omittedCount > 0 ? " \(plan.omittedCount) later requests exceed the notification budget; open the app to refresh coverage." : "")").font(.caption).foregroundStyle(.secondary)
                }
                Section("Your Data") {
                    Button("Export JSON Backup", systemImage: "square.and.arrow.up") {
                        do { document = BackupDocument(bytes: try store.repository.export()); exporting = true }
                        catch { result = error.localizedDescription }
                    }
                    Button("Import JSON Backup", systemImage: "square.and.arrow.down") { importing = true }
                    NavigationLink("On-device Backups (\(backups.count))") {
                        List {
                            ForEach(backups, id: \.path) { backup in Button(backup.lastPathComponent) { do { try stage(Data(contentsOf: backup)) } catch { result = error.localizedDescription } } }
                            if backups.isEmpty { Text("Snapshots appear after the first saved day. Up to seven daily snapshots and three before-restore snapshots are kept.").font(.caption).foregroundStyle(.secondary) }
                        }.navigationTitle("Backups")
                    }
                    Text("JSON includes habits, goals, progress, notes, categories, reminders and settings. A validated import replaces the current data after saving a recovery snapshot. Export periodically to protect against phone loss.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Archive") {
                    ForEach(store.data.habits.filter { $0.archived != nil }) { h in
                        HStack { HabitIcon(habit: h, size: 28); Text(h.name); Spacer(); Button("Restore") { store.archive(h.id, restore: true) } }
                        Button("Delete \(h.name) Permanently", role: .destructive) { deleteHabit = h }
                    }
                    if !store.data.habits.contains(where: { $0.archived != nil }) { Text("Archived habits keep their history and appear here.").font(.caption).foregroundStyle(.secondary) }
                }
                Section("Habit Buddy") {
                    Text("Offline. No account. Your habits stay on this device.")
                    Text("iOS 27 · Native SwiftUI").font(.caption).foregroundStyle(.secondary)
                    if !store.sharedStorageAvailable { Text("App Group storage is not configured. The app uses private local storage; widgets and Shortcuts need the shared group. Export your data before changing signing or the App Group.").font(.caption).foregroundStyle(.orange) }
                }
            }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "habit-buddy-\(Day().rawValue)") { outcome in
                    switch outcome { case .success: result = "Backup exported."; case .failure(let error): if (error as NSError).code != NSUserCancelledError { result = error.localizedDescription } }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { outcome in
                    switch outcome {
                    case .success(let url):
                        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        do { try stage(Data(contentsOf: url)) } catch { result = error.localizedDescription }
                    case .failure(let error): if (error as NSError).code != NSUserCancelledError { result = error.localizedDescription }
                    }
                }
                .confirmationDialog("Replace current habit data?", isPresented: $confirm, titleVisibility: .visible) {
                    Button("Replace and Save Recovery Snapshot", role: .destructive) { if let bytes = replacement, store.restore(bytes) { result = "Backup restored."; loadBackups() }; replacement = nil }
                    Button("Cancel", role: .cancel) { replacement = nil }
                } message: { Text(restoreDescription) }
                .confirmationDialog("Permanently delete this habit and all its history?", isPresented: Binding(get: { deleteHabit != nil }, set: { if !$0 { deleteHabit = nil } }), titleVisibility: .visible) {
                    Button("Delete Permanently", role: .destructive) {
                        if let id = deleteHabit?.id { store.change { data in data.habits.removeAll { $0.id == id }; data.records = data.records.filter { $0.value.habitID != id } } }; deleteHabit = nil
                    }
                }
                .alert("Habit Buddy", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) { Button("OK") { result = nil } } message: { Text(result ?? "") }
                .onAppear { loadBackups() }
        }
    }
    private func askNotifications() { Task { do { denied = try await !NotificationService.request(); await NotificationService.reconcile(store.data) } catch { result = error.localizedDescription } } }
    private func loadBackups() { do { backups = try store.repository.backups() } catch { result = error.localizedDescription } }
    private func stage(_ bytes: Data) throws { let data = try DataValidation.decode(bytes); replacement = bytes; restoreDescription = "This backup contains \(data.habits.count) habits and \(data.records.count) day records."; confirm = true }
}

struct ReorderView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(store.data.active) { h in
                    HStack { HabitIcon(habit: h, size: 30); Text(h.name); Spacer(); Button("Move Up", systemImage: "arrow.up") { moveUp(h) }.labelStyle(.iconOnly).disabled(h.id == store.data.active.first?.id) }
                }.onMove { source, destination in
                    var ids = store.data.active.map(\.id); ids.move(fromOffsets: source, toOffset: destination); persist(ids)
                }
            }.environment(\.editMode, .constant(.active)).navigationTitle("Reorder Habits")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func moveUp(_ habit: Habit) { var ids = store.data.active.map(\.id); guard let index = ids.firstIndex(of: habit.id), index > 0 else { return }; ids.swapAt(index, index - 1); persist(ids) }
    private func persist(_ ids: [UUID]) { store.change { data in for (order, id) in ids.enumerated() { if let i = data.habits.firstIndex(where: { $0.id == id }) { data.habits[i].order = order } } } }
}
