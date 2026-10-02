import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum DataValidation {
    public static func validate(_ data: BuddyData, today: Day = Day()) throws {
        func require(_ condition: Bool, _ reason: String) throws {
            if !condition { throw BuddyError.invalidData(reason) }
        }
        try require(data.schemaVersion == 1, "unsupported schema version")
        try require(data.habits.count <= 1_000 && data.records.count <= 250_000, "too many records")
        let habitIDs = Set(data.habits.map(\.id)), categoryIDs = Set(data.categories.map(\.id))
        try require(habitIDs.count == data.habits.count && categoryIDs.count == data.categories.count, "duplicate identifiers")
        try require(data.settings.weekStart >= 1 && data.settings.weekStart <= 7 && (1...7).contains(data.settings.recentDays), "invalid calendar settings")
        for category in data.categories { try require(!category.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && category.name.count <= 100, "invalid category") }
        for habit in data.habits {
            try require(!habit.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && habit.name.count <= 200 && habit.detail.count <= 2_000, "invalid habit name or description")
            try require(habit.created <= today && habit.created.rawValue >= "1970-01-01", "invalid start date")
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
        for (key, record) in data.records {
            guard let habit = data.habits.first(where: { $0.id == record.habitID }) else { throw BuddyError.invalidData("orphaned record") }
            let goal = habit.goal(on: record.day)
            try require(key == record.key && record.day >= habit.created && record.day <= today, "invalid record key or date")
            try require(record.amount >= 0 && record.amount <= Amount.maximum && record.note.count <= 20_000, "invalid progress or note")
            try require(goal.tracking == .measure || record.amount % 1_000 == 0, "fractional count")
            try require(goal.tracking != .yesNo || record.amount <= 1_000, "invalid yes/no amount")
            try require(record.completionHour == nil || (0...23).contains(record.completionHour!), "invalid completion hour")
        }
    }
    private static func validate(_ reminder: Reminder) throws {
        guard (0...23).contains(reminder.hour), (0...59).contains(reminder.minute),
              !reminder.weekdays.isEmpty, reminder.weekdays.allSatisfy({ (1...7).contains($0) }),
              Set(reminder.weekdays).count == reminder.weekdays.count else { throw BuddyError.invalidData("invalid reminder") }
    }
    public static func encode(_ data: BuddyData) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(data)
    }
    public static func decode(_ bytes: Data, today: Day = Day()) throws -> BuddyData {
        guard !bytes.isEmpty, bytes.count <= 64 * 1_024 * 1_024 else { throw BuddyError.invalidData("empty or oversized file") }
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
    public init(directory: URL) { self.directory = directory }
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
        return try DataValidation.decode(Data(contentsOf: file))
    }
    public func load() throws -> BuddyData { try locked { try readUnlocked() } }
    @discardableResult public func transaction(_ change: (inout BuddyData) throws -> Void) throws -> BuddyData {
        try locked {
            var current = try readUnlocked()
            try dailyBackup(current)
            try change(&current)
            try DataValidation.validate(current)
            try DataValidation.encode(current).write(to: file, options: .atomic)
            return current
        }
    }
    public func export() throws -> Data { try locked { try DataValidation.encode(readUnlocked()) } }
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
            try DataValidation.encode(replacement).write(to: file, options: .atomic)
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
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let backup = backupDirectory.appendingPathComponent("daily-\(Day().rawValue).json")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try DataValidation.encode(current).write(to: backup, options: .atomic)
        }
        try prune(prefix: "daily-", keep: 7)
    }
    private func prune(prefix: String, keep: Int) throws {
        let files = try FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(prefix) }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in files.dropFirst(keep) { try FileManager.default.removeItem(at: old) }
    }
}
