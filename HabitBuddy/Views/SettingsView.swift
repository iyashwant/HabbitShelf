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

enum SettingsPage: Hashable { case general, overview, checkIn, theme, categories, archive, data }

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @State private var exporting = false
    @State private var importing = false
    @State private var document: BackupDocument?
    @State private var replacement: Data?
    @State private var restoreDescription = ""
    @State private var confirm = false
    @State private var result: String?
    @State private var backups: [URL] = []
    @State private var categoryName = ""
    @State private var categoryEditor: Category?
    @State private var denied = false
    @State private var deleteHabit: Habit?
    @State private var reorder = false
    private func setting<T>(_ key: WritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(get: { store.data.settings[keyPath: key] }, set: { value in store.change { $0.settings[keyPath: key] = value } })
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsGroup("App") {
                        SettingsLink(page: .general, icon: "settings", color: "pink", title: "General")
                        SettingsLink(page: .overview, icon: "grid-2x2", color: "teal", title: "Overview")
                        SettingsLink(page: .checkIn, icon: "bell", color: "cyan", title: "Daily Check-In Reminders")
                        SettingsLink(page: .theme, icon: "palette", color: "amber", title: "Theme")
                        SettingsLink(page: .categories, icon: "tags", color: "lime", title: "Categories")
                        SettingsLink(page: .archive, icon: "archive", color: "green", title: "Archived Habits")
                        SettingsLink(page: .data, icon: "file-input", color: "indigo", title: "Data Import/Export")
                        SettingsRow(icon: "list", color: "coral", title: "Reorder Habits") { reorder = true }
                    }
                    SettingsGroup("Help") {
                        SettingsRow(icon: "ship", color: "orange", title: "Show Onboarding") { dismiss(); store.change { $0.settings.onboarding = false } }
                        SettingsRow(icon: "send", color: "gray", title: "Send Feedback") { openURL(URL(string: "https://github.com/iyashwant/habbit-buddy/issues")!) }
                    }
                    SettingsGroup("About") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Habit Buddy").font(BuddyFont.text(16, .semibold))
                            Text("Offline. No account. Your habits stay on this device.").font(BuddyFont.text(13)).foregroundStyle(BuddyStyle.secondaryText(scheme))
                            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") · iOS 27 · Native SwiftUI").font(BuddyFont.mono(11)).foregroundStyle(BuddyStyle.tertiaryText(scheme))
                            if !store.sharedStorageAvailable { Text("App Group storage is not configured. The app uses private local storage; widgets and Shortcuts need the shared group. Export your data before changing signing or the App Group.").font(BuddyFont.text(12)).foregroundStyle(.orange) }
                        }.padding(.horizontal, 20).padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(.horizontal, 8).padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(BuddyStyle.canvas(scheme))
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { SheetHeader(title: "Settings").background(BuddyStyle.canvas(scheme).opacity(0.94)) }
            .navigationDestination(for: SettingsPage.self) { page in self.page(page) }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "habit-buddy-\(Day().rawValue)") { outcome in
                switch outcome { case .success: result = "Backup exported."; case .failure(let error): if (error as NSError).code != NSUserCancelledError { result = error.localizedDescription } }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { outcome in
                switch outcome {
                case .success(let url): stage(url, scoped: true)
                case .failure(let error): if (error as NSError).code != NSUserCancelledError { result = error.localizedDescription }
                }
            }
            .confirmationDialog("Replace current habit data?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Replace and Save Recovery Snapshot", role: .destructive) {
                    if let bytes = replacement { Task { if await store.restore(bytes) { result = "Backup restored."; loadBackups() } } }
                    replacement = nil
                }
                Button("Cancel", role: .cancel) { replacement = nil }
            } message: { Text(restoreDescription) }
            .confirmationDialog("Permanently delete this habit and all its history?", isPresented: Binding(get: { deleteHabit != nil }, set: { if !$0 { deleteHabit = nil } }), titleVisibility: .visible) {
                Button("Delete Permanently", role: .destructive) {
                    if let id = deleteHabit?.id { store.change { Engine.deleteHabit(id, data: &$0) } }; deleteHabit = nil
                }
            }
            .alert("Habit Buddy", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) { Button("OK") { result = nil } } message: { Text(result ?? "") }
            .sheet(item:$categoryEditor){CategoryEditorView(category:$0).buddySheet()}
            .sheet(isPresented: $reorder) { ReorderView() }
            .onAppear { loadBackups() }
        }
    }
    @ViewBuilder private func page(_ page: SettingsPage) -> some View {
        switch page {
        case .general:
            SettingsPageView(title: "General") {
                SettingsGroup {
                    SettingsMenu(title: "First Day of Week", value: Calendar.current.weekdaySymbols[store.data.settings.weekStart - 1]) { ForEach(1...7, id: \.self) { d in Button(Calendar.current.weekdaySymbols[d - 1]) { setting(\.weekStart).wrappedValue = d } } }
                    SettingsToggle(title: "Outline Today", isOn: setting(\.showToday))
                    SettingsToggle(title: "Day Notes", isOn: setting(\.notes))
                    SettingsToggle(title: "Haptic Feedback", isOn: setting(\.haptics))
                    SettingsMenu(title: "Streak Freezes", value: store.data.settings.freezesPerMonth == 0 ? "Off" : "\(store.data.settings.freezesPerMonth) a month") {
                        Button("Off") { setting(\.freezesPerMonth).wrappedValue = 0 }
                        ForEach(1...3, id: \.self) { n in Button("\(n) a month") { setting(\.freezesPerMonth).wrappedValue = n } }
                    }
                }
                SettingsNote("A streak freeze protects a daily streak from one missed day. Press and hold a missed day, choose Edit Progress, then turn on Freeze Streak. Frozen days still count as missed in completion rates.")
            }
        case .overview:
            SettingsPageView(title: "Overview") {
                SettingsGroup("Layout") {
                    SettingsMenu(title: "Default View", value: store.data.settings.layout.title) {
                        ForEach(Layout.allCases, id: \.self) { layout in Button(layout.title) { setting(\.layout).wrappedValue = layout } }
                    }
                    SettingsStepper(title: "Compact View Days", value: setting(\.recentDays), range: 1...7)
                    SettingsToggle(title: "Compact Habit Names", isOn: setting(\.compactNames))
                    SettingsToggle(title: "Layout Switcher", isOn: setting(\.showLayoutSwitcher))
                    SettingsToggle(title: "Category Filter", isOn: setting(\.showCategoryFilter))
                    SettingsToggle(title: "Drag to Reorder", isOn: setting(\.dragToReorder))
                }
                SettingsGroup("Habit Cards") {
                    SettingsToggle(title: "Month Labels", isOn: setting(\.showMonthLabels))
                    SettingsToggle(title: "Weekday Labels", isOn: setting(\.showWeekdayLabels))
                    SettingsToggle(title: "Category Icons", isOn: setting(\.showCategoryIcons))
                    SettingsToggle(title: "Show Descriptions", isOn: setting(\.showDescriptions))
                    SettingsToggle(title: "Show Streak", isOn: setting(\.showStreak))
                    SettingsToggle(title: "Show Goal", isOn: setting(\.showGoal))
                    SettingsToggle(title: "Completion Indicator", isOn: setting(\.showCompletionIndicator))
                }
            }
        case .checkIn:
            SettingsPageView(title: "Daily Check-In") {
                SettingsGroup {
                    SettingsToggle(title: "Daily Check-In Reminder", isOn: Binding(get: { store.data.settings.checkIn != nil }, set: { enabled in store.change { $0.settings.checkIn = enabled ? Reminder() : nil }; if enabled { askNotifications() } }))
                    if let reminder = store.data.settings.checkIn {
                        SettingsLine { DatePicker("Time", selection: Binding(get: { Calendar.current.date(from: DateComponents(hour: reminder.hour, minute: reminder.minute)) ?? Date() }, set: { date in store.change { $0.settings.checkIn?.hour = Calendar.current.component(.hour, from: date); $0.settings.checkIn?.minute = Calendar.current.component(.minute, from: date) } }), displayedComponents: .hourAndMinute) }
                        SettingsLine { DraftField(title: "Title", saved: store.data.settings.checkInTitle) { text in store.change { $0.settings.checkInTitle = text } } }
                        SettingsLine { DraftField(title: "Message", saved: store.data.settings.checkInBody) { text in store.change { $0.settings.checkInBody = text } } }
                    }
                    SettingsToggle(title: "Weekly Recap Reminder", isOn: Binding(get: { store.data.settings.recapReminder }, set: { enabled in store.change { $0.settings.recapReminder = enabled }; if enabled { askNotifications() } }))
                    SettingsRow(icon: "bell-ring", color: "cyan", title: "Enable Notifications") { askNotifications() }
                    if denied { SettingsRow(icon: "settings", color: "gray", title: "Allow in System Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) } }
                }
                let plan = ReminderPlanner.plan(store.data)
                SettingsNote("\(plan.requests.count) scheduled reminders in the next 7 days.\(plan.omittedCount > 0 ? " \(plan.omittedCount) later requests exceed the notification budget; open the app to refresh coverage." : "")")
            }
        case .theme:
            SettingsPageView(title: "Theme") {
                SettingsGroup {
                    ForEach(Theme.allCases, id: \.self) { theme in
                        SettingsRow(icon: theme == .system ? "smartphone" : theme == .light ? "sun" : "moon", color: theme == .dark ? "indigo" : theme == .light ? "amber" : "gray", title: theme.rawValue.capitalized, chevron: false, selected: store.data.settings.theme == theme) { setting(\.theme).wrappedValue = theme }
                    }
                }
                SettingsNote("System follows your iPhone's appearance.")
            }
        case .categories:
            SettingsPageView(title: "Categories") {
                SettingsGroup {
                    ForEach(store.data.categories) { category in
                        SettingsLine {
                            Button { categoryEditor = category } label: { HStack(spacing: 10) { BuddyGlyph(symbol: category.symbol, size: 18); Text(category.name) }.contentShape(Rectangle()) }.buttonStyle(.plain)
                            Spacer()
                            Button("Delete", role: .destructive) { store.change { Engine.deleteCategory(category.id, data: &$0) } }.font(BuddyFont.text(13))
                        }
                    }
                    SettingsLine {
                        TextField("New category", text: $categoryName)
                        Button("Add") { let category = Category(name: categoryName.trimmingCharacters(in: .whitespacesAndNewlines)); if store.change({ $0.categories.append(category) }) { categoryName = "" } }.disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).tint(BuddyStyle.purple)
                    }
                }
            }
        case .archive:
            SettingsPageView(title: "Archived Habits") {
                let archived = store.data.habits.filter { $0.archived != nil }
                if archived.isEmpty { SettingsNote("Archived habits keep their history and appear here.") }
                else {
                    SettingsGroup {
                        ForEach(archived) { h in
                            SettingsLine { HabitIcon(habit: h, size: 34); Text(h.name); Spacer(); Button("Restore") { store.archive(h.id, restore: true) }.tint(BuddyStyle.purple) }
                            SettingsLine { Button("Delete \(h.name) Permanently", role: .destructive) { deleteHabit = h } }
                        }
                    }
                }
            }
        case .data:
            SettingsPageView(title: "Data Import/Export") {
                SettingsGroup {
                    SettingsRow(icon: "file-output", color: "indigo", title: "Export JSON Backup") {
                        Task {
                            do { document = BackupDocument(bytes: try await store.export()); exporting = true }
                            catch { result = error.localizedDescription }
                        }
                    }
                    SettingsRow(icon: "file-input", color: "blue", title: "Import JSON Backup") { importing = true }
                }
                SettingsNote("JSON includes habits, goals, progress, notes, categories, reminders and settings. A validated import replaces the current data after saving a recovery snapshot. Export periodically to protect against phone loss.")
                SettingsGroup("On-device Backups (\(backups.count))") {
                    ForEach(backups, id: \.path) { backup in SettingsRow(icon: "clock", color: "gray", title: backup.lastPathComponent) { stage(backup, scoped: false) } }
                    if backups.isEmpty { Text("Snapshots appear after the first saved day. Up to seven daily snapshots and three before-restore snapshots are kept.").font(BuddyFont.text(13)).foregroundStyle(BuddyStyle.secondaryText(scheme)).padding(16) }
                }
            }
        }
    }
    private func askNotifications() { Task { do { denied = try await !NotificationService.request(); await NotificationService.reconcile(store.data) } catch { result = error.localizedDescription } } }
    private func loadBackups() { Task { do { backups = try await store.backups() } catch { result = error.localizedDescription } } }
    /// Reads and validates a backup off the main thread, then asks before replacing anything.
    private func stage(_ url: URL, scoped: Bool) {
        Task {
            do {
                let (bytes, data) = try await Task.detached(priority: .userInitiated) {
                    let access = scoped && url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let bytes = try DataValidation.read(url)
                    return (bytes, try DataValidation.decode(bytes))
                }.value
                replacement = bytes; restoreDescription = "This backup contains \(data.habits.count) habits and \(data.records.count) day records."; confirm = true
            } catch { result = error.localizedDescription }
        }
    }
}

