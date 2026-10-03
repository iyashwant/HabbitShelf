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
        for screen in ["cards","compact","month","streaks","list","dashboard","today-ring","explore","insights","calendar","recap","notes-timeline","milestones","habit-milestones","routines","routine","timer","years","year-calendar","detail","editor","new-habit","statistics","notes","appearance","day","settings","share","welcome"] {
            let app=launch(screen)
            switch screen {
            case "editor","new-habit","day":XCTAssertTrue(app.buttons["Save"].firstMatch.waitForExistence(timeout:20))
            case "share":XCTAssertTrue(app.buttons["Share Habit"].firstMatch.waitForExistence(timeout:20))
            case "settings":XCTAssertTrue(app.buttons["Close Settings"].waitForExistence(timeout:20))
            case "statistics":XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout:20))
            case "welcome":XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout:20))
            case "appearance":XCTAssertTrue(app.staticTexts["Appearance"].firstMatch.waitForExistence(timeout:20))
            case "notes":XCTAssertTrue(app.buttons["Close Notes"].waitForExistence(timeout:20))
            case "detail","years":XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout:20))
            case "dashboard","today-ring":XCTAssertTrue(app.buttons["Edit Dashboard"].waitForExistence(timeout:20))
            case "insights","calendar","recap","notes-timeline","milestones","habit-milestones","routines","explore":XCTAssertTrue(app.buttons["Back"].firstMatch.waitForExistence(timeout:20));sleep(2)
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
        for screen in ["explore","insights","recap","today-ring"]{let app=launch(screen,theme:"light");XCTAssertTrue(app.buttons["Back"].firstMatch.waitForExistence(timeout:20));sleep(2);capture(app,screen+"-light");app.terminate()}
    }
    func testCompletionPersistsAfterRelaunch() {
        let app=launch("cards"),button=app.buttons["Log progress for Gym Day"]
        XCTAssertTrue(button.waitForExistence(timeout:20));XCTAssertEqual(button.value as? String,"0");button.tap();XCTAssertEqual(button.value as? String,"1")
        app.terminate();app.launchEnvironment["BUDDY_VISUAL_RESET"]="false";app.launch();XCTAssertTrue(button.waitForExistence(timeout:20));XCTAssertEqual(button.value as? String,"1");button.tap();XCTAssertEqual(button.value as? String,"0")
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
