import Foundation

/// Which home-screen widget kinds show the habits a change touched. WidgetKit reloads a kind as a whole, so a kind
/// reloads when any of its installed widgets shows one of those habits.
public enum WidgetTargets {
    /// What an installed widget was set to show.
    public enum Choice: Equatable, Sendable {
        /// One habit; nil shows the first active habit.
        case habit(UUID?)
        /// Chosen habits; nil or none shows every active habit.
        case habits([UUID]?)
        /// A routine's habits; nil shows the first routine.
        case routine(UUID?)
        /// A kind this doesn't know, which always reloads.
        case unknown
    }
    public struct Installed: Equatable, Sendable {
        public var kind: String
        public var choice: Choice
        public init(kind: String, choice: Choice) { self.kind = kind; self.choice = choice }
    }
    /// The kinds to reload after a change that touched `habits`. A widget showing a default habit or every habit
    /// reloads for any habit, since a touched habit can become or stop being the one it shows.
    public static func kinds(_ installed: [Installed], touching habits: Set<UUID>, data: BuddyData) -> Set<String> {
        guard !habits.isEmpty else { return [] }
        var kinds = Set<String>()
        for widget in installed where !kinds.contains(widget.kind) {
            let shows: Bool
            switch widget.choice {
            case .habit(let id): shows = id.map(habits.contains) ?? true
            case .habits(let ids): shows = ids.map { $0.isEmpty || !habits.isDisjoint(with: $0) } ?? true
            case .routine(let id):
                let routine = id.map { id in data.routines.first { $0.id == id } } ?? data.routines.first
                shows = routine.map { !habits.isDisjoint(with: $0.habitIDs) } ?? false
            case .unknown: shows = true
            }
            if shows { kinds.insert(widget.kind) }
        }
        return kinds
    }
}
