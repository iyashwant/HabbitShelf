import Foundation

/// Ranks habit icons for a habit name as it is typed: `IconCatalog` first, then the icon set's own
/// names and keywords when no catalog word matches.
///
/// Words are folded (case, accents, apostrophes) and lightly stemmed, so "running", "runs" and "run"
/// meet. Phrases ("work out", "brush teeth") take precedence over their words. Among words of equal
/// weight the later one leads ("Walk the dog"), except words after a preposition, which only qualify
/// the habit ("Meditate before bed", "Gym after work"). The word still being typed also matches by
/// prefix from four letters, and words of five letters or more tolerate a typo. A negation ("quit", "no", "less"…) or a
/// quit habit leads with the concept's crossed-out icon, or adds a ban icon when it has none.
public struct IconSuggester: Sendable {
    /// An icon available to the fallback search, with the words that describe it.
    public struct Entry: Sendable {
        public let id: String
        public let name: String
        public let keywords: [String]
        public init(id: String, name: String, keywords: [String]) { self.id = id; self.name = name; self.keywords = keywords }
    }
    struct Concept: Sendable { let icons: [String]; let off: String? }
    struct Hit: Sendable { let concept: Int; let weight: Double }
    struct Phrase: Sendable { let words: [String]; let hit: Hit }
    struct Word: Sendable { let text: String; let hits: [Hit] }
    struct Candidate: Sendable { let bytes: [UInt8]; let hits: [Hit] }
    struct Fallback: Sendable { let id: String; let weight: Double }

    private var concepts: [Concept] = []
    /// Stemmed single-word terms.
    private var exact: [String: [Hit]] = [:]
    /// Multi-word terms by their first stem, longest first.
    private var phrases: [String: [Phrase]] = [:]
    /// Unstemmed single-word terms, for the word being typed.
    private var typed: [Word] = []
    /// Terms and their stems by first letter, for typo matching.
    private var initials: [UInt8: [Candidate]] = [:]
    private var fallback: [String: [Fallback]] = [:]
    private let ban: String?

    static let fillers: Set<String> = ["a", "an", "the", "my", "your", "his", "her", "our", "their", "its", "some", "this", "that"]
    static let prepositions: Set<String> = ["with", "after", "before", "during", "until", "till", "for", "at", "by", "in", "on", "to", "from", "into", "without", "like", "about", "around", "while"]
    static let negators: Set<String> = ["no", "not", "never", "quit", "quitting", "stop", "stopping", "avoid", "avoiding", "less", "fewer", "limit", "limiting", "reduce", "reducing", "cut", "cutting", "without", "skip", "dont", "free", "sober", "ban", "detox", "abstain", "resist", "kick", "nofap"]
    static let stopwords: Set<String> = fillers.union(prepositions).union([
        "these", "those", "any", "of", "onto", "and", "or", "but", "so", "then", "than", "me", "i", "im", "ive", "myself", "it", "be", "is", "am", "are", "was",
        "get", "go", "going", "do", "doing", "done", "make", "take", "have", "has", "can", "will", "should", "must", "try", "keep", "start", "give", "practice", "practise", "track", "tracking",
        "more", "most", "much", "many", "very", "just", "only", "also", "every", "each", "per", "least", "once", "twice", "again", "all", "new", "good", "better", "best",
        "day", "days", "daily", "week", "weeks", "weekly", "month", "months", "monthly", "year", "years", "yearly", "today", "tonight", "time", "times",
        "minute", "minutes", "min", "mins", "hour", "hours", "hr", "hrs", "h", "m", "second", "seconds", "sec", "secs", "x", "k", "pm",
        "habit", "habits", "up", "out", "down", "over", "back", "first", "next", "last", "one", "two", "three", "four", "five", "ten", "twenty", "thirty",
    ])