/// A settings sub-page: back control, centered title and grouped rows.
struct SettingsPageView<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 0) { content() }.padding(.horizontal, 8).padding(.bottom, 40) }
            .scrollIndicators(.hidden)
            .background(BuddyStyle.canvas(scheme)).toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                ZStack {
                    Text(title).font(BuddyFont.text(20, .bold)).tracking(1.7).foregroundStyle(BuddyStyle.text(scheme)).lineLimit(1).padding(.horizontal, 56)
                    HStack { CircleControl(symbol: "chevron-left", label: "Back", size: 38, glyph: 16) { dismiss() }; Spacer() }
                }.padding(.horizontal, 12).padding(.top, 25).padding(.bottom, 10).background(BuddyStyle.canvas(scheme).opacity(0.94))
            }
    }
}
/// Uppercase caption above a bordered group whose rows are separated by hairlines.
struct SettingsGroup<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    var title: String?
    @ViewBuilder var content: () -> Content
    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }
    var body: some View {
        VStack(alignment: .leading, spacing: 9.6) {
            if let title { Text(title).fieldCaption().tracking(2.3).foregroundStyle(BuddyStyle.secondaryText(scheme)).padding(.leading, 5.7) }
            VStack(spacing: 0) {
                Group(subviews: content()) { rows in
                    ForEach(rows) { row in row; if row.id != rows.last?.id { BuddyStyle.divider(scheme).frame(height: 1) } }
                }
            }.panel(radius: 20, border: 0.125).clipShape(RoundedRectangle(cornerRadius: 20, style: .circular))
        }.padding(.top, title == nil ? 14 : 26.5)
    }
}
struct SettingsTile: View {
    let icon: String
    let color: String
    var body: some View { LucideIcon(icon, size: 18.5).foregroundStyle(BuddyStyle.color(color)).frame(width: 34, height: 34).background(BuddyStyle.color(color).opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .circular)) }
}
struct SettingsRow: View {
    @Environment(\.colorScheme) private var scheme
    let icon: String
    let color: String
    let title: String
    var chevron = true
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) { SettingsRowLabel(icon: icon, color: color, title: title, chevron: chevron, selected: selected) }.buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
struct SettingsLink: View {
    let page: SettingsPage
    let icon: String
    let color: String
    let title: String
    var body: some View { NavigationLink(value: page) { SettingsRowLabel(icon: icon, color: color, title: title) }.buttonStyle(.plain) }
}
struct SettingsRowLabel: View {
    @Environment(\.colorScheme) private var scheme
    let icon: String
    let color: String
    let title: String
    var chevron = true
    var selected = false
    var body: some View {
        HStack(spacing: 12.3) {
            SettingsTile(icon: icon, color: color)
            Text(title).font(BuddyFont.text(16)).foregroundStyle(BuddyStyle.text(scheme)).lineLimit(1)
            Spacer(minLength: 8)
            if selected { LucideIcon("check", size: 18).foregroundStyle(BuddyStyle.purple) }
            if chevron { LucideIcon("chevron-right", size: 15).foregroundStyle(Color(hex: scheme == .dark ? 0x6C6C70 : 0xA0A0A6)) }
        }.padding(.leading, 18).padding(.trailing, 19.4).frame(height: 53).contentShape(Rectangle())
    }
}
/// A plain settings row for custom controls.
struct SettingsLine<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: () -> Content
    var body: some View { HStack(spacing: 10) { content() }.font(BuddyFont.text(16)).foregroundStyle(BuddyStyle.text(scheme)).tint(BuddyStyle.purple).padding(.horizontal, 20).frame(minHeight: 53) }
}
/// Text saved when editing ends (Return, leaving the field or the page), not on every keystroke.
struct DraftField: View {
    let title: String
    let saved: String
    var commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        TextField(title, text: $text).focused($focused)
            .onAppear { text = saved }
            .onChange(of: saved) { _, value in if !focused { text = value } }
            .onChange(of: focused) { _, now in if !now { save() } }
            .onSubmit(save).onDisappear(perform: save)
    }
    private func save() { if text != saved { commit(text) } }
}
struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View { SettingsLine { Toggle(title, isOn: $isOn) } }
}
struct SettingsStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var body: some View { SettingsLine { Stepper(value: $value, in: range) { HStack { Text(title); Spacer(); Text("\(value)").font(BuddyFont.mono(14)) } } } }
}
struct SettingsMenu<Items: View>: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let value: String
    @ViewBuilder var items: () -> Items
    var body: some View {
        SettingsLine { Text(title); Spacer(); Menu { items() } label: { HStack(spacing: 6) { Text(value).font(BuddyFont.text(15)); LucideIcon("chevrons-up-down", size: 14) }.foregroundStyle(BuddyStyle.secondaryText(scheme)) } }
    }
}
struct SettingsNote: View {
    @Environment(\.colorScheme) private var scheme
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(BuddyFont.text(12.5)).foregroundStyle(BuddyStyle.tertiaryText(scheme)).padding(.horizontal, 12).padding(.top, 10) }
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


