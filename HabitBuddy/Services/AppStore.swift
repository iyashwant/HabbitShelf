import SwiftUI
import WidgetKit
import os

/// The app's habit data. Changes show at once; saving runs in order on a background queue, so file locks,
/// reads, validation and writes never hold up a tap. If a save fails, its change is undone and reported.
@MainActor final class AppStore: ObservableObject {
    /// What the screens show: the latest saved snapshot with any changes still being saved applied on top.
    @Published private(set) var data = BuddyData() { didSet { revision &+= 1; summaries.reset() } }
    @Published var error: String?
    @Published var loaded = false
    /// True until the first read from disk finishes, so launch shows neither onboarding nor an empty list early.
    @Published private(set) var loading = true
    @Published var sharedStorageAvailable = AppEnvironment.hasSharedContainer
    /// Increases with every published snapshot. Screens key background work on it instead of comparing snapshots.
    private(set) var revision = 0
    /// `data` as the screens show it: hidden habits and their days left out. Worked out once per snapshot,
    /// on first use. Lists and summaries read it; changes still go through `change`, against the full data.
    var visible: BuddyData {
        if visibleRevision != revision { visibleData = data.withoutHidden; visibleRevision = revision }
        return visibleData
    }
    private var visibleData = BuddyData()
    private var visibleRevision = -1
    /// Streaks, stats and milestones, computed once per habit for each published snapshot.
    let summaries = HabitSummaries(caching: true)
    let repository = AppEnvironment.repository
    private let worker: PersistenceWorker
    /// The latest snapshot read from or written to disk.
    private var committed = BuddyData()
    /// Changes shown but not yet saved, oldest first.
    private var pending: [(id: Int, change: Change)] = []
    private var nextChange = 0
    private var syncScope: SyncScope = []
    private var sync: Task<Void, Never>?
    private var syncPending = false
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    /// A change runs twice: on the screen's snapshot now, then on the latest saved snapshot on the persistence
    /// queue. Capture values (not `@State` or other view state), and decide from the `data` it is given.
    typealias Change = (inout BuddyData) throws -> Void
    init() {
        worker = PersistenceWorker(repository)
        haptic.prepare()
        #if DEBUG
        if let screen=ProcessInfo.processInfo.environment["BUDDY_VISUAL_SCREEN"],ProcessInfo.processInfo.environment["BUDDY_VISUAL_RESET"] != "false" {
            do { committed=try repository.transaction{$0=VisualSamples.audit(screen)};data=committed;loaded=true } catch { self.error=error.localizedDescription }
            loading=false
            return
        }
        #endif
        reload()
    }
    /// Reads the latest saved data, after any queued saves, keeping changes that are still being saved.
    /// `reschedule` then refreshes reminders from it, as when the app returns to the foreground.
    func reload(reschedule: Bool = false) {
        worker.submit({ try $0.load() }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                committed = value; data = rebased(); loaded = true
                if reschedule { Task { await NotificationService.reconcile(value) } }
            case .failure(let failure): error = failure.localizedDescription; loaded = false
            }
            loading = false
        }
    }
    /// Applies a change now and queues it to be saved. Returns false, changing nothing, if it is invalid.
    @discardableResult func change(_ block: @escaping Change) -> Bool {
        guard loaded else { error = loading ? "Your habits are still loading. Try again in a moment." : "Data could not be loaded. Restore a backup before making changes."; return false }
        var next = data
        do { try block(&next); try DataValidation.validate(next) }
        catch { self.error = error.localizedDescription; return false }
        syncScope.formUnion(SyncScope(from: data, to: next))
        data = next
        let id = nextChange
        nextChange += 1
        pending.append((id, block))
        worker.submit({ try $0.transaction(block) }) { [weak self] result in self?.saved(id, result) }
        return true
    }
    private func saved(_ id: Int, _ result: Result<BuddyData, Error>) {
        pending.removeAll { $0.id == id }
        switch result {
        case .success(let value):
            committed = value
            // During a burst of taps the screen already shows every queued change; it takes the saved data once they finish.
            if pending.isEmpty { data = value }
            scheduleSync()
        case .failure(let failure):
            error = failure.localizedDescription
            data = rebased()
        }
        endBackgroundTaskIfIdle()
    }
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
            let scope = syncScope
            syncScope = []; syncPending = false
            await AppEnvironment.changed(committed, scope: scope)
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
        change { try Engine.setAmount(value, habitID: id, day: day, data: &$0) }
    }
    /// A yes/no habit toggles and a count adds one, judged from the latest saved amount when it is saved.
    @discardableResult func quickLog(_ habit: Habit, day: Day = Day()) -> Bool {
        let id = habit.id
        let result = withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .snappy(duration: 0.22)) {
            change { data in
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
            committed = try await worker.run { try $0.restore(bytes) }
            data = rebased(); loaded = true
            syncScope = .all; scheduleSync(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    /// Logs a running timer once, even if the Live Activity's Finish runs at the same time.
    /// True once the session is logged or was already finished elsewhere.
    func finishTimer(_ session: TimerSession, at now: Date) async -> Bool {
        do {
            guard let value = try await worker.run({ try TimerSessions.finish(session, repository: $0, at: now) }) else { return true }
            committed = value; data = rebased()
            syncScope = .all; scheduleSync(); return true
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
    init(_ repository: BuddyRepository) { self.repository = repository }
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