    /// - Parameters:
    ///   - catalog: Entries in `IconCatalog`'s format.
    ///   - icons: The installed icons. When given, catalog icons outside it are dropped and its names and keywords become the fallback search.
    public init(catalog: [String] = IconCatalog.entries, icons: [Entry] = []) {
        let installed = Set(icons.map(\.id))
        func usable(_ id: String) -> Bool { installed.isEmpty || installed.contains(id) }
        ban = usable("lu:ban") ? "lu:ban" : nil
        var typedHits: [String: [Hit]] = [:]
        for line in catalog {
            guard let colon = line.firstIndex(of: ":") else { continue }
            var list: [String] = [], off: String?, scale = 1.0
            for name in line[..<colon].split(separator: " ") {
                if name.hasPrefix("!") { off = "lu:" + name.dropFirst() } else if name.hasPrefix("*") { scale = Double(name.dropFirst()) ?? 1 } else { list.append("lu:" + name) }
            }
            let index = concepts.count
            concepts.append(Concept(icons: list.filter(usable), off: off.flatMap { usable($0) ? $0 : nil }))
            for term in line[line.index(after: colon)...].split(separator: ",") {
                var text = term.trimmingCharacters(in: .whitespaces), weight = scale
                if text.hasSuffix("~") { text.removeLast(); weight *= 0.4 }
                let raw = Self.words(text).filter { !Self.fillers.contains($0) }
                guard !raw.isEmpty, raw.count > 1 || !Self.stopwords.contains(raw[0]) else { continue }
                let stems = raw.map(Self.stem)
                if stems.count == 1 {
                    Self.merge(Hit(concept: index, weight: weight), into: &exact[stems[0], default: []])
                    Self.merge(Hit(concept: index, weight: weight), into: &typedHits[raw[0], default: []])
                } else {
                    phrases[stems[0], default: []].append(Phrase(words: stems, hit: Hit(concept: index, weight: weight * (1 + 0.5 * Double(stems.count - 1)))))
                }
            }
        }
        for key in phrases.keys { phrases[key]?.sort { $0.words.count > $1.words.count } }
        typed = typedHits.map { Word(text: $0.key, hits: $0.value) }.sorted { $0.text < $1.text }
        for (key, hits) in exact.map({ ($0.key, $0.value) }) + typed.map({ ($0.text, $0.hits) }) {
            let bytes = Array(key.utf8)
            if let first = bytes.first { initials[first, default: []].append(Candidate(bytes: bytes, hits: hits)) }
        }
        var shared: [String: [String: Double]] = [:]
        for icon in icons {
            for (text, weight) in [(icon.name, 0.5)] + icon.keywords.map({ ($0, 0.25) }) {
                for word in Self.words(text) where word.count >= 3 && !Self.stopwords.contains(word) {
                    let stem = Self.stem(word)
                    shared[stem, default: [:]][icon.id] = max(shared[stem]?[icon.id] ?? 0, weight)
                }
            }
        }
        // A word shared by many icons ("arrow", "square") says nothing about a habit.
        for (stem, ids) in shared where ids.count <= 20 { fallback[stem] = ids.map { Fallback(id: $0.key, weight: $0.value) }.sorted { $0.id < $1.id } }
    }

