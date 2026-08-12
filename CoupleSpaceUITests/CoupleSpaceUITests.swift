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
        XCUIDevice.shared.orientation = .portrait
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
    func testReadsPartnerMessageAndSendsBasicTextChat() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-partner-message"]
        app.launch()

        app.tabBars.buttons["對話"].tap()
        XCTAssertTrue(app.staticTexts["晚點一起吃飯嗎？"].waitForExistence(timeout: 3))

        let input = app.textFields["conversation-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 1))
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        input.typeText("好，晚點見")
        app.buttons["send-conversation-message"].tap()

        XCTAssertTrue(app.staticTexts["好，晚點見"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '已讀'")).firstMatch.exists)
        app.staticTexts["晚點一起吃飯嗎？"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))
        app.tabBars.buttons["今天"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testCreatesShortTextMomentAndShowsItInSharedTimeline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let createMomentButton = app.buttons["create-moment"]
        XCTAssertTrue(createMomentButton.waitForExistence(timeout: 3))
        if !createMomentButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(createMomentButton.isHittable)
        createMomentButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["moment-composer"].waitForExistence(timeout: 1))

        app.buttons["一句話"].tap()
        let editor = app.textViews["moment-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 1))
        editor.tap()
        editor.typeText("今天看到漂亮的天空")
        app.buttons["save-moment"].tap()

        XCTAssertTrue(app.staticTexts["今天看到漂亮的天空"].waitForExistence(timeout: 2))
        app.tabBars.buttons["我們"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["moment-timeline"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["今天看到漂亮的天空"].exists)
    }

    @MainActor
    func testSetsAndClearsCurrentStatusWithoutCreatingHistoryByDefault() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let partnerStatusCard = app.staticTexts
            .matching(identifier: "partner-status-card")
            .firstMatch
        let currentStatusCard = app.descendants(matching: .any)["current-user-status-card"]
        XCTAssertTrue(partnerStatusCard.waitForExistence(timeout: 3))
        XCTAssertTrue(currentStatusCard.waitForExistence(timeout: 3))
        XCTAssertLessThan(partnerStatusCard.frame.midX, currentStatusCard.frame.midX)
        currentStatusCard.tap()
        XCTAssertTrue(app.navigationBars["更新此刻狀態"].waitForExistence(timeout: 1))
        XCTAssertEqual(app.switches["save-status-as-moment"].value as? String, "0")
        app.buttons["save-current-status"].tap()

        XCTAssertTrue(app.staticTexts["忙一下，晚點聊"].waitForExistence(timeout: 2))
        app.descendants(matching: .any)["current-user-status-card"].tap()
        XCTAssertTrue(app.buttons["clear-current-status"].waitForExistence(timeout: 1))
        app.buttons["clear-current-status"].tap()
        XCTAssertTrue(app.staticTexts["尚未設定"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testSavesDisplayNameAndPrivatePartnerNameFromAccountSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-partner-moment"]
        app.launch()

        XCTAssertTrue(app.staticTexts["伴侶留下的"].waitForExistence(timeout: 3))

        app.tabBars.buttons["我們"].tap()
        app.buttons["account-settings"].tap()

        let displayName = app.textFields["display-name-input"]
        XCTAssertTrue(displayName.waitForExistence(timeout: 1))
        displayName.tap()
        displayName.typeText("小日")
        let partnerName = app.textFields["private-partner-name-input"]
        partnerName.tap()
        partnerName.typeText("小月亮")
        app.buttons["save-relationship-names"].tap()

        XCTAssertTrue(app.staticTexts["稱呼已更新。"].waitForExistence(timeout: 2))
        app.buttons["完成"].tap()
        app.tabBars.buttons["今天"].tap()
        XCTAssertTrue(app.staticTexts["小日"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["小月亮"].exists)
        XCTAssertTrue(
            app.staticTexts["小月亮留下的"].exists,
            "Existing Moment history should immediately use the current private partner name."
        )

        app.tabBars.buttons["我們"].tap()
        app.buttons["account-settings"].tap()
        XCTAssertTrue(app.buttons["clear-display-name"].waitForExistence(timeout: 1))
        app.buttons["clear-display-name"].tap()
        expectation(
            for: NSPredicate(format: "isEnabled == true"),
            evaluatedWith: app.buttons["clear-private-partner-name"]
        )
        waitForExpectations(timeout: 2)
        XCTAssertEqual(partnerName.value as? String, "小月亮")
        app.buttons["clear-private-partner-name"].tap()

        app.buttons["完成"].tap()
        app.tabBars.buttons["今天"].tap()
        XCTAssertTrue(app.staticTexts["我"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["伴侶"].exists)
        XCTAssertTrue(
            app.staticTexts["伴侶留下的"].exists,
            "Clearing each saved name should restore the history fallback labels."
        )
    }

    @MainActor
    func testPhotoMomentDoesNotBlockOpeningComposerAgain() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-photo-moment"]
        app.launch()

        XCTAssertTrue(app.images["moment-card"].waitForExistence(timeout: 3))
        app.buttons["create-moment"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["moment-composer"].waitForExistence(timeout: 1),
            "A displayed photo must not intercept taps intended for the Moment button."
        )
    }

    @MainActor
    func testRespondsToPartnerMomentWithEmoji() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-partner-moment"]
        app.launch()

        let hugButton = app.buttons["moment-emoji-hug"]
        XCTAssertTrue(hugButton.waitForExistence(timeout: 3))
        hugButton.tap()
        XCTAssertTrue(app.staticTexts["我的回應"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testRespondsToPartnerMomentWithCustomEmoji() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-partner-moment"]
        app.launch()

        let moreButton = app.buttons["more-moment-emoji"]
        XCTAssertTrue(moreButton.waitForExistence(timeout: 3))
        moreButton.tap()

        let partyEmoji = app.buttons["custom-moment-emoji-🥳"]
        XCTAssertTrue(partyEmoji.waitForExistence(timeout: 1))
        partyEmoji.tap()

        XCTAssertTrue(app.staticTexts["🥳"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testRespondsToPartnerMomentWithShortText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-partner-moment"]
        app.launch()

        let responseButton = app.buttons["回一句"]
        if !responseButton.waitForExistence(timeout: 1) {
            app.swipeUp()
        }
        XCTAssertTrue(responseButton.waitForExistence(timeout: 3))
        responseButton.tap()
        let editor = app.textViews["moment-response-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 1))
        editor.tap()
        editor.typeText("抱抱你，晚點一起休息")
        app.buttons["save-moment-response"].tap()

        XCTAssertTrue(app.staticTexts["抱抱你，晚點一起休息"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testAnswersPartnerQuestionAndRevealsBothAnswers() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-partner-question"]
        app.launch()

        let answerButton = app.buttons["回答這一題"]
        if !answerButton.waitForExistence(timeout: 1) {
            app.swipeUp()
        }
        XCTAssertTrue(answerButton.waitForExistence(timeout: 3))
        answerButton.tap()

        let editor = app.textViews["partner-question-answer-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 1))
        XCTAssertTrue(editor.isHittable)
        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        editor.typeText("有人陪我吃飯")
        app.buttons["save-question-answer"].tap()

        app.swipeUp()
        XCTAssertTrue(app.staticTexts["下班一起吃飯"].exists)
        XCTAssertTrue(app.staticTexts["有人陪我吃飯"].exists)
    }

    @MainActor
    func testCreatesQuestionMomentAndWaitsForJointReveal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(app.buttons["create-question-moment"].waitForExistence(timeout: 3))
        app.buttons["create-question-moment"].tap()
        let editor = app.textViews["question-answer-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 1))
        editor.tap()
        editor.typeText("希望你知道我今天有點累")
        app.buttons["save-question-moment"].tap()

        app.swipeUp()
        XCTAssertTrue(
            app.staticTexts["回答已送出，等對方有空時一起揭曉。"].waitForExistence(timeout: 2)
        )
    }

    @MainActor
    func testAccountSettingsUsesAnAlertAndKeepsW1ValidationToolsReachable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        app.tabBars.buttons["我們"].tap()
        app.buttons["account-settings"].tap()

        let signOutButton = app.buttons["登出"]
        if !signOutButton.waitForExistence(timeout: 1) {
            app.swipeUp()
        }
        XCTAssertTrue(signOutButton.waitForExistence(timeout: 2))
        signOutButton.tap()
        XCTAssertTrue(app.alerts["要登出 CoupleSpace 嗎？"].waitForExistence(timeout: 1))
        app.alerts.buttons["取消"].tap()

        let toolsButton = app.buttons["w1-technical-tools"]
        XCTAssertTrue(toolsButton.waitForExistence(timeout: 1))
        toolsButton.tap()
        XCTAssertTrue(app.navigationBars["W1 技術驗證"].waitForExistence(timeout: 2))
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
