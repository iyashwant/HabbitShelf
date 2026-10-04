import XCTest
import UIKit

final class HabitBuddyUITests:XCTestCase {
    override func setUpWithError() throws {continueAfterFailure=false}
    private func launch(_ screen:String,theme:String="dark")->XCUIApplication {
        let app=XCUIApplication();app.launchEnvironment=["BUDDY_VISUAL_SCREEN":screen,"BUDDY_VISUAL_DATE":"2026-08-18","BUDDY_VISUAL_THEME":theme]
        app.launchArguments=["-AppleLanguages","(en)","-AppleLocale","en_US"];app.launch();XCTAssertTrue(app.wait(for:.runningForeground,timeout:15));return app
    }
    private func capture(_ app:XCUIApplication,_ name:String) {
        let shot=app.screenshot();let attachment=XCTAttachment(screenshot:shot);attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
        guard let bytes=shot.image.jpegData(compressionQuality:0.8)else{XCTFail("Screenshot encoding failed");return}
        let size=24_576,total=(bytes.count+size-1)/size
        for i in 0..<total{let part=bytes.subdata(in:i*size..<min(bytes.count,(i+1)*size));print("BUDDY_CAPTURE|\(name)|\(i)|\(total)|\(part.base64EncodedString())")}
    }
    func testReferenceScreenCaptures() {
        for screen in ["cards","compact","compact-settings","month","streaks","list","dashboard","today-ring","explore","insights","calendar","recap","notes-timeline","milestones","habit-milestones","routines","routine","timer","years","year-calendar","detail","editor","new-habit","statistics","notes","appearance","day","settings","theme","share","welcome"] {
            let app=launch(screen)
            switch screen {
            case "editor","new-habit","day":XCTAssertTrue(app.buttons["Save"].firstMatch.waitForExistence(timeout:20))
            case "share":XCTAssertTrue(app.buttons["Share Habit"].firstMatch.waitForExistence(timeout:20))
            case "settings":XCTAssertTrue(app.buttons["Close Settings"].waitForExistence(timeout:20))
            case "theme":XCTAssertTrue(app.buttons["Default"].waitForExistence(timeout:20))
            case "statistics":XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout:20))
            case "welcome":XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout:20))
            case "appearance":XCTAssertTrue(app.staticTexts["Appearance"].firstMatch.waitForExistence(timeout:20))
            case "compact-settings":XCTAssertTrue(app.buttons["5 days"].waitForExistence(timeout:20));sleep(1)
            case "notes":XCTAssertTrue(app.buttons["Close Notes"].waitForExistence(timeout:20))
            case "detail","years":XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout:20))
            case "dashboard","today-ring":XCTAssertTrue(app.buttons["Edit Dashboard"].waitForExistence(timeout:20))
            case "explore":XCTAssertTrue(app.buttons["explore-timer"].waitForExistence(timeout:20));sleep(2)
            case "insights","calendar","recap","notes-timeline","milestones","habit-milestones","routines":XCTAssertTrue(app.buttons["Back"].firstMatch.waitForExistence(timeout:20));sleep(2)
            case "routine":XCTAssertTrue(app.buttons["Complete All in Morning"].firstMatch.waitForExistence(timeout:20))
            case "timer":XCTAssertTrue(app.buttons["Start Timer"].waitForExistence(timeout:20))
            case "year-calendar":XCTAssertTrue(app.buttons["Share Year Calendar"].waitForExistence(timeout:20))
            default:XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout:20))
            }
            capture(app,screen+"-dark")
            if screen=="editor"{app.buttons["Choose Icon"].tap();XCTAssertTrue(app.textFields["Search icons or emoji"].waitForExistence(timeout:10));capture(app,"icons-dark")}
            app.terminate()
        }
        for screen in ["cards","welcome"]{let app=launch(screen,theme:"light");XCTAssertTrue(app.buttons[screen=="cards" ? "Settings":"Continue"].waitForExistence(timeout:20));capture(app,screen+"-light");app.terminate()}
        for screen in ["explore","insights","recap","today-ring"]{let app=launch(screen,theme:"light");XCTAssertTrue((screen=="explore" ? app.buttons["explore-timer"]:screen=="today-ring" ? app.buttons["Edit Dashboard"]:app.buttons["Back"].firstMatch).waitForExistence(timeout:20));sleep(2);capture(app,screen+"-light");app.terminate()}
    }
    func testSwitcherOpensDashboardAndExploreInPlace() {
        let app=launch("cards"),dashboard=app.buttons["Dashboard"],explore=app.buttons["Explore"]
        XCTAssertTrue(dashboard.waitForExistence(timeout:20));XCTAssertTrue(explore.exists)
        XCTAssertLessThan(app.buttons["list view"].frame.midX,dashboard.frame.midX,"Dashboard follows the layouts");XCTAssertLessThan(dashboard.frame.midX,explore.frame.midX,"Explore is last")
        dashboard.tap();XCTAssertTrue(app.buttons["Edit Dashboard"].waitForExistence(timeout:5));XCTAssertTrue(dashboard.isSelected);XCTAssertFalse(app.buttons["Back"].exists,"Dashboard opens in place")
        XCTAssertTrue(app.buttons["Settings"].exists);capture(app,"switcher-dashboard")
        explore.tap();XCTAssertTrue(app.buttons["explore-timer"].waitForExistence(timeout:5));XCTAssertTrue(explore.isSelected);XCTAssertFalse(app.buttons["Back"].exists,"Explore opens in place");capture(app,"switcher-explore")
        app.buttons.matching(NSPredicate(format:"label BEGINSWITH 'Insights'")).firstMatch.tap();XCTAssertTrue(app.buttons["Back"].firstMatch.waitForExistence(timeout:5));XCTAssertFalse(explore.isHittable,"Pages pushed from Explore cover the switcher")
        app.buttons["Back"].firstMatch.tap();XCTAssertTrue(app.buttons["explore-timer"].waitForExistence(timeout:5),"Back returns to Explore")
        app.buttons["cards view"].tap();XCTAssertTrue(app.buttons["Log progress for Gym Day"].waitForExistence(timeout:5));XCTAssertTrue(app.buttons["cards view"].isSelected);XCTAssertFalse(dashboard.isSelected)
    }
    func testCompletionPersistsAfterRelaunch() {
        let app=launch("cards"),button=app.buttons["Log progress for Gym Day"]
        XCTAssertTrue(button.waitForExistence(timeout:20));XCTAssertEqual(button.value as? String,"0");button.tap();XCTAssertEqual(button.value as? String,"1")
        app.terminate();app.launchEnvironment["BUDDY_VISUAL_RESET"]="false";app.launch();XCTAssertTrue(button.waitForExistence(timeout:20));XCTAssertEqual(button.value as? String,"1");button.tap();XCTAssertEqual(button.value as? String,"0")
    }
    func testCompactListSettings() {
        let app=launch("compact"),pill=app.buttons["Last 5 days"]
        XCTAssertTrue(pill.waitForExistence(timeout:20));XCTAssertTrue(app.buttons["Gym Day"].exists,"Names show by default")
        pill.tap();let three=app.buttons["3 days"];XCTAssertTrue(three.waitForExistence(timeout:10));XCTAssertTrue(app.buttons["5 days"].isSelected);XCTAssertTrue(app.buttons["Shown"].isSelected)
        three.tap();XCTAssertTrue(three.isSelected);XCTAssertFalse(app.buttons["5 days"].isSelected);XCTAssertTrue(app.buttons["Last 3 days"].waitForExistence(timeout:5),"The list behind the sheet follows the choice")
        app.buttons["Hidden"].tap();XCTAssertTrue(app.buttons["Hidden"].isSelected);capture(app,"compact-settings-changed")
        let title=app.staticTexts["Compact List Settings"];title.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.99)),withVelocity:.fast,thenHoldForDuration:0);XCTAssertTrue(title.waitForNonExistence(timeout:5),"Dragging the sheet down closes it")
        XCTAssertFalse(app.buttons["Gym Day"].exists,"Hidden names leave only the icons")
        app.terminate();app.launchEnvironment["BUDDY_VISUAL_RESET"]="false";app.launch()
        XCTAssertTrue(app.buttons["Last 3 days"].waitForExistence(timeout:20),"The day count is saved");XCTAssertFalse(app.buttons["Gym Day"].exists,"Hidden names are saved")
    }
    func testHoldingACardOpensItsMenu() {
        // Each hold starts from a fresh launch: tapping outside didn't always close the menu in the simulator.
        for part in ["name","check"] {
            let app=launch("cards"),check=app.buttons["Log progress for Gym Day"],menu=app.buttons["Complete Yesterday"]
            let held=part=="name" ? app.buttons.matching(NSPredicate(format:"label BEGINSWITH 'Gym Day'")).firstMatch:check
            XCTAssertTrue(held.waitForExistence(timeout:20));let before=check.value as? String
            held.press(forDuration:1.2);XCTAssertTrue(menu.waitForExistence(timeout:5),"Holding a card's \(part) opens the habit menu")
            XCTAssertFalse(app.buttons["Back"].exists,"rather than the habit");XCTAssertEqual(check.value as? String,before,"without logging")
            app.terminate()
        }
    }
    private func grid(_ app:XCUIApplication,_ habit:String)->XCUIElement { app.otherElements.matching(NSPredicate(format:"label BEGINSWITH %@",habit+", contribution grid")).firstMatch }
    func testDraggingACardByItsGridReordersHabits() {
        let app=launch("cards")
        func gymFirst()->Bool { app.buttons.matching(NSPredicate(format:"label BEGINSWITH 'Gym Day'")).firstMatch.frame.minY<app.buttons.matching(NSPredicate(format:"label BEGINSWITH 'Push-Ups'")).firstMatch.frame.minY }
        XCTAssertTrue(grid(app,"Gym Day").waitForExistence(timeout:20));XCTAssertTrue(gymFirst())
        grid(app,"Gym Day").press(forDuration:1.0,thenDragTo:grid(app,"Push-Ups"),withVelocity:.slow,thenHoldForDuration:1.0)
        let moved=expectation(for:NSPredicate{_,_ in !gymFirst()},evaluatedWith:nil);wait(for:[moved],timeout:10)
        app.terminate();app.launchEnvironment["BUDDY_VISUAL_RESET"]="false";app.launch()
        XCTAssertTrue(grid(app,"Gym Day").waitForExistence(timeout:20));XCTAssertFalse(gymFirst(),"The new order is saved")
    }
    func testCompactRowNameOpensHabitMenu() {
        let app=launch("compact"),name=app.buttons["Gym Day"]
        XCTAssertTrue(name.waitForExistence(timeout:20));name.press(forDuration:1.2)
        XCTAssertTrue(app.buttons["Complete Yesterday"].waitForExistence(timeout:5),"Holding a compact row's name opens the habit menu");XCTAssertFalse(app.buttons["Back"].exists,"rather than the habit")
    }
    func testThemeAccent() {
        let app=launch("theme"),teal=app.buttons["teal"],standard=app.buttons["Default"]
        XCTAssertTrue(teal.waitForExistence(timeout:20));XCTAssertTrue(standard.isSelected,"New installs keep the violet accent")
        teal.tap();XCTAssertTrue(teal.isSelected);XCTAssertFalse(standard.isSelected)
        app.buttons["Light"].tap();XCTAssertTrue(app.buttons["Light"].isSelected);sleep(1);capture(app,"theme-teal-light")
        app.terminate();app.launchEnvironment["BUDDY_VISUAL_RESET"]="false";app.launch()
        XCTAssertTrue(teal.waitForExistence(timeout:20));XCTAssertTrue(teal.isSelected,"The accent is saved");XCTAssertTrue(app.buttons["Light"].isSelected,"The appearance is saved")
        standard.tap();XCTAssertTrue(standard.isSelected);XCTAssertFalse(teal.isSelected)
        app.buttons["System"].tap();XCTAssertTrue(app.buttons["System"].isSelected);sleep(1);capture(app,"theme-system")
    }
    func testLiquidGlass() {
        let app=launch("theme"),glass=app.switches["Liquid Glass"]
        func reveal(_ element:XCUIElement) { for _ in 0..<8 where !(element.exists && element.isHittable) { app.swipeUp() } }
        func tint(_ name:String)->XCUIElement { app.buttons["\(name) tint"] }
        XCTAssertTrue(app.buttons["Default"].waitForExistence(timeout:20));reveal(glass)
        XCTAssertEqual(glass.value as? String,"0","Liquid Glass starts off");XCTAssertFalse(app.buttons["Frosted"].exists)
        glass.switches.firstMatch.tap();XCTAssertEqual(glass.value as? String,"1");sleep(1);capture(app,"theme-glass-on")
        let clear=app.buttons["Clear"];reveal(clear);XCTAssertTrue(app.buttons["System"].firstMatch.exists)
        clear.tap();XCTAssertTrue(clear.isSelected)
        reveal(tint("teal"));tint("teal").tap();XCTAssertTrue(tint("teal").isSelected);XCTAssertTrue(app.sliders["Tint Strength"].exists)
        sleep(1);capture(app,"theme-glass")
        app.buttons["Back"].tap();app.buttons["Close Settings"].tap();XCTAssertTrue(app.buttons["Create Habit"].waitForExistence(timeout:10));sleep(1);capture(app,"glass-clear-teal")
        app.terminate();app.launchEnvironment["BUDDY_VISUAL_RESET"]="false";app.launch()
        XCTAssertTrue(app.buttons["Default"].waitForExistence(timeout:20));reveal(glass);XCTAssertEqual(glass.value as? String,"1","The mode is saved")
        reveal(clear);XCTAssertTrue(clear.isSelected,"The transparency is saved");reveal(tint("teal"));XCTAssertTrue(tint("teal").isSelected,"The tint is saved")
        let frosted=app.buttons["Frosted"];reveal(frosted);frosted.tap();XCTAssertTrue(frosted.isSelected)
        app.buttons["Back"].tap();app.buttons["Close Settings"].tap();XCTAssertTrue(app.buttons["Create Habit"].waitForExistence(timeout:10));sleep(1);capture(app,"glass-frosted-teal")
        // The visual route keeps Settings opening on the Theme page.
        app.buttons["Settings"].tap();XCTAssertTrue(app.buttons["Default"].waitForExistence(timeout:10));reveal(glass);glass.switches.firstMatch.tap()
        XCTAssertEqual(glass.value as? String,"0");XCTAssertFalse(app.buttons["Frosted"].exists,"Turning the mode off hides its options")
    }
    func testHiddenHabitsLeaveEveryView() {
        let app=launch("compact")
        func hideRow(_ name:String)->XCUIElement{app.buttons.matching(NSPredicate(format:"identifier == 'hide-habit' AND label == %@",name)).firstMatch}
        XCTAssertTrue(app.buttons["Last 5 days"].waitForExistence(timeout:20));XCTAssertTrue(app.buttons["Gym Day"].exists);XCTAssertTrue(app.staticTexts["10 HABITS"].exists)
        app.buttons["Last 5 days"].tap();let row=app.buttons["Hidden Habits"];XCTAssertTrue(row.waitForExistence(timeout:10));XCTAssertEqual(row.value as? String,"None")
        row.tap();XCTAssertTrue(hideRow("Gym Day").waitForExistence(timeout:10))
        hideRow("Gym Day").tap();hideRow("Journal").tap()
        XCTAssertEqual(hideRow("Gym Day").value as? String,"Hidden");XCTAssertEqual(hideRow("Push-Ups").value as? String,"Shown");capture(app,"hide-habits")
        app.buttons["Close Hide Habits"].tap();XCTAssertTrue(row.waitForExistence(timeout:5));XCTAssertEqual(row.value as? String,"2 hidden")
        let title=app.staticTexts["Compact List Settings"];title.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.99)),withVelocity:.fast,thenHoldForDuration:0);XCTAssertTrue(title.waitForNonExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["8 HABITS"].waitForExistence(timeout:5),"The compact list counts only shown habits");XCTAssertFalse(app.buttons["Gym Day"].exists);XCTAssertFalse(app.buttons["Journal"].exists);XCTAssertTrue(app.buttons["Push-Ups"].exists)
        capture(app,"hidden-compact")
        app.buttons["cards view"].tap();XCTAssertTrue(app.buttons["Log progress for Push-Ups"].waitForExistence(timeout:5));XCTAssertFalse(app.buttons["Log progress for Gym Day"].exists,"Cards leave hidden habits out")
        app.terminate();app.launchEnvironment["BUDDY_VISUAL_RESET"]="false";app.launch()
        XCTAssertTrue(app.buttons["Log progress for Push-Ups"].waitForExistence(timeout:20));XCTAssertFalse(app.buttons["Log progress for Gym Day"].exists,"Hidden habits stay hidden after relaunch")
        app.buttons["Settings"].tap();let settingsRow=app.buttons["Hidden Habits"];XCTAssertTrue(settingsRow.waitForExistence(timeout:10));settingsRow.tap()
        let showAll=app.buttons["Show All Habits"];XCTAssertTrue(showAll.waitForExistence(timeout:10));showAll.tap();XCTAssertTrue(showAll.waitForNonExistence(timeout:5));XCTAssertEqual(hideRow("Gym Day").value as? String,"Shown")
        app.buttons["Close Hide Habits"].tap();app.buttons["Close Settings"].tap()
        XCTAssertTrue(app.buttons["Log progress for Gym Day"].waitForExistence(timeout:10),"Show All brings every habit back")
    }
    func testEditorValidationAndIconSearch() {
        let app=launch("new-habit");XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout:20));XCTAssertFalse(app.buttons["Save"].isEnabled,"Save stays disabled until the habit has a name.")
        let name=app.textFields["Habit name"];name.tap();name.typeText("Test Habit");app.buttons["Choose Icon"].tap();let search=app.textFields["Search icons or emoji"];XCTAssertTrue(search.waitForExistence(timeout:10));search.tap();search.typeText("dumbbell");app.buttons["Dumbbell"].firstMatch.tap();XCTAssertEqual(name.value as? String,"Test Habit");app.buttons["Save"].tap();XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout:10));let saved=app.buttons["Log progress for Test Habit"];for _ in 0..<6{if saved.exists{break};app.swipeUp()};XCTAssertTrue(saved.exists)
    }
    func testIconFollowsHabitName() {
        // Suggestions settle 250 ms after typing pauses.
        func settles(_ element:XCUIElement,_ value:String,_ message:String="") {
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@",value),object:element)],timeout:5),.completed,message.isEmpty ? "Icon becomes \(value)":message)
        }
        let app=launch("new-habit"),name=app.textFields["Habit name"],hero=app.buttons["Choose Icon"]
        XCTAssertTrue(name.waitForExistence(timeout:20));XCTAssertEqual(hero.value as? String,"Activity");XCTAssertFalse(app.buttons["Use Activity Icon"].exists)
        name.tap();name.typeText("Quit smoking")
        XCTAssertTrue(app.buttons["Use Cigarette Off Icon"].waitForExistence(timeout:5));XCTAssertTrue(app.buttons["Use Cigarette Icon"].exists);settles(hero,"Cigarette Off")
        name.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:12));settles(hero,"Activity","With no matching word the default icon returns")
        name.typeText("Go to the gym");XCTAssertTrue(app.buttons["Use Dumbbell Icon"].waitForExistence(timeout:5));settles(hero,"Dumbbell");capture(app,"icon-suggestions-gym")
        app.buttons["Use Biceps Flexed Icon"].tap();XCTAssertEqual(hero.value as? String,"Biceps Flexed")
        name.typeText(" and swim");XCTAssertTrue(app.buttons["Use Waves Ladder Icon"].waitForExistence(timeout:5),"Suggestions keep following the name")
        XCTAssertEqual(hero.value as? String,"Biceps Flexed","A chosen icon stays while the name changes")
        app.buttons["Save"].tap();XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout:10))
        let editing=launch("editor"),field=editing.textFields["Habit name"],icon=editing.buttons["Choose Icon"]
        XCTAssertTrue(field.waitForExistence(timeout:20));let original=icon.value as? String;XCTAssertTrue(editing.buttons["Use Dumbbell Icon"].exists,"Gym Day shows its suggestions")
        field.tap();field.typeText(" swim");XCTAssertTrue(editing.buttons["Use Waves Ladder Icon"].waitForExistence(timeout:5))
        XCTAssertEqual(icon.value as? String,original,"An existing habit's own icon is not replaced");capture(editing,"icon-suggestions-edit")
    }
    func testBackfillDaysBeforeHabitStart() {
        let app=launch("new-habit");let name=app.textFields["Habit name"];XCTAssertTrue(name.waitForExistence(timeout:20));name.tap();name.typeText("Backfill Habit");app.buttons["Save"].tap()
        let card=app.buttons["Log progress for Backfill Habit"];XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout:10));for _ in 0..<6{if card.exists{break};app.swipeUp()};app.staticTexts["Backfill Habit"].firstMatch.tap()
        func day(_ key:String)->XCUIElement{app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@",key+",")).firstMatch}
        let yesterday=day("2026-08-17");XCTAssertTrue(yesterday.waitForExistence(timeout:10));XCTAssertTrue(yesterday.isEnabled,"A day before the habit's start must accept a log.");yesterday.tap()
        XCTAssertTrue(app.buttons["2026-08-17, complete, 1"].waitForExistence(timeout:10))
        app.buttons["Previous month"].firstMatch.tap();let july=day("2026-07-10");XCTAssertTrue(july.waitForExistence(timeout:10));XCTAssertTrue(july.isEnabled);july.tap()
        XCTAssertTrue(app.buttons["2026-07-10, complete, 1"].waitForExistence(timeout:10));capture(app,"backfill-before-start")
    }
    func testDashboardCheckAndAddWidget() {
        let app=launch("dashboard"),check=app.buttons.matching(identifier:"Log progress for Gym Day")
        XCTAssertTrue(app.buttons["Edit Dashboard"].waitForExistence(timeout:20));XCTAssertTrue(check.firstMatch.waitForExistence(timeout:10))
        let before=check.count;XCTAssertEqual(check.firstMatch.value as? String,"Not done");check.firstMatch.tap();XCTAssertEqual(check.firstMatch.value as? String,"Done")
        app.buttons["Add Widget"].firstMatch.tap();let save=app.buttons["save-widget"];XCTAssertTrue(save.waitForExistence(timeout:10));save.tap()
        XCTAssertTrue(app.buttons["Edit Dashboard"].waitForExistence(timeout:10));for _ in 0..<6{if check.count>before{break};app.swipeUp()}
        XCTAssertGreaterThan(check.count,before,"The new streak widget for the first habit appears on the dashboard.")
        capture(app,"dashboard-added")
    }
    /// Holding a widget opens its menu; moving on lifts it, the others make room, and dropping it saves the order.
    func testDraggingADashboardWidgetReordersIt() {
        var app=launch("dashboard")
        func today()->XCUIElement { app.otherElements.matching(NSPredicate(format:"label BEGINSWITH 'Today, '")).firstMatch }
        func deepWork()->XCUIElement { app.staticTexts["Deep Work"].firstMatch }
        func todayFirst()->Bool { today().frame.minY<deepWork().frame.minY }
        // A synthesized hold sometimes leaves the menu open instead of handing the touch to the drag (iOS 27 simulator),
        // so the drag gets three tries, each from a fresh launch.
        var moved=false
        for attempt in 1...3 where !moved {
            if attempt>1 {app.terminate();app=launch("dashboard")}
            XCTAssertTrue(today().waitForExistence(timeout:20));XCTAssertTrue(todayFirst())
            today().press(forDuration:1.0,thenDragTo:deepWork(),withVelocity:.slow,thenHoldForDuration:1.0)
            moved=XCTWaiter().wait(for:[expectation(for:NSPredicate{_,_ in !todayFirst()},evaluatedWith:nil)],timeout:5) == .completed
            if !moved {print("Dashboard drag attempt \(attempt) didn't move the widget")}
        }
        XCTAssertTrue(moved,"Moving after the hold drags the widget to its new place");XCTAssertFalse(app.buttons["Duplicate"].exists,"and closes the menu")
        capture(app,"dashboard-dragged")
        app.terminate();app.launchEnvironment["BUDDY_VISUAL_RESET"]="false";app.launch()
        XCTAssertTrue(today().waitForExistence(timeout:20));XCTAssertFalse(todayFirst(),"The new order is saved")
        today().press(forDuration:1.2);XCTAssertTrue(app.buttons["Duplicate"].waitForExistence(timeout:5),"Holding without moving still opens the widget's menu");XCTAssertFalse(todayFirst())
    }
    /// Every dashboard design, size and option, captured a screen at a time.
    func testDashboardWidgetCaptures() {
        for (screen,theme,pages) in [("dashboard","dark",6),("widgets","dark",7),("widgets","light",7),("widget-config","dark",4)] {
            let app=launch(screen,theme:theme)
            XCTAssertTrue((screen=="widget-config" ? app.buttons["save-widget"]:app.buttons["Edit Dashboard"]).waitForExistence(timeout:20));sleep(1)
            for page in 0..<pages {
                if page>0 {app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.78)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.3)));sleep(1)}
                capture(app,"\(screen)-\(theme)-\(page)")
            }
            app.terminate()
        }
    }
    func testWidgetCustomization() {
        let app=launch("dashboard"),pushUps=app.buttons.matching(identifier:"Log progress for Push-Ups")
        XCTAssertTrue(app.buttons["Edit Dashboard"].waitForExistence(timeout:20));let before=pushUps.count
        app.buttons["Add Widget"].firstMatch.tap();let save=app.buttons["save-widget"];XCTAssertTrue(save.waitForExistence(timeout:10))
        app.buttons["Several Habits"].tap();app.buttons["Quick Check"].tap();app.buttons["Small"].tap();app.buttons["Gym Day"].firstMatch.tap();app.buttons["Push-Ups"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Shows 2 chosen. Tap a habit to add or remove it."].exists)
        capture(app,"widget-config-quick-check");save.tap()
        XCTAssertTrue(app.buttons["Edit Dashboard"].waitForExistence(timeout:10));XCTAssertEqual(pushUps.count,before+1,"The small quick check shows the chosen habits")
        let gym=app.buttons.matching(identifier:"Log progress for Gym Day"),added=gym.element(boundBy:gym.count-1);for _ in 0..<8{if added.isHittable{break};app.swipeUp()}
        XCTAssertEqual(added.value as? String,"Not done");added.tap();XCTAssertEqual(added.value as? String,"Done","A quick check icon logs today")
        added.press(forDuration:1.2);let duplicate=app.buttons["Duplicate"];XCTAssertTrue(duplicate.waitForExistence(timeout:10));duplicate.tap()
        XCTAssertTrue(app.buttons["Edit Dashboard"].waitForExistence(timeout:10));XCTAssertEqual(pushUps.count,before+2,"Duplicate adds a copy of the widget")
        capture(app,"dashboard-quick-check-added")
    }
    /// Opt-in, on a simulator kept for it: loads the sample habits into the real store, pages through Habit Buddy's
    /// widget gallery and adds widgets to the Home Screen. Widgets need the App Group, so build signed to run locally
    /// (without CODE_SIGNING_ALLOWED=NO) and pass TEST_RUNNER_BUDDY_HOME_WIDGETS=1.
    func testHomeScreenWidgetGallery() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BUDDY_HOME_WIDGETS"] == "1", "Changes the Home Screen; opt in with TEST_RUNNER_BUDDY_HOME_WIDGETS=1")
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(en)","-AppleLocale","en_US"];app.launch()
        if app.buttons["Continue"].waitForExistence(timeout:8){app.buttons["Continue"].tap()}
        if app.buttons["Try sample habits"].waitForExistence(timeout:8){app.buttons["Try sample habits"].tap()}
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout:10));sleep(2)
        // A second press leaves Home Screen editing if an earlier run stopped in it.
        XCUIDevice.shared.press(.home);sleep(2);XCUIDevice.shared.press(.home);sleep(1)
        let springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        func shot(_ name:String){let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
        func dump(_ step:String){print("SPRINGBOARD \(step)\n"+springboard.debugDescription)}
        func openGallery()->Bool {
            springboard.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.6)).press(forDuration:1.6)
            if !springboard.buttons["Edit"].waitForExistence(timeout:4) {
                let menu=springboard.buttons["Edit Home Screen"];guard menu.waitForExistence(timeout:3) else{dump("no edit mode");return false};menu.tap()
                guard springboard.buttons["Edit"].waitForExistence(timeout:5) else{dump("no edit button");return false}
            }
            springboard.buttons["Edit"].tap()
            let add=springboard.buttons["Add Widget"];guard add.waitForExistence(timeout:5) else{dump("no add widget");return false};add.tap()
            let cell=springboard.cells["Habit Buddy"];guard cell.waitForExistence(timeout:8) else{dump("no app cell");return false}
            for _ in 0..<4{if cell.isHittable{break};springboard.swipeUp()}
            cell.tap();return springboard.pageIndicators.firstMatch.waitForExistence(timeout:8)
        }
        let pager=springboard.pageIndicators.matching(NSPredicate(format:"value BEGINSWITH 'page '")).firstMatch
        func next(){springboard.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:0.6)).press(forDuration:0.05,thenDragTo:springboard.coordinate(withNormalizedOffset:CGVector(dx:0.15,dy:0.6)));sleep(2)}
        /// The preview on screen, such as "Habit Buddy, Quick Check|Widget, Medium".
        func showing()->String {
            let previews=springboard.buttons.matching(NSPredicate(format:"label BEGINSWITH 'Habit Buddy, '")).allElementsBoundByIndex
            return previews.first{$0.exists && $0.frame.minX>=0 && $0.frame.maxX<=springboard.frame.width}.map{"\($0.label)|\($0.value as? String ?? "")"} ?? ""
        }
        guard openGallery() else{XCTFail("Couldn't open Habit Buddy's widget gallery");return}
        sleep(2);var last=""
        for page in 0..<30 {
            let value=pager.value as? String ?? "";if value==last{break};last=value
            print("GALLERY_PAGE \(value) \(showing())");shot(String(format:"gallery-%02d",page));next()
        }
        XCTAssertEqual(last,"page 25 of 25","Every design and size is in the gallery")
        springboard.buttons["close"].firstMatch.tap();sleep(1);XCUIDevice.shared.press(.home);sleep(2)
        // Put a few designs on the Home Screen and use their buttons there.
        for (name,size) in [("This Year","Medium"),("Goal Ring","Small"),("Routine","Small"),("Quick Check","Medium")] {
            guard openGallery() else{XCTFail("Couldn't reopen the gallery");return}
            sleep(1);var found=false
            for _ in 0..<26 { if showing()=="Habit Buddy, \(name)|Widget, \(size)" {found=true;break};next() }
            XCTAssertTrue(found,"\(name) \(size) is in the gallery");guard found else{continue}
            springboard.buttons[" Add Widget"].firstMatch.tap();sleep(2)
            if springboard.buttons["Done"].waitForExistence(timeout:5){springboard.buttons["Done"].tap()};sleep(2);XCUIDevice.shared.press(.home);sleep(1)
        }
        sleep(3);shot("home-widgets");dump("home")
        let complete=springboard.buttons["Complete All in Morning"].firstMatch
        if complete.waitForExistence(timeout:5){complete.tap();sleep(4);shot("home-widgets-routine-done")}
        let gym=springboard.buttons["Log progress for Gym Day"].firstMatch
        if gym.waitForExistence(timeout:5){gym.tap();sleep(4);shot("home-widgets-gym-logged")}
        XCUIDevice.shared.press(.home);sleep(1);XCUIDevice.shared.press(.home)
    }
    func testRoutineWidgetCompletesRoutine() {
        let app=launch("widgets"),all=app.buttons["Complete All in Morning"].firstMatch
        XCTAssertTrue(all.waitForExistence(timeout:20));all.tap()
        XCTAssertTrue(app.descendants(matching:.any)["Morning is done"].firstMatch.waitForExistence(timeout:10),"Complete All in the routine widget finishes the routine")
        XCTAssertFalse(app.buttons["Complete All in Morning"].exists)
    }
    func testRoutineCompletesItsHabits() {
        let app=launch("routines"),all=app.buttons["Complete All in Morning"].firstMatch
        XCTAssertTrue(all.waitForExistence(timeout:20));XCTAssertTrue(all.isEnabled);all.tap()
        XCTAssertTrue(app.staticTexts["All 3 done today"].waitForExistence(timeout:10));XCTAssertFalse(all.isEnabled)
        app.buttons["Back"].firstMatch.tap();let meditate=app.buttons["Log progress for Meditate"]
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout:10));for _ in 0..<6{if meditate.exists{break};app.swipeUp()}
        XCTAssertTrue(meditate.exists);XCTAssertEqual(meditate.value as? String,"10","Completing the routine fills a measured habit to its target")
    }
    func testTimerLogsElapsedTimeWithLiveActivity() {
        let app=launch("timer"),start=app.buttons["Start Timer"]
        XCTAssertTrue(start.waitForExistence(timeout:20));app.buttons["Stopwatch"].tap();start.tap()
        let finish=app.buttons["finish-timer"];XCTAssertTrue(finish.waitForExistence(timeout:10));sleep(4)
        XCUIDevice.shared.press(.home);sleep(3)
        let home=XCTAttachment(screenshot:XCUIScreen.main.screenshot());home.name="timer-live-activity";home.lifetime = .keepAlways;add(home)
        app.activate();XCTAssertTrue(finish.waitForExistence(timeout:10));finish.tap()
        XCTAssertTrue(start.waitForExistence(timeout:10),"Finishing ends the timer")
        app.buttons["Close Timer"].tap();let meditate=app.buttons["Log progress for Meditate"];for _ in 0..<6{if meditate.exists{break};app.swipeUp()}
        XCTAssertTrue(meditate.exists);XCTAssertNotEqual(meditate.value as? String,"0","The elapsed minutes are logged")
    }
    func testLiveActivityFinishButtonLogsTimer() {
        let app=launch("timer"),start=app.buttons["Start Timer"]
        XCTAssertTrue(start.waitForExistence(timeout:20));app.buttons["Stopwatch"].tap();start.tap()
        XCTAssertTrue(app.buttons["finish-timer"].waitForExistence(timeout:10));sleep(3)
        // The Lock Screen presentation also appears in Notification Center, pulled down from the top edge.
        XCUIDevice.shared.press(.home);sleep(3)
        let springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard"),finish=springboard.buttons["Finish & Log"].firstMatch
        // The activity can take a moment to draw after the pull-down, so pull again if it isn't there yet.
        for _ in 0..<3 {
            springboard.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.002)).press(forDuration:0.1,thenDragTo:springboard.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.7)))
            if finish.waitForExistence(timeout:8){break}
            springboard.swipeUp();sleep(2)
        }
        let lock=XCTAttachment(screenshot:XCUIScreen.main.screenshot());lock.name="timer-lock-screen";lock.lifetime = .keepAlways;add(lock)
        XCTAssertTrue(finish.exists,"The Live Activity shows its Finish button");finish.tap();sleep(3)
        springboard.swipeUp();app.activate()
        XCTAssertTrue(start.waitForExistence(timeout:15),"The Live Activity's Finish ends the in-app timer too")
        app.buttons["Close Timer"].tap();let meditate=app.buttons["Log progress for Meditate"];for _ in 0..<6{if meditate.exists{break};app.swipeUp()}
        XCTAssertTrue(meditate.exists);XCTAssertNotEqual(meditate.value as? String,"0","The Live Activity's Finish logs the elapsed minutes")
    }
    func testNativeShareSheet() {
        let app=launch("share"),share=app.buttons["share-habit-image"]
        XCTAssertTrue(share.waitForExistence(timeout:20));share.tap()
        let action=app.descendants(matching:.any).matching(NSPredicate(format:"label == %@ OR label == %@","Copy","Save Image")).firstMatch
        let presented=action.waitForExistence(timeout:15)
        capture(app,"native-share")
        if !presented{print("SHARE_ACCESSIBILITY\n"+app.debugDescription)}
        XCTAssertTrue(presented,"The exported PNG must open a native image-sharing action.")
    }
}