struct CategoryEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State var category: Category
    @State private var icons=false
    var body: some View {
        VStack(spacing:20) {
            SheetHeader(title:"Edit Category")
            Button { icons=true } label: { BuddyGlyph(symbol:category.symbol,size:36).foregroundStyle(BuddyStyle.purple).frame(width:88,height:88).background(BuddyStyle.purple.opacity(0.13),in:Circle()) }.buttonStyle(.plain).accessibilityLabel("Choose Category Icon")
            TextField("Category name",text:$category.name).padding(14).background(Color.primary.opacity(0.06),in:RoundedRectangle(cornerRadius:14))
            Spacer()
            PrimaryAction(title:"Save") {
                category.name=category.name.trimmingCharacters(in:.whitespacesAndNewlines)
                let saved=category
                if store.change({data in if let i=data.categories.firstIndex(where:{$0.id==saved.id}){data.categories[i]=saved}}){dismiss()}
            }.disabled(category.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        }.padding(20).background(BuddyStyle.canvas(scheme)).sheet(isPresented:$icons){IconPickerView(selection:$category.symbol,color:BuddyStyle.purple)}
    }
}

extension Layout {
    var title: String { switch self { case .cards: "Classic"; case .compact: "Compact"; case .month: "Month"; case .streaks: "Streaks"; case .list: "List" } }
}
