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
    func testOfflineLaunchKeepsTheMainTabsVisibleWithoutRestoringAccountSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-offline"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["today-screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts["目前為離線模式，待送內容會在恢復網路後重試。"]
                .waitForExistence(timeout: 1)
        )
        XCTAssertTrue(app.tabBars.buttons["今天"].exists)
        XCTAssertTrue(app.tabBars.buttons["對話"].exists)
        XCTAssertTrue(app.tabBars.buttons["我們"].exists)
        XCTAssertFalse(app.navigationBars["帳號設定"].exists)

        app.tabBars.buttons["對話"].tap()
        let input = app.textFields["conversation-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 1))
        input.tap()
        input.typeText("離線待送")
        app.buttons["send-conversation-message"].tap()

        XCTAssertTrue(app.staticTexts["離線待送"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["傳送失敗，點此重試"].waitForExistence(timeout: 2))
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
    func testShowsFailedMessageWithoutPresentingItAsSyncedOrRead() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-failed-message"]
        app.launch()

        app.tabBars.buttons["對話"].tap()
        XCTAssertTrue(app.staticTexts["第三則待重試"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["傳送失敗，點此重試"].waitForExistence(timeout: 1))
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "label == '傳送失敗，點此重試'")).count,
            3
        )
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '已讀'")).firstMatch.exists)
    }

    @MainActor
    func testChatPhotoReactionReplacementAndRemoval() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-w10-chat"]
        app.launch()

        app.tabBars.buttons["對話"].tap()
        let sourceMessage = app.staticTexts["晚餐後一起散步"]
        XCTAssertTrue(sourceMessage.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["已收藏為 Moment"].waitForExistence(timeout: 2))
        var photo = app.images["聊天照片"]
        XCTAssertTrue(photo.waitForExistence(timeout: 2))

        photo.tap()
        XCTAssertTrue(app.images["聊天照片預覽"].waitForExistence(timeout: 2))
        app.images["聊天照片預覽"].swipeDown()
        XCTAssertFalse(app.images["聊天照片預覽"].waitForExistence(timeout: 1))
        photo = app.images["聊天照片"]

        photo.press(forDuration: 1)
        XCTAssertTrue(app.buttons["關閉訊息選單"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["愛心"].waitForExistence(timeout: 1))
        app.buttons["愛心"].tap()
        XCTAssertTrue(app.staticTexts["愛心"].waitForExistence(timeout: 2))

        photo.press(forDuration: 1)
        XCTAssertTrue(app.buttons["微笑"].waitForExistence(timeout: 1))
        app.buttons["微笑"].tap()
        XCTAssertTrue(app.staticTexts["微笑"].waitForExistence(timeout: 2))

        photo.press(forDuration: 1)
        XCTAssertTrue(app.buttons["微笑"].waitForExistence(timeout: 1))
        app.buttons["微笑"].tap()
        XCTAssertFalse(app.staticTexts["微笑"].waitForExistence(timeout: 1))

        photo.press(forDuration: 1)
        XCTAssertTrue(app.buttons["收藏為 Moment"].waitForExistence(timeout: 1))
        app.buttons["收藏為 Moment"].tap()
        let savedMomentLabels = app.staticTexts.matching(
            NSPredicate(format: "label == '已收藏為 Moment'")
        )
        expectation(
            for: NSPredicate { _, _ in savedMomentLabels.count == 2 },
            evaluatedWith: app
        )
        waitForExpectations(timeout: 2)
    }

    @MainActor
    func testChatUsesSharedPickerForCustomEmojiReaction() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-w10-chat"]
        app.launch()

        app.tabBars.buttons["對話"].tap()
        let photo = app.images["聊天照片"]
        XCTAssertTrue(photo.waitForExistence(timeout: 3))
        photo.press(forDuration: 1)
        XCTAssertTrue(app.buttons["更多 Emoji"].waitForExistence(timeout: 1))
        app.buttons["更多 Emoji"].tap()

        let partyEmoji = app.buttons["custom-conversation-emoji-🥳"]
        XCTAssertTrue(partyEmoji.waitForExistence(timeout: 2))
        partyEmoji.tap()
        XCTAssertTrue(app.staticTexts["🥳"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testChatComposerAndTextLongPressUseSharedAppointmentForm() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-w10-chat"]
        app.launch()

        app.tabBars.buttons["對話"].tap()
        let composerAppointment = app.buttons["create-appointment-from-composer"]
        XCTAssertTrue(composerAppointment.waitForExistence(timeout: 3))
        composerAppointment.tap()
        XCTAssertTrue(app.navigationBars["建立共同約定"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.textFields["appointment-title"].value as? String, "標題")
        app.buttons["取消"].tap()

        let sourceMessage = app.staticTexts["晚餐後一起散步"]
        XCTAssertTrue(sourceMessage.waitForExistence(timeout: 2))
        sourceMessage.press(forDuration: 1)
        let createFromMessage = app.buttons["create-appointment-from-message"]
        XCTAssertTrue(createFromMessage.waitForExistence(timeout: 2))
        createFromMessage.tap()

        XCTAssertTrue(app.navigationBars["建立共同約定"].waitForExistence(timeout: 2))
        XCTAssertEqual(
            app.textFields["appointment-title"].value as? String,
            "晚餐後一起散步"
        )
        XCTAssertTrue(app.staticTexts["已帶入原訊息文字；請自行確認標題、日期與時間後再建立。"].exists)
    }

    @MainActor
    func testSavedMomentOpensAndHighlightsItsSourceConversation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-w10-chat"]
        app.launch()

        let sourceButton = app.buttons["查看原對話"]
        XCTAssertTrue(sourceButton.waitForExistence(timeout: 3))
        sourceButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["conversation-screen"].waitForExistence(timeout: 2))
        let sourceMessage = app.staticTexts["晚餐後一起散步"]
        XCTAssertTrue(sourceMessage.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["來源訊息"].waitForExistence(timeout: 2))
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
    func testCreatesSharedAppointmentFromToday() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let createButton = app.buttons["create-shared-appointment"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 3))
        if !createButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(createButton.isHittable)
        createButton.tap()

        XCTAssertTrue(app.navigationBars["建立共同約定"].waitForExistence(timeout: 2))
        let title = app.textFields["appointment-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 1))
        title.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 1) {
            title.tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        title.typeText("週末一起吃晚餐")
        app.buttons["confirm-shared-appointment"].tap()

        XCTAssertTrue(app.staticTexts["週末一起吃晚餐"].waitForExistence(timeout: 2))
        XCTAssertTrue(
            app.descendants(matching: .any)["next-shared-appointment"].exists
        )
    }

    @MainActor
    func testOpensEditsAndCancelsSharedAppointmentFromUs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-w11-appointments"]
        app.launch()

        app.tabBars.buttons["我們"].tap()
        let scheduleButton = app.buttons["open-shared-appointment-schedule"]
        XCTAssertTrue(scheduleButton.waitForExistence(timeout: 3))
        scheduleButton.tap()

        XCTAssertTrue(app.navigationBars["共同日程"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["週末一起吃晚餐"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["上週一起散步"].exists)
        app.staticTexts["週末一起吃晚餐"].tap()

        XCTAssertTrue(app.navigationBars["約定詳情"].waitForExistence(timeout: 2))
        app.buttons["edit-shared-appointment"].tap()
        XCTAssertTrue(app.navigationBars["編輯共同約定"].waitForExistence(timeout: 2))
        XCTAssertEqual(
            app.textFields["appointment-title"].value as? String,
            "週末一起吃晚餐"
        )
        app.buttons["取消"].tap()

        app.buttons["cancel-shared-appointment"].tap()
        XCTAssertTrue(app.alerts["要取消這筆共同約定嗎？"].waitForExistence(timeout: 1))
        app.alerts.buttons["取消約定"].tap()

        XCTAssertTrue(app.staticTexts["狀態, 已取消"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["edit-shared-appointment"].exists)
        XCTAssertTrue(
            app.staticTexts["這筆約定已取消；原內容會保留在你們的過往約定中。"].exists
        )
    }

    @MainActor
    func testConversationAppointmentCardOpensAndReflectsCancellation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-w11-appointments"]
        app.launch()

        app.tabBars.buttons["對話"].tap()
        let appointmentID = "a4000000-0000-0000-0000-000000000001"
        let card = app.descendants(matching: .any)[
            "conversation-appointment-card-\(appointmentID)"
        ]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.tap()

        XCTAssertTrue(app.navigationBars["約定詳情"].waitForExistence(timeout: 2))
        app.buttons["cancel-shared-appointment"].tap()
        XCTAssertTrue(app.alerts["要取消這筆共同約定嗎？"].waitForExistence(timeout: 1))
        app.alerts.buttons["取消約定"].tap()
        XCTAssertTrue(app.staticTexts["狀態, 已取消"].waitForExistence(timeout: 2))

        app.navigationBars["約定詳情"].buttons["對話"].tap()
        let cancelledStatus = app.descendants(matching: .any)[
            "conversation-appointment-status-\(appointmentID)"
        ]
        XCTAssertTrue(cancelledStatus.waitForExistence(timeout: 2))
    }

    @MainActor
    func testSharedAppointmentCalendarShowsSelectedDayAndScheduleCreateEntry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-w11-calendar"]
        app.launch()

        app.tabBars.buttons["我們"].tap()
        let scheduleButton = app.buttons["open-shared-appointment-schedule"]
        XCTAssertTrue(scheduleButton.waitForExistence(timeout: 3))
        scheduleButton.tap()

        let calendarButton = app.buttons["open-shared-appointment-calendar"]
        XCTAssertTrue(calendarButton.waitForExistence(timeout: 2))
        calendarButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["shared-appointment-calendar-screen"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.staticTexts["今天一起喝咖啡"].waitForExistence(timeout: 2))

        app.navigationBars["共同月曆"].buttons["共同日程"].tap()
        app.buttons["create-appointment-from-schedule"].tap()
        XCTAssertTrue(app.navigationBars["建立共同約定"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testAppointmentDiscussionSendsTextAndReusesEmojiActions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-w11-discussion"]
        app.launch()

        app.tabBars.buttons["我們"].tap()
        let scheduleButton = app.buttons["open-shared-appointment-schedule"]
        XCTAssertTrue(scheduleButton.waitForExistence(timeout: 3))
        scheduleButton.tap()
        XCTAssertTrue(app.staticTexts["週末去看展"].waitForExistence(timeout: 2))
        app.staticTexts["週末去看展"].tap()

        let discussionButton = app.buttons["open-appointment-discussion"]
        XCTAssertTrue(discussionButton.waitForExistence(timeout: 2))
        discussionButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["appointment-discussion-screen"]
                .waitForExistence(timeout: 2)
        )
        let partnerMessage = app.staticTexts["要不要先約下午兩點？"]
        XCTAssertTrue(partnerMessage.waitForExistence(timeout: 2))
        XCTAssertTrue(app.images["聊天照片"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["send-conversation-photo"].exists)
        XCTAssertFalse(app.buttons["create-appointment-from-composer"].exists)

        let input = app.descendants(matching: .any)["conversation-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 1))
        input.tap()
        input.typeText("我們兩點見")
        app.buttons["send-conversation-message"].tap()
        XCTAssertTrue(app.staticTexts["我們兩點見"].waitForExistence(timeout: 2))

        partnerMessage.press(forDuration: 1)
        let heart = app.buttons["愛心"]
        XCTAssertTrue(heart.waitForExistence(timeout: 2))
        heart.tap()
        XCTAssertTrue(app.staticTexts["愛心"].waitForExistence(timeout: 2))

        partnerMessage.press(forDuration: 1)
        let saveMoment = app.buttons["收藏為 Moment"]
        XCTAssertTrue(saveMoment.waitForExistence(timeout: 2))
    }

    @MainActor
    func testMomentReturnsToExactAppointmentDiscussionMessage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-w11-discussion"]
        app.launch()

        XCTAssertTrue(app.staticTexts["從約定留下的 Moment"].waitForExistence(timeout: 3))
        let openSource = app.buttons["查看原對話"]
        XCTAssertTrue(openSource.waitForExistence(timeout: 2))
        openSource.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["appointment-discussion-screen"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts["來源訊息"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["要不要先約下午兩點？"].exists)
    }

    @MainActor
    func testSourceNavigationReplacesAppointmentAndMainConversationRoutes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-w11-source-routing"]
        app.launch()

        XCTAssertTrue(app.staticTexts["第一個約定來源"].waitForExistence(timeout: 3))
        app.buttons["查看原對話"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["appointment-discussion-screen"]
                .waitForExistence(timeout: 3)
        )

        app.tabBars.buttons["我們"].tap()
        XCTAssertTrue(app.staticTexts["第二個約定來源"].waitForExistence(timeout: 2))
        let sourceButtons = app.buttons.matching(
            NSPredicate(format: "label == '查看原對話'")
        )
        XCTAssertEqual(sourceButtons.count, 3)
        sourceButtons.element(boundBy: 2).tap()

        let secondSourceMessage = app.staticTexts
            .matching(identifier: "conversation-message-d4000000-0000-0000-0000-000000000022")
            .matching(NSPredicate(format: "label == '第二個約定來源訊息'"))
            .firstMatch
        XCTAssertTrue(secondSourceMessage.waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts
                .matching(
                    identifier: "conversation-message-d4000000-0000-0000-0000-000000000022"
                )
                .matching(NSPredicate(format: "label == '來源訊息'"))
                .firstMatch
                .exists
        )

        app.tabBars.buttons["我們"].tap()
        XCTAssertTrue(app.staticTexts["一般聊天來源"].waitForExistence(timeout: 2))
        app.buttons.matching(NSPredicate(format: "label == '查看原對話'"))
            .element(boundBy: 1)
            .tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["conversation-screen"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertFalse(app.descendants(matching: .any)["appointment-discussion-screen"].exists)
        let mainSourceMessage = app.staticTexts
            .matching(identifier: "conversation-message-d4000000-0000-0000-0000-000000000030")
            .matching(NSPredicate(format: "label == '一般聊天來源訊息'"))
            .firstMatch
        XCTAssertTrue(mainSourceMessage.waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts
                .matching(
                    identifier: "conversation-message-d4000000-0000-0000-0000-000000000030"
                )
                .matching(NSPredicate(format: "label == '來源訊息'"))
                .firstMatch
                .exists
        )
    }

    @MainActor
    func testConversationOpensRecentlyUpdatedAppointmentDiscussion() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-w11-discussion"]
        app.launch()

        app.tabBars.buttons["對話"].tap()
        XCTAssertTrue(app.staticTexts["近期約定討論"].waitForExistence(timeout: 3))
        let recentDiscussion = app.buttons[
            "recent-appointment-discussion-a4000000-0000-0000-0000-000000000004"
        ]
        XCTAssertTrue(recentDiscussion.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["未讀 2 則"].exists)
        recentDiscussion.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["appointment-discussion-screen"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.staticTexts["週末去看展"].exists)
        XCTAssertTrue(app.images["聊天照片"].waitForExistence(timeout: 2))
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