    /// Icon IDs for `title`, best first. Empty when no word is recognized.
    public func suggest(_ title: String, quit: Bool = false, limit: Int = 8) -> [String] {
        let raw = Self.words(title)
        guard !raw.isEmpty, limit > 0 else { return [] }
        let typing = title.unicodeScalars.last.map { CharacterSet.alphanumerics.contains($0) } ?? false
        var negated = quit, words: [String] = [], seq: [String] = []
        for (i, word) in raw.enumerated() {
            if Self.negators.contains(word) || (word == "up" && i > 0 && raw[i - 1] == "give") { negated = true }
            if !Self.fillers.contains(word) { words.append(word); seq.append(Self.stem(word)) }
        }
        guard !seq.isEmpty else { return [] }
        // Words after a preposition that follows a recognized word only qualify the habit.
        var modifier = Array(repeating: false, count: seq.count), recognized = false, qualifying = false
        for i in seq.indices {
            if Self.prepositions.contains(words[i]) { qualifying = qualifying || recognized; continue }
            modifier[i] = qualifying
            if !Self.stopwords.contains(words[i]), exact[seq[i]] != nil { recognized = true }
        }
        let leads = seq.indices.filter { !modifier[$0] }
        func emphasis(_ i: Int) -> (factor: Double, bonus: Double) {
            if modifier[i] { return (0.7, 0) }
            guard leads.count > 1, let rank = leads.firstIndex(of: i) else { return (1, 0) }
            return (1, 0.15 * Double(rank) / Double(leads.count - 1))
        }
        var scores: [Int: Double] = [:], used = Array(repeating: false, count: seq.count)
        func add(_ hits: [Int: Double], at i: Int) { let e = emphasis(i); for (c, w) in hits { scores[c, default: 0] += w * e.factor + e.bonus } }
        for i in seq.indices where !used[i] {
            let found = (phrases[seq[i]] ?? []).filter { p in i + p.words.count <= seq.count && Array(seq[i..<i + p.words.count]) == p.words }
            guard let longest = found.first?.words.count else { continue }
            var hits: [Int: Double] = [:]
            for p in found where p.words.count == longest { hits[p.hit.concept] = max(hits[p.hit.concept] ?? 0, p.hit.weight) }
            add(hits, at: i)
            for k in i..<i + longest { used[k] = true }
        }
        var extra: [String: Double] = [:]
        for i in seq.indices where !used[i] {
            let stem = seq[i], word = words[i]
            if Self.stopwords.contains(word) { continue }
            if let hits = exact[stem] { add(Self.best(hits), at: i); continue }
            if Self.negators.contains(word) { continue }
            var hits: [Int: Double] = [:]
            if typing && i == seq.count - 1 && word.count >= 4 {
                for entry in typed where entry.text.hasPrefix(word) {
                    let completion = 0.5 + 0.4 * Double(word.count) / Double(entry.text.count)
                    for h in entry.hits { hits[h.concept] = max(hits[h.concept] ?? 0, h.weight * completion) }
                }
            }
            let spelled = Array(word.utf8), stemmed = Array(stem.utf8)
            if hits.isEmpty, spelled.count >= 5, let first = spelled.first {
                let allowed = spelled.count >= 8 ? 2 : 1
                for candidate in initials[first] ?? [] {
                    let d = min(Self.distance(spelled, candidate.bytes, limit: allowed), Self.distance(stemmed, candidate.bytes, limit: allowed))
                    guard d <= allowed else { continue }
                    for h in candidate.hits { hits[h.concept] = max(hits[h.concept] ?? 0, h.weight * (d == 1 ? 0.75 : 0.6)) }
                }
            }
            if hits.isEmpty { for f in fallback[stem] ?? [] { extra[f.id] = max(extra[f.id] ?? 0, f.weight) } } else { add(hits, at: i) }
        }

        var ranked: [String: (score: Double, order: Int)] = [:]
        func put(_ id: String, _ score: Double, _ order: Int) {
            let old = ranked[id]
            ranked[id] = (max(old?.score ?? 0, score), min(old?.order ?? .max, order))
        }
        var top: (concept: Int, score: Double)?
        for (c, raw) in scores {
            let concept = concepts[c], score = negated && concept.off != nil ? raw * 1.25 : raw
            var list = concept.icons
            if negated, let off = concept.off { list.insert(off, at: 0) }
            guard !list.isEmpty else { continue }
            if score > top?.score ?? 0 || (score == top?.score && c < top!.concept) { top = (c, score) }
            for (k, id) in list.enumerated() { put(id, k == 0 ? score : score * max(0.3, 0.6 - 0.05 * Double(k - 1)), c * 16 + k) }
        }
        if let top, negated, concepts[top.concept].off == nil, let ban { put(ban, top.score * 0.95, top.concept * 16) }
        if ranked.isEmpty { for (n, item) in extra.sorted(by: { $0.key < $1.key }).enumerated() { put(item.key, item.value, 1_000_000 + n) } }
        return ranked.sorted { $0.value.score != $1.value.score ? $0.value.score > $1.value.score : $0.value.order < $1.value.order }.prefix(limit).map(\.key)
    }

