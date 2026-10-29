import XCTest

/// Walks the Food flow for the CI screen recording: Georgia Tech → a dining hall's menu → staples → Panda Express → outside food.
final class FoodDemoTests: XCTestCase {
    private let app = XCUIApplication()

    private func pause(_ seconds: TimeInterval = 1.2) { Thread.sleep(forTimeInterval: seconds) }

    /// A campus place's row; its label also has the kind and location after the name.
    private func place(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    private func logFirst(containing text: String, moreServings: Bool = false) {
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
        guard row.waitForExistence(timeout: 10) else { return }
        row.tap()
        pause()
        if moreServings { app.steppers.firstMatch.buttons.element(boundBy: 1).tap(); pause(0.8) }
        app.buttons["Log"].tap()
        pause()
    }

    private func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        pause()
    }

    func testFoodFlowDemo() throws {
        continueAfterFailure = true
        addUIInterruptionMonitor(withDescription: "alerts") { alert in
            for label in ["Allow", "Don't Allow", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        // Dining halls only show for Georgia Tech; "-campus gatech" sets that pref for this launch.
        app.launchArguments = ["-uiDemo", "-campus", "gatech"]
        app.launch()
        pause(2)

        app.tabBars.buttons["Food"].tap()
        pause(2)
        app.buttons["Georgia Tech"].tap()
        pause()
        place("North Ave Dining Hall").tap()
        _ = app.staticTexts["Loading today's menu"].waitForNonExistence(timeout: 20)
        pause(2)
        app.swipeUp()
        pause()
        app.swipeDown()
        pause()
        logFirst(containing: "kcal", moreServings: true)

        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) {
            search.tap()
            search.typeText("Cheerios")
            pause()
            logFirst(containing: "Cheerios")
            // The search bar's dismiss button is "Cancel" before iOS 26 and a close button after.
            if let dismiss = ["Cancel", "Close", "Clear text"].map({ app.buttons[$0].firstMatch }).first(where: \.exists) {
                dismiss.tap()
            }
            pause()
        }
        app.swipeUp()
        app.swipeUp()
        pause(1.5)
        back()
        pause()
        // Another campus place: the Student Center's Panda Express.
        let panda = place("Panda Express")
        for _ in 0..<4 where !panda.isHittable { app.swipeUp() }
        panda.tap()
        pause()
        logFirst(containing: "kcal")
        back()
        back()
        pause(2)

        app.buttons["Outside food"].tap()
        pause()
        app.buttons["Chick-fil-A"].tap()
        pause()
        logFirst(containing: "sandwich")
        back()
        back()
        pause(3)
    }
}
