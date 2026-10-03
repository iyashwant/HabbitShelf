import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum DataValidation {
    /// The largest store, backup or import that is read or written.
    public static let maximumBytes = 64 * 1_024 * 1_024
    public static func validate(_ data: BuddyData, today: Day = Day()) throws {
        func require(_ condition: Bool, _ reason: String) throws {
            if !condition { throw BuddyError.invalidData(reason) }
        }
        try require(data.schemaVersion == 1, "unsupported schema version")
        try require(data.habits.count <= 1_000 && data.records.count <= 250_000, "too many records")
        // Records find their habit by ID once each, rather than searching every habit.
        let byID = Dictionary(data.habits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let habitIDs = Set(byID.keys), categoryIDs = Set(data.categories.map(\.id))
        try require(habitIDs.count == data.habits.count && categoryIDs.count == data.categories.count, "duplicate identifiers")
        try require(data.settings.weekStart >= 1 && data.settings.weekStart <= 7 && (1...7).contains(data.settings.recentDays), "invalid calendar settings")
        for category in data.categories { try require(!category.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && category.name.count <= 100, "invalid category") }
        for habit in data.habits {
            try require(!habit.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && habit.name.count <= 200 && habit.detail.count <= 2_000, "invalid habit name or description")
            try require(habit.created <= today && habit.created >= Habit.earliestStart, "invalid start date")
            try require(habit.archived == nil || (habit.archived! >= habit.created && habit.archived! <= today), "invalid archive date")
            var pauseEnd: Day?
            for pause in habit.pauses {
                try require(pause.from >= habit.created && pause.through <= today && pause.from <= pause.through && (pauseEnd == nil || pause.from > pauseEnd!), "invalid paused dates")
                pauseEnd = pause.through
            }
            try require(Set(habit.categories).count == habit.categories.count && Set(habit.categories).isSubset(of: categoryIDs), "invalid category membership")
            try require(!habit.goals.isEmpty && habit.goals.first!.from == habit.created && habit.goals.count <= 10_000, "missing initial goal")
            var previous: Day?
            for goal in habit.goals {
                try require(goal.from <= today && (previous == nil || goal.from > previous!), "unordered or duplicate goal date")
                try require(goal.target > 0 && goal.target <= Amount.maximum, "invalid target")
                try require(goal.tracking == .measure || goal.target % 1_000 == 0, "a count target must be an integer")
                try require(goal.tracking != .yesNo || goal.target == 1_000, "invalid yes/no target")
                try require(goal.mode != .quit || goal.cadence == .daily, "quit habits use daily goals")
                try require(goal.days >= 1 && goal.days <= (goal.cadence == .weekly ? 7 : goal.cadence == .monthly ? 31 : 1), "invalid cadence target")
                try require(goal.unit.count <= 40, "unit is too long")
                previous = goal.from
            }
            try require(habit.reminders.count <= 3, "at most three reminders per habit")
            for reminder in habit.reminders { try validate(reminder) }
        }
        if let reminder = data.settings.checkIn { try validate(reminder) }
        if let dashboard = data.settings.dashboard {
            try require(dashboard.count <= 100 && Set(dashboard.map(\.id)).count == dashboard.count, "invalid dashboard")
            for widget in dashboard {
                let ids = widget.habitIDs ?? []
                try require(ids.count <= 1_000 && Set(ids).count == ids.count, "invalid dashboard habits")
                try require((widget.title?.count ?? 0) <= 100 && (widget.color?.count ?? 0) <= 40, "invalid dashboard widget")
            }
        }
        try require((0...7).contains(data.settings.freezesPerMonth), "invalid streak freeze allowance")
        try require(data.routines.count <= 100 && Set(data.routines.map(\.id)).count == data.routines.count, "invalid routines")
        for routine in data.routines {
            try require(!routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && routine.name.count <= 100, "invalid routine name")
            try require(Set(routine.habitIDs).count == routine.habitIDs.count && Set(routine.habitIDs).isSubset(of: habitIDs), "invalid routine habits")
        }
        let prefixes = byID.mapValues { Record.keyPrefix($0.id) }
        for (key, record) in data.records {
            guard let habit = byID[record.habitID], let prefix = prefixes[record.habitID] else { throw BuddyError.invalidData("orphaned record") }
            let goal = habit.goal(on: record.day)
            // Same as `key == record.key`, without building a key string per record.
            let keyMatches = key.utf8.count == prefix.utf8.count + record.day.rawValue.utf8.count && key.hasPrefix(prefix) && key.hasSuffix(record.day.rawValue)
            try require(keyMatches && record.day >= habit.created && record.day <= today, "invalid record key or date")
            // A note can't have more characters than UTF-8 bytes, so most notes skip counting characters.
            try require(record.amount >= 0 && record.amount <= Amount.maximum && (record.note.utf8.count <= 20_000 || record.note.count <= 20_000), "invalid progress or note")
            try require(goal.tracking == .measure || record.amount % 1_000 == 0, "fractional count")
            try require(goal.tracking != .yesNo || record.amount <= 1_000, "invalid yes/no amount")
            try require(record.completionHour == nil || (0...23).contains(record.completionHour!), "invalid completion hour")
            try require(record.frozen != true || (record.day < today && goal.mode == .build && goal.cadence == .daily && record.amount < goal.target), "invalid streak freeze")
        }
    }
    private static func validate(_ reminder: Reminder) throws {
        guard (0...23).contains(reminder.hour), (0...59).contains(reminder.minute),
              !reminder.weekdays.isEmpty, reminder.weekdays.allSatisfy({ (1...7).contains($0) }),
              Set(reminder.weekdays).count == reminder.weekdays.count else { throw BuddyError.invalidData("invalid reminder") }
    }
    /// Portable exports are formatted for people; the store and its backups are written compactly.
    public static func encode(_ data: BuddyData, formatted: Bool = true) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        if formatted { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        return try encoder.encode(data)
    }
    /// A portable export: formatted, unless formatting would make it too large to import again.
    public static func export(_ data: BuddyData) throws -> Data {
        let formatted = try encode(data)
        return formatted.count <= maximumBytes ? formatted : try encode(data, formatted: false)
    }
    /// Reads a store, backup or import, checking its size before loading it into memory.
    public static func read(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumBytes else { throw BuddyError.invalidData("empty or oversized file") }
        return try Data(contentsOf: url)
    }
    public static func decode(_ bytes: Data, today: Day = Day()) throws -> BuddyData {
        guard !bytes.isEmpty, bytes.count <= maximumBytes else { throw BuddyError.invalidData("empty or oversized file") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(BuddyData.self, from: bytes)
        try validate(value, today: today); return value
    }
}

/// A process-wide advisory lock plus atomic replacement prevents lost app/widget writes.
/// Every transaction re-reads the latest file under the lock, then validates before committing.
public final class BuddyRepository: @unchecked Sendable {
    public let directory: URL
    private let mutex = NSRecursiveLock()
    /// The last snapshot this instance read or committed, keyed by its exact bytes and validation day.
    /// Unchanged files skip JSON decoding; any write from another process changes the bytes.
    private var cache: (bytes: Data, day: Day, value: BuddyData)?
    /// The largest file a commit may write; tests lower it.
    let maximumBytes: Int
    public convenience init(directory: URL) { self.init(directory: directory, maximumBytes: DataValidation.maximumBytes) }
    init(directory: URL, maximumBytes: Int) { self.directory = directory; self.maximumBytes = maximumBytes }
    private var file: URL { directory.appendingPathComponent("habits-v1.json") }
    public var backupDirectory: URL { directory.appendingPathComponent("Backups", isDirectory: true) }
    private func locked<T>(_ body: () throws -> T) throws -> T {
        mutex.lock(); defer { mutex.unlock() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.appendingPathComponent("store.lock").path, O_CREAT | O_RDWR, mode_t(0o600))
        guard fd >= 0 else { throw BuddyError.storage("unable to lock the database") }
        defer { flock(fd, LOCK_UN); close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw BuddyError.storage("database lock failed") }
        return try body()
    }
    private func readUnlocked() throws -> BuddyData {
        guard FileManager.default.fileExists(atPath: file.path) else { return BuddyData() }
        let bytes = try DataValidation.read(file), today = Day()
        if let cache, cache.day == today, cache.bytes == bytes { return cache.value }
        let value = try DataValidation.decode(bytes, today: today)
        cache = (bytes, today, value)
        return value
    }
    private func commitUnlocked(_ value: BuddyData) throws {
        let bytes = try DataValidation.encode(value, formatted: false)
        // A file the decoder would reject must never replace a readable one.
        guard bytes.count <= maximumBytes else { throw BuddyError.storage("it would be larger than the 64 MB limit. Remove some notes or habits, then try again.") }
        try bytes.write(to: file, options: .atomic)
        cache = (bytes, Day(), value)
    }
    public func load() throws -> BuddyData { try locked { try readUnlocked() } }
    @discardableResult public func transaction(_ change: (inout BuddyData) throws -> Void) throws -> BuddyData {
        try locked {
            var current = try readUnlocked()
            try dailyBackup(current)
            try change(&current)
            try DataValidation.validate(current)
            try commitUnlocked(current)
            return current
        }
    }
    public func export() throws -> Data { try locked { try DataValidation.export(readUnlocked()) } }
    @discardableResult public func restore(_ bytes: Data) throws -> BuddyData {
        // Fully decode and validate BEFORE opening a transaction or touching the usable file.
        let replacement = try DataValidation.decode(bytes)
        return try locked {
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let stamp = "before-restore-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).json"
            if FileManager.default.fileExists(atPath: file.path) {
                // Preserve even an unreadable original, allowing explicit recovery from corruption.
                try Data(contentsOf: file).write(to: backupDirectory.appendingPathComponent(stamp), options: .atomic)
            }
            try prune(prefix: "before-restore-", keep: 3)
            try commitUnlocked(replacement)
            return replacement
        }
    }
    public func backups() throws -> [URL] {
        try locked {
            guard FileManager.default.fileExists(atPath: backupDirectory.path) else { return [] }
            return try FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
    }
    private func dailyBackup(_ current: BuddyData) throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let backup = backupDirectory.appendingPathComponent("daily-\(Day().rawValue).json")
        // Only this method creates daily snapshots, so pruning is needed only after adding one.
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        try DataValidation.encode(current, formatted: false).write(to: backup, options: .atomic)
        try prune(prefix: "daily-", keep: 7)
    }
    private func prune(prefix: String, keep: Int) throws {
        let files = try FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(prefix) }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in files.dropFirst(keep) { try FileManager.default.removeItem(at: old) }
    }
}