    /// Lowercased words without accents or apostrophes; bare numbers are dropped.
    static func words(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
        var result: [String] = [], word = String.UnicodeScalarView()
        func flush() {
            guard !word.isEmpty else { return }
            let text = String(word); word = String.UnicodeScalarView()
            if !text.allSatisfy(\.isNumber) { result.append(text) }
        }
        for scalar in folded.unicodeScalars {
            if scalar == "'" || scalar == "\u{2019}" { continue }
            if CharacterSet.alphanumerics.contains(scalar) { word.append(scalar) } else { flush() }
        }
        flush()
        return result
    }

    /// A light English stemmer: plurals, -ing, -ed, -ation, a final e, y to i and a doubled final consonant.
    /// It only needs to be consistent, so "smoke" and "smoking" both become "smok".
    static func stem(_ word: String) -> String {
        var w = Array(word.utf8)
        guard w.count > 2, w.allSatisfy({ $0 >= 97 && $0 <= 122 }) else { return word }
        func ends(_ suffix: String) -> Bool { let s = Array(suffix.utf8); return w.count > s.count && w.suffix(s.count).elementsEqual(s) }
        func vowel(_ c: UInt8) -> Bool { "aeiou".utf8.contains(c) }
        if ends("sses") { w.removeLast(2) }
        else if ends("ies") && w.count > 4 { w.removeLast(2) }
        else if ends("ches") || ends("shes") || ends("xes") { w.removeLast(2) }
        else if ends("s") && !ends("ss") && !ends("us") && !ends("is") { w.removeLast() }
        if w.count > 5 && ends("ing") { w.removeLast(3) }
        else if w.count > 4 && ends("ed") && !ends("eed") { w.removeLast(2) }
        if w.count > 6 && ends("ation") { w.removeLast(3) }
        if w.count > 3 && w.last == UInt8(ascii: "e") { w.removeLast() }
        if w.count > 2, w.last == UInt8(ascii: "y"), !vowel(w[w.count - 2]) { w[w.count - 1] = UInt8(ascii: "i") }
        if w.count > 2, w[w.count - 1] == w[w.count - 2], !vowel(w[w.count - 1]) { w.removeLast() }
        return String(decoding: w, as: UTF8.self)
    }

    /// Optimal string alignment distance, giving up once it exceeds `limit`.
    static func distance(_ a: [UInt8], _ b: [UInt8], limit: Int) -> Int {
        guard abs(a.count - b.count) <= limit else { return limit + 1 }
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        var before = [Int](repeating: 0, count: b.count + 1), previous = Array(0...b.count), current = before
        for i in 1...a.count {
            current[0] = i
            var smallest = i
            for j in 1...b.count {
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { value = min(value, before[j - 2] + 1) }
                current[j] = value
                smallest = min(smallest, value)
            }
            if smallest > limit { return limit + 1 }
            (before, previous, current) = (previous, current, before)
        }
        return previous[b.count]
    }

    private static func merge(_ hit: Hit, into list: inout [Hit]) {
        if let i = list.firstIndex(where: { $0.concept == hit.concept }) { if hit.weight > list[i].weight { list[i] = hit } } else { list.append(hit) }
    }
    private static func best(_ hits: [Hit]) -> [Int: Double] { Dictionary(hits.map { ($0.concept, $0.weight) }, uniquingKeysWith: max) }
}
