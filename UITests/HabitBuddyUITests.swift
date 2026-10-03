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
        for screen in ["cards","compact","month","detail","editor","new-habit","statistics","notes","appearance","day","settings","share","welcome"] {
            let app=launch(screen)
            switch screen {
            case "editor","new-habit","day":XCTAssertTrue(app.buttons["Save"].firstMatch.waitForExistence(timeout:20))
            case "share":XCTAssertTrue(app.buttons["Share Habit"].firstMatch.waitForExistence(timeout:20))
            case "settings","statistics":XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout:20))
            case "welcome":XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout:20))
            case "appearance":XCTAssertTrue(app.staticTexts["Appearance"].firstMatch.waitForExistence(timeout:20))
            case "notes":XCTAssertTrue(app.buttons["Close Notes"].waitForExistence(timeout:20))
            case "detail":XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout:20))
            default:XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout:20))
            }
            capture(app,screen+"-dark")
            if screen=="editor"{app.buttons["Choose Icon"].tap();XCTAssertTrue(app.textFields["Search icons or emoji"].waitForExistence(timeout:10));capture(app,"icons-dark")}
            app.terminate()
        }
        for screen in ["cards","welcome"]{let app=launch(screen,theme:"light");XCTAssertTrue(app.buttons[screen=="cards" ? "Settings":"Continue"].waitForExistence(timeout:20));capture(app,screen+"-light");app.terminate()}
    }
    func testCompletionPersistsAfterRelaunch() {
        let app=launch("cards"),button=app.buttons["Log progress for Gym Day"]
        XCTAssertTrue(button.waitForExistence(timeout:20));XCTAssertEqual(button.value as? String,"0");button.tap();XCTAssertEqual(button.value as? String,"1")
        app.terminate();app.launchEnvironment["BUDDY_VISUAL_RESET"]="false";app.launch();XCTAssertTrue(button.waitForExistence(timeout:20));XCTAssertEqual(button.value as? String,"1");button.tap();XCTAssertEqual(button.value as? String,"0")
    }
    func testEditorValidationAndIconSearch() {
        let app=launch("new-habit");XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout:20));app.buttons["Save"].tap();XCTAssertTrue(app.staticTexts["editor-error"].waitForExistence(timeout:10))
        let name=app.textFields["Habit name"];name.tap();name.typeText("Test Habit");app.buttons["Choose Icon"].tap();let search=app.textFields["Search icons or emoji"];XCTAssertTrue(search.waitForExistence(timeout:10));search.tap();search.typeText("dumbbell");app.buttons["Dumbbell"].tap();XCTAssertEqual(name.value as? String,"Test Habit");app.buttons["Save"].tap();XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout:10));let saved=app.buttons["Log progress for Test Habit"];for _ in 0..<6{if saved.exists{break};app.swipeUp()};XCTAssertTrue(saved.exists)
    }
    func testNativeShareSheet() {
        let app=launch("share");XCTAssertTrue(app.buttons["Share Habit"].firstMatch.waitForExistence(timeout:20));app.buttons["Share Habit"].firstMatch.tap();capture(app,"native-share");XCTAssertTrue(app.otherElements["native-share-sheet"].waitForExistence(timeout:15))
    }
}
