import Foundation

/// A recorded civil date. UTC is used only for calendar arithmetic, never to re-date logs.
///
/// Arithmetic runs on `ordinal`, a day count since 1970-01-01, so grids and streaks never touch
/// DateFormatter or Calendar. Foundation's Gregorian calendar is Julian before the 1582 reform,
/// so earlier dates keep using Foundation to preserve its exact rules.
public struct Day: RawRepresentable, Codable, Hashable, Comparable, Identifiable, Sendable {
    public let rawValue: String
    private let ordinal: Int
    public var id: String { rawValue }
    public init?(rawValue: String) {
        guard let (y, m, d) = Self.components(rawValue) else { return nil }
        if (Self.firstFastYear...9_999).contains(y) {
            guard (1...12).contains(m), (1...Self.daysIn(m, y)).contains(d) else { return nil }
            self.rawValue = rawValue; ordinal = Self.ordinal(y, m, d)
        } else {
            guard let date = Self.formatter.date(from: rawValue), Self.formatter.string(from: date) == rawValue else { return nil }
            self.rawValue = rawValue; ordinal = Self.floorDays(date.timeIntervalSince1970)
        }
    }
    public init() {
        #if DEBUG
        if let day = Self.visualDate { self = day; return }
        #endif
        self.init(Date(), timeZone: .current)
    }
    public init(_ date: Date, timeZone: TimeZone = .current) {
        let local = Self.floorDays(date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date)))
        if local >= Self.firstFastOrdinal && local <= Self.lastFastOrdinal { self.init(ordinal: local); return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(storing: String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!), ordinal: local)
    }
    private init(ordinal: Int) {
        guard ordinal >= Self.firstFastOrdinal && ordinal <= Self.lastFastOrdinal else {
            self.init(Date(timeIntervalSince1970: Double(ordinal) * 86_400), timeZone: Self.utc); return
        }
        let (y, m, d) = Self.civil(ordinal)
        let text = String(unsafeUninitializedCapacity: 10) { b in
            let zero = UInt8(ascii: "0"), dash = UInt8(ascii: "-")
            b[0] = zero + UInt8(y / 1_000); b[1] = zero + UInt8(y / 100 % 10); b[2] = zero + UInt8(y / 10 % 10); b[3] = zero + UInt8(y % 10)
            b[4] = dash; b[5] = zero + UInt8(m / 10); b[6] = zero + UInt8(m % 10)
            b[7] = dash; b[8] = zero + UInt8(d / 10); b[9] = zero + UInt8(d % 10)
            return 10
        }
        self.init(storing: text, ordinal: ordinal)
    }
    private init(storing rawValue: String, ordinal: Int) { self.rawValue = rawValue; self.ordinal = ordinal }
    #if DEBUG
    private static let visualDate = ProcessInfo.processInfo.environment["BUDDY_VISUAL_DATE"].flatMap { Day(rawValue: $0) }
    #endif
    private static let utc = TimeZone(secondsFromGMT: 0)!
    // Immutable after initialization. DateFormatter is thread safe on supported Apple platforms.
    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar; f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"
        f.isLenient = false; return f
    }()
    public static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    public var date: Date { Date(timeIntervalSince1970: Double(ordinal) * 86_400) }
    public var month: String { String(rawValue.prefix(7)) }
    /// Months since January of year 0 (January is 0 mod 12), for month arithmetic without strings or a calendar.
    public var monthNumber: Int {
        var year = 0, month = 0
        for (i, byte) in rawValue.utf8.prefix(7).enumerated() where i != 4 {
            let digit = Int(byte) - 48
            if i < 4 { year = year * 10 + digit } else { month = month * 10 + digit }
        }
        return year * 12 + month - 1
    }
    public var weekday: Int { ((ordinal + 4) % 7 + 7) % 7 + 1 } // Sunday = 1; 1970-01-01 was a Thursday
    public func adding(_ count: Int) -> Day { count == 0 ? self : Day(ordinal: ordinal + count) }
    public func startOfWeek(_ firstWeekday: Int) -> Day { adding(-((weekday - firstWeekday + 7) % 7)) }
    public var startOfMonth: Day { Day(rawValue: month + "-01")! }
    public var endOfMonth: Day {
        if let (y, m, _) = Self.components(rawValue), (Self.firstFastYear...9_999).contains(y) { return Day(ordinal: Self.ordinal(y, m, Self.daysIn(m, y))) }
        return Day(Self.calendar.date(byAdding: .month, value: 1, to: startOfMonth.date)!, timeZone: Self.utc).adding(-1)
    }
    public func distance(to other: Day) -> Int { other.ordinal - ordinal }
    public func addingMonths(_ n: Int) -> Day { Day(Self.calendar.date(byAdding: .month, value: n, to: date)!, timeZone: Self.utc) }
    public static func < (lhs: Day, rhs: Day) -> Bool { lhs.ordinal < rhs.ordinal }

    // Proleptic Gregorian conversions (H. Hinnant, "chrono-Compatible Low-Level Date Algorithms").
    private static let firstFastYear = 1_583
    private static let firstFastOrdinal = ordinal(1_583, 1, 1)
    private static let lastFastOrdinal = ordinal(9_999, 12, 31)
    private static func floorDays(_ seconds: TimeInterval) -> Int { Int((seconds / 86_400).rounded(.down)) }
    private static func isLeap(_ y: Int) -> Bool { y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) }
    private static func daysIn(_ m: Int, _ y: Int) -> Int {
        switch m { case 2: return isLeap(y) ? 29 : 28; case 4, 6, 9, 11: return 30; default: return 31 }
    }
    private static func ordinal(_ year: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400, yoe = y - era * 400
        let doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1
        return era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719_468
    }
    private static func civil(_ ordinal: Int) -> (Int, Int, Int) {
        let z = ordinal + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097, doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100), mp = (5 * doy + 2) / 153
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, doy - (153 * mp + 2) / 5 + 1)
    }
    /// Strict `YYYY-MM-DD` with ASCII digits; range checks are left to the caller.
    private static func components(_ text: String) -> (Int, Int, Int)? {
        var y = 0, m = 0, d = 0, i = 0
        for byte in text.utf8 {
            guard i < 10 else { return nil }
            if i == 4 || i == 7 { guard byte == UInt8(ascii: "-") else { return nil } }
            else {
                guard byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") else { return nil }
                let digit = Int(byte - UInt8(ascii: "0"))
                if i < 4 { y = y * 10 + digit } else if i < 7 { m = m * 10 + digit } else { d = d * 10 + digit }
            }
            i += 1
        }
        return i == 10 ? (y, m, d) : nil
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer(); let text = try c.decode(String.self)
        guard let day = Day(rawValue: text) else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid civil date") }
        self = day
    }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
    public static func range(_ start: Day, _ end: Day) -> [Day] {
        guard start <= end else { return [] }
        return (0...start.distance(to: end)).map { start.adding($0) }
    }
}

/// Exact thousandths; count and yes/no goals use multiples of 1,000.
public enum Amount {
    public static let maximum: Int64 = 1_000_000_000_000
    public static func parse(_ text: String, locale: Locale = .current) throws -> Int64 {
        let separator = locale.decimalSeparator ?? "."
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: separator, with: ".")
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard value.contains(where: \.isNumber), parts.count <= 2, parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let whole = Int64(parts[0].isEmpty ? "0" : String(parts[0])), whole <= maximum / 1_000,
              parts.count == 1 || parts[1].count <= 3 else { throw BuddyError.invalidAmount }
        let fraction = parts.count == 2 ? Int64(String(parts[1]) + String(repeating: "0", count: 3 - parts[1].count)) ?? 0 : 0
        let result = whole * 1_000 + fraction
        guard result <= maximum else { throw BuddyError.invalidAmount }; return result
    }
    public static func text(_ value: Int64) -> String {
        let whole = value / 1_000, fraction = value % 1_000
        guard fraction != 0 else { return String(whole) }
        var suffix = String(format: "%03lld", fraction)
        while suffix.last == "0" { suffix.removeLast() }
        return "\(whole).\(suffix)"
    }
}
