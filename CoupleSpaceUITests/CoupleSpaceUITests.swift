//
//  CoupleSpaceUITests.swift
//  CoupleSpaceUITests
//
//  Created by titus on 2026/7/29.
//

import XCTest

final class CoupleSpaceUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testLaunchAnimationCompletes() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["main-content"].waitForExistence(timeout: 3),
            "The launch animation should finish and reveal the app content."
        )
    }

    @MainActor
    func testPrimaryNavigationStartsOnTodayAndSwitchesTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 3))

        app.tabBars.buttons["對話"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["conversation-screen"].waitForExistence(timeout: 1))

        app.tabBars.buttons["我們"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["us-screen"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testPairingEntryRequiresACompleteInvitationCode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-pairing"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["pairing-screen"].waitForExistence(timeout: 3))

        let acceptButton = app.buttons["accept-pairing-invitation"]
        let declineButton = app.buttons["decline-pairing-invitation"]
        XCTAssertFalse(acceptButton.isEnabled)
        XCTAssertFalse(declineButton.isEnabled)

        app.textFields["pairing-invitation-input"].tap()
        app.textFields["pairing-invitation-input"].typeText("11111111-2222-4333-8444-555555555555")

        XCTAssertTrue(acceptButton.isEnabled)
        XCTAssertTrue(declineButton.isEnabled)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
