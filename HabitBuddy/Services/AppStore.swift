import Observation
import SwiftUI
import WidgetKit
import os

/// The app's habit data. Changes show at once; saving runs in order on a background queue, so file locks,
/// reads, validation and writes never hold up a tap. If a save fails, its change is undone and reported.
///
/// Views redraw only for the properties they read: a screen that reads `settings` alone doesn't redraw for a
/// check-in, and one that reads `data` redraws for every change.
@MainActor @Observable final class AppStore {
    /// What the screens show: the latest saved snapshot with any changes still being saved applied on top.
    /// Set only through `publish`, which records which habits changed. Observed by hand: Observation's own setter
    /// compares the old and new snapshots, reading every record.
    var data: BuddyData { access(keyPath: \.data); return snapshot }
    @ObservationIgnored private var snapshot = BuddyData()
    /// `data.settings`, replaced only when the settings change.
    private(set) var settings = BuddyData().settings
    var error: String?
    var loaded = false
    /// True until the first read from disk finishes, so launch shows neither onboarding nor an empty list early.
    private(set) var loading = true
    var sharedStorageAvailable = AppEnvironment.hasSharedContainer
    /// Increases with every published snapshot. Screens key background work on it instead of comparing snapshots.
    private(set) var revision = 0
    /// `data` as the screens show it: hidden habits and their days left out. Worked out once per snapshot,
    /// on first use. Lists and summaries read it; changes still go through `change`, against the full data.
    var visible: BuddyData {
        if visibleRevision != revision { visibleData = data.withoutHidden; visibleRevision = revision }
        return visibleData
    }
    @ObservationIgnored private var visibleData = BuddyData()
    @ObservationIgnored private var visibleRevision = -1
    /// Streaks, stats and milestones per habit, worked out in the background (see `HabitSummaries`).
    let summaries = HabitSummaries(caching: true)
    let repository = AppEnvironment.repository
    private let worker: PersistenceWorker
    /// The latest snapshot read from or written to disk.
    @ObservationIgnored private var committed = BuddyData()
    /// Changes shown but not yet saved, oldest first, with the habits whose days each one edits (nil if unknown).
    @ObservationIgnored private var pending: [(id: Int, habits: Set<UUID>?, change: Change)] = []
    @ObservationIgnored private var nextChange = 0
    /// What the saved changes touched since the screen last took a saved snapshot, which it does when the queue drains.
    @ObservationIgnored private var savedHabits: Set<UUID>? = []
    @ObservationIgnored private var savedElsewhere = false
    /// Counts changes per habit, and for every habit at once (`allVersion`) when a change can't tell which it touched.
    /// Views read them through `version(_:)`, so a habit's views redraw when its summary arrives too.
    private var habitVersions: [UUID: Int] = [:]
    private var allVersion = 0
    @ObservationIgnored private var syncScope: SyncScope = []
    /// The habits whose widgets the changes since the last sync may alter, or nil when any may.
    @ObservationIgnored private var syncHabits: Set<UUID>? = []
    @ObservationIgnored private var sync: Task<Void, Never>?
    @ObservationIgnored private var syncPending = false
    @ObservationIgnored private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    @ObservationIgnored private var summaryRefresh: Task<Void, Never>?
    @ObservationIgnored private var summaryRefreshQueued = false
    /// From launch until the habits first show, as a "First load" interval in Instruments' os_signpost track.
    @ObservationIgnored private var firstLoad: OSSignpostIntervalState?
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    /// A change runs twice: on the screen's snapshot now, then on the latest saved snapshot on the persistence
    /// queue. Capture values (not `@State` or other view state), and decide from the `data` it is given.
    typealias Change = (inout BuddyData) throws -> Void
    init() {
        worker = PersistenceWorker(repository)
        haptic.prepare()
        summaries.onStale = { [weak self] in self?.scheduleSummaryRefresh() }
        #if DEBUG
        if let screen=ProcessInfo.processInfo.environment["BUDDY_VISUAL_SCREEN"],ProcessInfo.processInfo.environment["BUDDY_VISUAL_RESET"] != "false" {
            do { committed=try repository.transaction{$0=VisualSamples.audit(screen)};publish(committed,everything:true);loaded=true } catch { self.error=error.localizedDescription }
            loading=false
            return
        }
        #endif
        firstLoad = Self.interactions.beginInterval("First load")
        reload()
    }
    /// Reads the latest saved data, after any queued saves, keeping changes that are still being saved.
    /// `reschedule` then refreshes reminders from it, as when the app returns to the foreground.
    func reload(reschedule: Bool = false) {
        worker.load(summarize: !loaded) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let saved):
                committed = saved.data
                let first = !loaded
                // An unchanged file redraws nothing; one written by a widget or Shortcut redraws every habit.
                publish(rebased(), touched: [], everything: saved.changedElsewhere || first); loaded = true
                if let results = saved.summaries { summaries.install(results, for: Set(results.keys), today: Day()) }
                else if first { prefetchSummaries() }
                if first, let interval = firstLoad {
                    firstLoad = nil
                    DispatchQueue.main.async { Self.interactions.endInterval("First load", interval) }
                }
                if reschedule { Task { await NotificationService.reconcile(saved.data) } }
            case .failure(let failure): error = failure.localizedDescription; loaded = false
            }
            loading = false
        }
    }
    /// Applies a change now and queues it to be saved. Returns false, changing nothing, if it is invalid.
    /// `touching` names the habits whose days it edits, so only they redraw; leave it out when unsure.
    @discardableResult func change(touching habits: Set<UUID>? = nil, _ block: @escaping Change) -> Bool {
        apply(block, habits: habits, validate: true)
    }
    /// A check-in through the shared engine, which checks every value it writes. The full check of all records
    /// waits for the save on the persistence queue instead of holding up the tap. Only `habits` redraw.
    @discardableResult func log(_ habits: Set<UUID>, _ block: @escaping Change) -> Bool {
        apply(block, habits: habits, validate: false)
    }
    private func apply(_ block: @escaping Change, habits: Set<UUID>?, validate: Bool) -> Bool {
        guard loaded else { error = loading ? "Your habits are still loading. Try again in a moment." : "Data could not be loaded. Restore a backup before making changes."; return false }
        var next = data
        do { try block(&next); if validate { try DataValidation.validate(next) } }
        catch { self.error = error.localizedDescription; return false }
        let scope = SyncScope(from: data, to: next)
        syncScope.formUnion(scope)
        if scope.contains(.widgets) { syncHabits = Self.widgetHabits(from: data, to: next, touched: habits).flatMap { habits in syncHabits?.union(habits) } }
        let id = nextChange
        nextChange += 1
        pending.append((id, habits, block))
        publish(next, touched: habits)
        worker.save(block) { [weak self] result in self?.saved(id, result) }
        return true
    }
    private func saved(_ id: Int, _ result: Result<PersistenceWorker.Snapshot, Error>) {
        let habits = pending.first { $0.id == id }?.habits
        pending.removeAll { $0.id == id }
        switch result {
        case .success(let saved):
            committed = saved.data
            if let touched = savedHabits, let habits { savedHabits = touched.union(habits) } else { savedHabits = nil }
            savedElsewhere = savedElsewhere || saved.changedElsewhere
            // During a burst of taps the screen already shows every queued change; it takes the saved data once they
            // finish. The habits they touched redraw from it, and every habit does if another process wrote too.
            if pending.isEmpty {
                publish(saved.data, touched: savedHabits, everything: savedElsewhere)
                savedHabits = []; savedElsewhere = false
            }
            scheduleSync()
        case .failure(let failure):
            error = failure.localizedDescription
            publish(rebased(), everything: true)
        }
        endBackgroundTaskIfIdle()
    }
    /// Shows a snapshot. A habit redraws when its days (`touched`) or definition changed; with `touched` nil every
    /// record is compared. Every habit redraws for `everything`, or when settings, categories or routines changed.
    private func publish(_ next: BuddyData, touched: Set<UUID>? = nil, everything: Bool = false) {
        if !everything, let habits = Self.changedHabits(from: data, to: next, touched: touched) {
            for id in habits { habitVersions[id, default: 0] &+= 1 }
            summaries.invalidate(habits)
        } else {
            allVersion &+= 1
            summaries.reset()
        }
        if settings != next.settings { settings = next.settings }
        withMutation(keyPath: \.data) { snapshot = next }
        revision &+= 1
        if !summaries.staleHabits.isEmpty { scheduleSummaryRefresh() }
    }
    /// Works out stale summaries off the main thread once the current update finishes. Their views keep the previous
    /// results until then, and redraw when the new ones arrive.
    private func scheduleSummaryRefresh() {
        guard !summaryRefreshQueued else { return }
        summaryRefreshQueued = true
        // Not during a view update, where a summary read may ask for this.
        Task { [weak self] in self?.refreshSummaries() }
    }
    /// After launch, works out the summaries the first screen didn't need, for the screens opened next.
    private func prefetchSummaries() {
        let snapshot = data, revision = revision, today = Day(), habits = Set(snapshot.active.map(\.id))
        Task { [weak self] in
            // Results from an older snapshot could be out of date, and the screens work out what they need anyway.
            guard let results = await offMain(priority: .utility, { HabitSummaries.compute(habits, data: snapshot, today: today) }), let self, self.revision == revision else { return }
            summaries.fill(results, today: today)
        }
    }
    private func refreshSummaries() {
        summaryRefreshQueued = false
        let habits = summaries.staleHabits
        guard !habits.isEmpty else { return }
        summaryRefresh?.cancel()
        let snapshot = data, revision = revision, today = Day()
        summaryRefresh = Task { [weak self] in
            guard let results = await offMain({ HabitSummaries.compute(habits, data: snapshot, today: today) }), let self else { return }
            // A newer snapshot came out meanwhile: work them out again from it.
            guard self.revision == revision else { scheduleSummaryRefresh(); return }
            summaries.install(results, for: habits, today: today)
            for id in habits { habitVersions[id, default: 0] &+= 1 }
        }
    }
    /// The habits whose definition or days differ, or nil when every habit may have. Collections a change left
    /// alone still share storage with the old snapshot, so comparing them is immediate.
    private static func changedHabits(from old: BuddyData, to new: BuddyData, touched: Set<UUID>?) -> Set<UUID>? {
        guard old.settings == new.settings, old.categories == new.categories, old.routines == new.routines else { return nil }
        if touched == nil && old.records != new.records { return nil }
        var habits = touched ?? []
        if old.habits != new.habits {
            let before = Dictionary(old.habits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for habit in new.habits where before[habit.id] != habit { habits.insert(habit.id) }
        }
        return habits
    }
    /// The habits whose widgets a change may alter, or nil when any may. Adding, removing or reordering habits
    /// changes what a widget showing every habit lists, so it counts as any.
    private static func widgetHabits(from old: BuddyData, to new: BuddyData, touched: Set<UUID>?) -> Set<UUID>? {
        guard let habits = changedHabits(from: old, to: new, touched: touched) else { return nil }
        if old.habits != new.habits && !old.habits.map(\.id).elementsEqual(new.habits.map(\.id)) { return nil }
        return habits
    }
    /// Changes when the habit or its days change on screen. Views compare it to skip redrawing for other habits' changes.
    func version(_ id: UUID) -> HabitVersion { HabitVersion(all: allVersion, habit: habitVersions[id, default: 0]) }
    /// The saved snapshot with the changes still being saved applied again; one that no longer applies is left out.
    private func rebased() -> BuddyData {
        var value = committed
        for item in pending {
            var attempt = value
            if (try? item.change(&attempt)) != nil { value = attempt }
        }
        return value
    }
    /// Widget reloads and notification rescheduling run once after a burst of saves, never concurrently.
    private func scheduleSync(delay: Duration = .milliseconds(350)) {
        guard !syncScope.isEmpty else { return }
        let previous = sync
        previous?.cancel()
        syncPending = true
        sync = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await previous?.value
            guard let self else { return }
            let scope = syncScope, habits = syncHabits
            syncScope = []; syncHabits = []; syncPending = false
            await AppEnvironment.changed(committed, scope: scope, habits: habits)
            endBackgroundTaskIfIdle()
        }
    }
    /// Leaving the app must not strand a queued save, widget reload or reminder update.
    func flushSync() {
        if syncPending { scheduleSync(delay: .zero) }
        guard !pending.isEmpty || syncPending, backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save habits") { [weak self] in self?.endBackgroundTask() }
    }
    private func endBackgroundTaskIfIdle() { if pending.isEmpty && !syncPending { endBackgroundTask() } }
    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
    func habit(_ id: UUID) -> Habit? { data.habits.first { $0.id == id } }
    @discardableResult func setAmount(_ value: Int64, _ id: UUID, _ day: Day) -> Bool {
        log([id]) { try Engine.setAmount(value, habitID: id, day: day, data: &$0) }
    }
    /// Each check-in tap shows in Instruments' os_signpost track as a "Check-in" interval, from the tap until the main
    /// thread has run the screen update that shows it. `PerformanceUITests` measures it.
    private static let interactions = OSSignposter(subsystem: "com.iyashwant.habbitbuddy", category: "Interaction")
    /// A yes/no habit toggles and a count adds one, judged from the latest saved amount when it is saved.
    @discardableResult func quickLog(_ habit: Habit, day: Day = Day()) -> Bool {
        let interval = Self.interactions.beginInterval("Check-in")
        // Runs once the run loop has finished this turn, including SwiftUI's update and the commit to the screen.
        defer { DispatchQueue.main.async { Self.interactions.endInterval("Check-in", interval) } }
        let id = habit.id
        let result = withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .snappy(duration: 0.22)) {
            log([id]) { data in
                guard let current = data.habits.first(where: { $0.id == id }) else { throw BuddyError.unavailable }
                if current.goal(on: day).tracking == .yesNo { try Engine.setAmount(data.record(id, day).amount == 0 ? 1_000 : 0, habitID: id, day: day, data: &data) }
                else { try Engine.increment(habitID: id, day: day, data: &data) }
            }
        }
        // The change shows at once, so the tap's feedback no longer waits for the file to be saved.
        if result && data.settings.haptics { haptic.impactOccurred(); haptic.prepare() }
        return result
    }
    func archive(_ id: UUID, restore: Bool = false) {
        change { data in
            if let i = data.habits.firstIndex(where: { $0.id == id }) {
                if restore, let start = data.habits[i].archived?.adding(1), start < Day() {
                    data.habits[i].pauses.append(Pause(from: start, through: Day().adding(-1)))
                }
                data.habits[i].archived = restore ? nil : Day()
            }
        }
    }
    /// Replaces everything with a validated backup, after the queued saves.
    func restore(_ bytes: Data) async -> Bool {
        do {
            committed = try await worker.replace { try $0.restore(bytes) } ?? committed
            publish(rebased(), everything: true); loaded = true
            syncScope = .all; syncHabits = nil; scheduleSync(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    /// Logs a running timer once, even if the Live Activity's Finish runs at the same time.
    /// True once the session is logged or was already finished elsewhere.
    func finishTimer(_ session: TimerSession, at now: Date) async -> Bool {
        do {
            guard let value = try await worker.replace({ try TimerSessions.finish(session, repository: $0, at: now) }) else { return true }
            committed = value; publish(rebased(), everything: true)
            syncScope = .all; syncHabits = syncHabits?.union([session.habitID]); scheduleSync(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func export() async throws -> Data { try await worker.run { try $0.export() } }
    func backups() async throws -> [URL] { try await worker.run { try $0.backups() } }
}

/// Runs repository work one job at a time, in submission order, off the main thread.
final class PersistenceWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.iyashwant.habbitbuddy.persistence", qos: .userInitiated)
    private let repository: BuddyRepository
    /// Each job shows as a "Persistence job" interval in Instruments' os_signpost track.
    private static let signposter = OSSignposter(subsystem: "com.iyashwant.habbitbuddy", category: "Persistence")
    /// The snapshot this worker last read or saved. Used only on the queue.
    private var latest: BuddyData?
    /// A snapshot read or saved, and whether the file held changes this worker didn't make, written since by a
    /// widget, Shortcut, Live Activity or other user of the repository.
    struct Snapshot { let data: BuddyData; let changedElsewhere: Bool; var summaries: [UUID: HabitSummaries.Result]? = nil }
    init(_ repository: BuddyRepository) { self.repository = repository }
    /// With `summarize`, also works out every active habit's summary when the first screen shows streaks, so launch
    /// draws without reading histories on the main thread.
    func load(summarize: Bool = false, completion: @escaping @MainActor (Result<Snapshot, Error>) -> Void) {
        submit({ [self] repository in
            let data = try repository.load()
            defer { latest = data }
            let summaries = summarize && HabitSummaries.firstScreenReads(data) ? HabitSummaries.compute(Set(data.active.map(\.id)), data: data, today: Day()) : nil
            return Snapshot(data: data, changedElsewhere: data != latest, summaries: summaries)
        }, completion: completion)
    }
    /// Runs `change` in a locked transaction on the latest file.
    func save(_ change: @escaping AppStore.Change, completion: @escaping @MainActor (Result<Snapshot, Error>) -> Void) {
        submit({ [self] repository in
            var elsewhere = false
            // While the file is unchanged the repository hands back the snapshot it last saved, so this is immediate.
            let data = try repository.transaction { current in elsewhere = current != latest; try change(&current) }
            latest = data
            return Snapshot(data: data, changedElsewhere: elsewhere)
        }, completion: completion)
    }
    /// Runs work that replaces the store, such as a restore, and remembers the snapshot it saved.
    func replace(_ work: @escaping (BuddyRepository) throws -> BuddyData?) async throws -> BuddyData? {
        try await run { [self] repository in
            let data = try work(repository)
            if let data { latest = data }
            return data
        }
    }
    /// Completions run on the main queue in the same order as their jobs.
    func submit<T>(_ work: @escaping (BuddyRepository) throws -> T, completion: @escaping @MainActor (Result<T, Error>) -> Void) {
        let job = Unchecked((work, completion)), repository = repository
        queue.async {
            let interval = Self.signposter.beginInterval("Persistence job")
            defer { Self.signposter.endInterval("Persistence job", interval) }
            let result = Unchecked((Result { try job.value.0(repository) }, job.value.1))
            DispatchQueue.main.async { MainActor.assumeIsolated { result.value.1(result.value.0) } }
        }
    }
    func run<T: Sendable>(_ work: @escaping (BuddyRepository) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in submit(work) { continuation.resume(with: $0) } }
    }
}
/// Moves values the compiler can't prove sendable onto the persistence queue; the store hands them over and doesn't share them.
struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

struct DaySelection: Identifiable {
    let habit: Habit
    let day: Day
    var id: String { "\(habit.id)-\(day.rawValue)" }
}

/// Runs `work` off the main thread for a view's `.task`. Cancelling the task (its ID changed, or the view left)
/// cancels the work too, and a cancelled caller gets nil, so an older result never replaces a newer one.
func offMain<T: Sendable>(priority: TaskPriority = .userInitiated, _ work: @escaping @Sendable () -> T) async -> T? {
    let task = Task.detached(priority: priority, operation: work)
    let value = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    return Task.isCancelled ? nil : value
}
