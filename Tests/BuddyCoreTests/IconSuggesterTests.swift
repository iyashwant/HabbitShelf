import XCTest
@testable import BuddyCore

final class IconSuggesterTests: XCTestCase {
    /// The bundled Lucide index, read from the repository like the app reads it from its bundle.
    static let lucide: [IconSuggester.Entry] = {
        struct Icon: Decodable { let id: String; let name: String; let keywords: [String] }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bytes = (try? Data(contentsOf: root.appendingPathComponent("Shared/Resources/lucide-icons.json"))) ?? Data()
        return ((try? JSONDecoder().decode([Icon].self, from: bytes)) ?? []).map { IconSuggester.Entry(id: $0.id, name: $0.name, keywords: $0.keywords) }
    }()
    static let suggester = IconSuggester(icons: lucide)
    func expect(_ cases: [(String, String)], quit: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        for (title, icon) in cases { XCTAssertEqual(Self.suggester.suggest(title, quit: quit).first, "lu:" + icon, title, file: file, line: line) }
    }

    func testEveryCatalogIconIsBundled() {
        let installed = Set(Self.lucide.map(\.id))
        XCTAssertGreaterThan(installed.count, 1_000)
        for entry in IconCatalog.entries {
            let parts = entry.split(separator: ":", maxSplits: 1)
            XCTAssertEqual(parts.count, 2, entry)
            for name in parts[0].split(separator: " ") where !name.hasPrefix("*") {
                XCTAssertTrue(installed.contains("lu:" + name.drop { $0 == "!" }), "\(name) in \(entry)")
            }
            XCTAssertFalse(parts.last!.split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }, entry)
        }
        XCTAssertGreaterThan(IconCatalog.entries.count, 250)
    }
    func testCommonHabits() {
        expect([
            ("Go to the gym", "dumbbell"), ("Work out", "dumbbell"), ("Lift weights", "dumbbell"), ("Push-Ups", "biceps-flexed"), ("Run 5k", "sport-shoe"),
            ("Walk 10k steps", "footprints"), ("Swim", "waves-ladder"), ("Yoga", "person-standing"), ("Meditate", "flower-2"), ("Smoking", "cigarette"),
            ("Drink water", "glass-water"), ("Drink 8 glasses of water", "glass-water"), ("Diet", "salad"), ("Eat healthy", "salad"), ("Take vitamins", "pill"),
            ("Read 20 pages", "book-open"), ("Read news", "newspaper"), ("Journal", "notebook-pen"), ("Learn Spanish", "languages"), ("Leetcode", "code-xml"),
            ("Sleep by 11", "bed"), ("Wake up at 6am", "alarm-clock"), ("Make the bed", "bed-double"), ("Brush teeth", "toothbrush"), ("Floss", "toothbrush"),
            ("Save money", "piggy-bank"), ("Water plants", "plant-pot"), ("Call mom", "phone-call"), ("Pray", "hand-heart"), ("Namaz", "mosque"),
            ("Walk the dog", "dog"), ("Feed the cat", "cat"), ("Cook dinner", "chef-hat"), ("Practice guitar", "guitar"), ("Weigh in", "weight"),
        ])
    }
    func testQuittingLeadsWithCrossedOutIcon() {
        expect([("Quit smoking", "cigarette-off"), ("No alcohol", "wine-off"), ("Stop drinking", "wine-off"), ("Sober", "wine-off"), ("Sugar free", "candy-off"),
                ("Less sugar", "candy-off"), ("Limit screen time", "phone-off"), ("No snooze", "alarm-clock-off"), ("Quit coffee", "bean-off"), ("No spend day", "credit-card-x")])
        expect([("Smoking", "cigarette-off"), ("Gossip", "mouth-off")], quit: true)
        XCTAssertEqual(Self.suggester.suggest("Quit smoking").prefix(2), ["lu:cigarette-off", "lu:cigarette"])
        // Without a crossed-out version the habit's own icon leads and a ban icon follows.
        XCTAssertEqual(Self.suggester.suggest("No junk food").prefix(2), ["lu:hamburger", "lu:ban"])
        // "Pay off" is not a negation.
        XCTAssertEqual(Self.suggester.suggest("Pay off debt").first, "lu:credit-card")
        XCTAssertFalse(Self.suggester.suggest("Pay off debt").contains("lu:ban"))
    }
    func testPhrasesAndQualifiersPickTheMainActivity() {
        expect([("Read before bed", "book-open"), ("Meditate before bed", "flower-2"), ("Gym after work", "dumbbell"), ("Run with friends", "sport-shoe"),
                ("No phone before bed", "phone-off"), ("Walk to work", "footprints"), ("Clean kitchen", "broom"), ("Save 10 dollars", "piggy-bank"), ("Morning run", "sport-shoe")])
    }
    func testWordBeingTypedAndTypos() {
        XCTAssertEqual(Self.suggester.suggest("Medit").first, "lu:flower-2")
        XCTAssertEqual(Self.suggester.suggest("Medi").first, "lu:pill", "Medication, medicine and meds share the shorter prefix")
        XCTAssertTrue(Self.suggester.suggest("Medi").contains("lu:flower-2"))
        XCTAssertEqual(Self.suggester.suggest("Smok").first, "lu:cigarette")
        XCTAssertEqual(Self.suggester.suggest("Go to the gy"), [], "Two letters are too few to guess from")
        XCTAssertEqual(Self.suggester.suggest("Qui"), [], "Three letters don't guess either, so typing doesn't flash unrelated icons")
        XCTAssertEqual(Self.suggester.suggest("Run").first, "lu:sport-shoe", "A short word still matches exactly")
        XCTAssertEqual(Self.suggester.suggest("Smok ").first, "lu:cigarette", "A finished word still matches its stem")
        expect([("Excercise", "dumbbell"), ("Meditaiton", "flower-2"), ("Sleap", "bed"), ("Yogga", "person-standing"), ("Wrkout", "dumbbell")])
        XCTAssertEqual(Self.suggester.suggest("Play piano").first, "lu:piano")
        XCTAssertFalse(Self.suggester.suggest("Play piano").contains("lu:hand-heart"), "Short words don't take typo matches (play / pray)")
    }
    func testFallsBackToIconKeywords() {
        XCTAssertEqual(Self.suggester.suggest("Archery").first, "lu:bow-arrow")
        let custom = IconSuggester(catalog: [], icons: [IconSuggester.Entry(id: "lu:bow-arrow", name: "Bow Arrow", keywords: ["archery", "sport"])])
        XCTAssertEqual(custom.suggest("Archery practice"), ["lu:bow-arrow"])
    }
    func testUnknownTitlesSuggestNothing() {
        for title in ["", "   ", "123", "Xqzt vrbl", "🙂", "The"] { XCTAssertEqual(Self.suggester.suggest(title), [], title) }
    }
    func testResultsAreUniqueLimitedAndInstalled() {
        let installed = Set(Self.lucide.map(\.id))
        for title in ["Go to the gym and lift weights after work", "Quit smoking", "Eat fruit and vegetables", "Medit"] {
            let icons = Self.suggester.suggest(title, limit: 5)
            XCTAssertLessThanOrEqual(icons.count, 5); XCTAssertEqual(Set(icons).count, icons.count, title)
            XCTAssertTrue(icons.allSatisfy(installed.contains), title)
        }
        XCTAssertEqual(Self.suggester.suggest("Gym", limit: 0), [])
        // Catalog icons that aren't installed are skipped rather than returned.
        let small = IconSuggester(icons: [IconSuggester.Entry(id: "lu:bed", name: "Bed", keywords: [])])
        XCTAssertEqual(small.suggest("Go to the gym"), [])
        XCTAssertEqual(small.suggest("Sleep"), ["lu:bed"])
    }
    func testStemmerJoinsWordForms() {
        for group in [["smoke", "smoking", "smoked", "smokes"], ["run", "running", "runs"], ["swim", "swimming"], ["study", "studying", "studied", "studies"],
                      ["candy", "candies"], ["journal", "journaling", "journalling"], ["meditate", "meditation", "meditating"], ["egg", "eggs"], ["up", "ups"],
                      ["dish", "dishes"], ["glass", "glasses"], ["hydrate", "hydration"], ["floss", "flossing"]] {
            XCTAssertEqual(Set(group.map(IconSuggester.stem)).count, 1, "\(group) → \(group.map(IconSuggester.stem))")
        }
        XCTAssertEqual(IconSuggester.words("Don't skip Café-time, 10 mins!"), ["dont", "skip", "cafe", "time", "mins"])
        XCTAssertEqual(IconSuggester.distance(Array("meditaiton".utf8), Array("meditation".utf8), limit: 2), 1)
    }
    func testSuggestingIsFast() {
        let titles = ["Go to the gym", "Quit smoking", "Meditaiton", "Drink 8 glasses of water", "No phone before bed", "Archery"]
        let start = Date()
        for _ in 0..<500 { for title in titles { _ = Self.suggester.suggest(title) } }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3, "3,000 suggestions; typing calls one per keystroke")
    }
}
