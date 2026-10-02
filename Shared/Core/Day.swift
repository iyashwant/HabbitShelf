import Foundation

/// A recorded civil date. UTC is used only for calendar arithmetic, never to re-date logs.
public struct Day: RawRepresentable, Codable, Hashable, Comparable, Identifiable, Sendable {
    public let rawValue: String
    public var id: String { rawValue }
    public init?(rawValue: String) {
        guard rawValue.count == 10, let date = Self.formatter.date(from: rawValue),
              Self.formatter.string(from: date) == rawValue else { return nil }
        self.rawValue = rawValue
    }
    public init(_ date: Date = Date(), timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        rawValue = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    private static var formatter: DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar; f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"
        f.isLenient = false; return f
    }
    public static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }
    public var date: Date { Self.formatter.date(from: rawValue)! }
    public var month: String { String(rawValue.prefix(7)) }
    public var weekday: Int { Self.calendar.component(.weekday, from: date) } // Sunday = 1
    public func adding(_ count: Int) -> Day {
        Day(Self.calendar.date(byAdding: .day, value: count, to: date)!, timeZone: TimeZone(secondsFromGMT: 0)!)
    }
    public func startOfWeek(_ firstWeekday: Int) -> Day { adding(-((weekday - firstWeekday + 7) % 7)) }
    public var startOfMonth: Day { Day(rawValue: month + "-01")! }
    public var endOfMonth: Day {
        Day(Self.calendar.date(byAdding: .month, value: 1, to: startOfMonth.date)!, timeZone: TimeZone(secondsFromGMT: 0)!).adding(-1)
    }
    public func distance(to other: Day) -> Int { Self.calendar.dateComponents([.day], from: date, to: other.date).day! }
    public static func < (lhs: Day, rhs: Day) -> Bool { lhs.rawValue < rhs.rawValue }
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
