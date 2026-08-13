import Foundation
import Testing
#if os(iOS)
import UIKit
#endif
@testable import CoupleSpace

struct AppSkeletonTests {
    @Test func uiTestingLaunchOptionIsExplicitAndOrderIndependent() {
        #expect(AppLaunchOptions(arguments: []).isUITesting == false)
        #expect(AppLaunchOptions(arguments: ["--other", "--ui-testing"]).isUITesting)
        #expect(AppLaunchOptions(arguments: ["--ui-testing-pairing"]).isPairingUITesting)
    }

#if os(iOS)
    @Test func systemAndInAppLaunchBackgroundShareTheNamedAsset() {
        let launchScreen = Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen") as? [String: Any]

        #expect(launchScreen?["UIColorName"] as? String == "LaunchBackground")
        #expect(UIColor(named: "LaunchBackground", in: .main, compatibleWith: nil) != nil)
    }
#endif

    @Test func appConfigurationLoadsExplicitRuntimeAndSupabaseSettings() throws {
        let configuration = try AppConfiguration(values: [
            "AppEnvironment": "test",
            "SupabaseURL": "https://example.supabase.co",
            "SupabasePublishableKey": "sb_publishable_test",
        ])

        #expect(configuration.runtimeEnvironment == .test)
        #expect(configuration.supabase.url == URL(string: "https://example.supabase.co"))
    }

    @Test func appConfigurationRejectsUnknownRuntimeEnvironment() {
        #expect(throws: AppConfigurationError.invalidRuntimeEnvironment) {
            try AppConfiguration(values: [
                "AppEnvironment": "unknown",
                "SupabaseURL": "https://example.supabase.co",
                "SupabasePublishableKey": "sb_publishable_test",
            ])
        }
    }

    @Test func primarySectionsStayInAcceptedOrderAndOpenOnToday() {
        #expect(PrimarySection.allCases == [.today, .conversation, .us])
        #expect(PrimarySection.defaultSelection == .today)
    }

    @Test func chatTextPolicyNormalizesContentAndRejectsInvalidMessages() {
        #expect(ChatTextPolicy.normalizedBody("  晚點一起吃飯  ") == "晚點一起吃飯")
        #expect(ChatTextPolicy.normalizedBody(" \n\t ") == nil)
        #expect(ChatTextPolicy.normalizedBody(
            String(repeating: "a", count: ChatTextPolicy.maximumLength + 1)
        ) == nil)
    }

    @Test func conversationOutboxPersistsFIFOAndIsolatesAccountsAndRelationships() throws {
        let suiteName = "ConversationOutboxTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ConversationOutboxStore(defaults: defaults)
        let userID = UUID()
        let relationshipID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        var queue = ConversationOutboxQueue()
        try queue.enqueue(ConversationOutboxEntry(
            userID: userID,
            relationshipID: relationshipID,
            clientID: firstID,
            body: "第一則",
            localCreatedAt: Date(timeIntervalSince1970: 100),
            attemptCount: 0
        ))
        try queue.enqueue(ConversationOutboxEntry(
            userID: userID,
            relationshipID: relationshipID,
            clientID: secondID,
            body: "第二則",
            localCreatedAt: Date(timeIntervalSince1970: 101),
            attemptCount: 0
        ))
        try store.save(queue, userID: userID, relationshipID: relationshipID)

        var restored = try store.load(userID: userID, relationshipID: relationshipID)
        #expect(restored.entries.map(\.clientID) == [firstID, secondID])
        #expect(restored.beginFirstAttempt()?.clientID == firstID)
        #expect(restored.entries.first?.attemptCount == 1)
        #expect(restored.messages.allSatisfy { $0.deliveryState == .failed })
        try restored.acknowledgeFirst(clientID: firstID)
        try store.save(restored, userID: userID, relationshipID: relationshipID)
        #expect(try store.load(userID: userID, relationshipID: relationshipID).entries.map(\.clientID) == [secondID])
        #expect(try store.load(userID: UUID(), relationshipID: relationshipID).isEmpty)
        #expect(try store.load(userID: userID, relationshipID: UUID()).isEmpty)
        store.clearAll(userID: userID)
        #expect(try store.load(userID: userID, relationshipID: relationshipID).isEmpty)
    }

    @Test func conversationSnapshotPersistsRecentSyncedMessagesAndIsolatesScope() throws {
        let suiteName = "ConversationSnapshotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ConversationSnapshotStore(defaults: defaults)
        let userID = UUID()
        let relationshipID = UUID()
        let messages = (0..<(ConversationLocalSnapshotPolicy.maximumMessageCount + 1)).map { index in
            ChatMessage(
                id: UUID(),
                senderUserID: userID,
                body: "訊息 \(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        try store.save(
            ConversationSnapshot(currentUserID: userID, messages: messages, unreadCount: 3),
            userID: userID,
            relationshipID: relationshipID
        )

        let loaded = try store.load(userID: userID, relationshipID: relationshipID)
        let restored = try #require(loaded)
        #expect(restored.messages.count == ConversationLocalSnapshotPolicy.maximumMessageCount)
        #expect(restored.messages.first?.body == "訊息 1")
        #expect(restored.messages.last?.body == "訊息 200")
        #expect(restored.unreadCount == 3)
        #expect(try store.load(userID: UUID(), relationshipID: relationshipID) == nil)
        #expect(try store.load(userID: userID, relationshipID: UUID()) == nil)

        store.clearAll(userID: userID)
        #expect(try store.load(userID: userID, relationshipID: relationshipID) == nil)
    }

    @Test func todaySnapshotPersistsMomentsStatusAndPhotoWithinAccountRelationshipScope() throws {
        let suiteName = "TodaySnapshotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let photoRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodaySnapshotTests.\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: photoRootURL)
        }
        let store = TodaySnapshotStore(defaults: defaults, photoRootURL: photoRootURL)
        let userID = UUID()
        let relationshipID = UUID()
        let partnerUserID = UUID()
        let momentID = UUID()
        let moment = Moment(
            id: momentID,
            creatorUserID: partnerUserID,
            content: .question(MomentQuestion(key: "understand_today", prompt: "題目")),
            createdAt: Date(timeIntervalSince1970: 100),
            responses: [MomentResponse(
                id: UUID(),
                responderUserID: userID,
                content: .emoji(.heart),
                createdAt: Date(timeIntervalSince1970: 101)
            )],
            questionAnswers: [MomentQuestionAnswer(
                id: UUID(),
                answererUserID: partnerUserID,
                content: "今天有點累",
                createdAt: Date(timeIntervalSince1970: 102)
            )]
        )
        let status = CurrentRelationshipStatus(
            userID: partnerUserID,
            content: .custom("晚點想聊聊"),
            expiration: .manual,
            expiresAt: nil,
            updatedAt: Date(timeIntervalSince1970: 103)
        )
        let togetherNow = TogetherNowSnapshot(
            currentUserID: userID,
            partnerUserID: partnerUserID,
            currentDisplayName: "小日",
            partnerDisplayName: "小月",
            privatePartnerName: "月亮",
            currentStatus: nil,
            partnerStatus: status
        )
        let photoData = Data([0x01, 0x02, 0x03])

        try store.saveMoments([moment], userID: userID, relationshipID: relationshipID)
        try store.saveTogetherNow(togetherNow, userID: userID, relationshipID: relationshipID)
        try store.savePhoto(
            photoData,
            userID: userID,
            relationshipID: relationshipID,
            momentID: momentID
        )

        #expect(try store.loadMoments(userID: userID, relationshipID: relationshipID) == [moment])
        #expect(try store.loadTogetherNow(userID: userID, relationshipID: relationshipID) == togetherNow)
        #expect(try store.loadPhoto(
            userID: userID,
            relationshipID: relationshipID,
            momentID: momentID
        ) == photoData)
        #expect(try store.loadMoments(userID: UUID(), relationshipID: relationshipID) == nil)
        #expect(try store.loadTogetherNow(userID: userID, relationshipID: UUID()) == nil)

        store.clearAll(userID: userID)
        #expect(try store.loadMoments(userID: userID, relationshipID: relationshipID) == nil)
        #expect(try store.loadTogetherNow(userID: userID, relationshipID: relationshipID) == nil)
        #expect(try store.loadPhoto(
            userID: userID,
            relationshipID: relationshipID,
            momentID: momentID
        ) == nil)
    }

    @Test func conversationRecoveryRetryUsesTheAcceptedBoundedBackoff() {
        #expect(ConversationRecoveryRetryPolicy.maximumAttempts == 3)
        #expect(ConversationRecoveryRetryPolicy.delayNanoseconds(afterAttempt: 1) == 1_000_000_000)
        #expect(ConversationRecoveryRetryPolicy.delayNanoseconds(afterAttempt: 2) == 4_000_000_000)
        #expect(ConversationRecoveryRetryPolicy.delayNanoseconds(afterAttempt: 3) == nil)
    }

    @MainActor
    @Test func conversationModelTracksUnreadVisibilityAndStableSendRetries() async throws {
        let currentUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
        let partnerUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!
        let partnerMessage = ChatMessage(
            id: UUID(uuidString: "C1000000-0000-0000-0000-000000000001")!,
            senderUserID: partnerUserID,
            body: "今天還好嗎？",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let service = ConversationRemoteServiceFake(
            currentUserID: currentUserID,
            messages: [partnerMessage],
            unreadCount: 1
        )
        let model = ConversationModel(service: service)

        await model.start()
        #expect(model.messages == [partnerMessage])
        #expect(model.unreadCount == 1)
        #expect(service.isObserving)

        await model.setConversationVisible(true)
        #expect(model.unreadCount == 0)
        #expect(service.markedReadMessageIDs == [partnerMessage.id])

        service.sendDelay = .milliseconds(300)
        let slowSend = Task { await model.send("立即顯示") }
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.messages.last?.body == "立即顯示")
        #expect(model.messages.last?.deliveryState == .sending)
        #expect(await slowSend.value)
        await model.waitForScheduledDelivery()
        #expect(model.messages.last?.deliveryState == .synced)

        service.sendDelay = .zero
        service.sendFailuresRemaining = 1
        #expect(await model.send("  我很好  "))
        await model.waitForScheduledDelivery()
        #expect(model.messages.last?.body == "我很好")
        #expect(model.messages.last?.deliveryState == .failed)
        let failedMessageID = try #require(model.messages.last?.id)
        await model.retryMessage(id: failedMessageID)
        #expect(service.sentBodies == ["立即顯示", "我很好", "我很好"])
        #expect(service.sentClientIDs[1] == service.sentClientIDs[2])
        #expect(model.messages.last?.body == "我很好")
        #expect(model.messages.last?.deliveryState == .synced)

        let realtimeMessage = ChatMessage(
            id: UUID(uuidString: "C1000000-0000-0000-0000-000000000003")!,
            senderUserID: partnerUserID,
            body: "那就好",
            createdAt: Date(timeIntervalSince1970: 300)
        )
        service.messages.append(realtimeMessage)
        service.unreadCount = 1
        await service.sendChange()
        #expect(model.messages.last == realtimeMessage)
        #expect(model.unreadCount == 0)
        #expect(service.markedReadMessageIDs.last == realtimeMessage.id)

        await model.stop()
        #expect(!service.isObserving)
    }

    @MainActor
    @Test func conversationModelDrainsMessagesInFIFOWhileTheFirstSendIsInFlight() async throws {
        let currentUserID = UUID()
        let service = ConversationRemoteServiceFake(
            currentUserID: currentUserID,
            messages: [],
            unreadCount: 0
        )
        let model = ConversationModel(service: service)
        await model.start()

        service.sendDelay = .milliseconds(200)
        let first = Task { await model.send("第一則") }
        try await Task.sleep(for: .milliseconds(30))
        let second = Task { await model.send("第二則") }

        #expect(await second.value)
        #expect(await first.value)
        await model.waitForScheduledDelivery()
        #expect(service.sentBodies == ["第一則", "第二則"])
        #expect(model.messages.map(\.body) == ["第一則", "第二則"])
        #expect(model.messages.allSatisfy { $0.deliveryState == .synced })
    }

    @MainActor
    @Test func conversationModelMarksEveryMessageBlockedByAFailedFIFOHeadAsRetryable() async {
        let service = ConversationRemoteServiceFake(
            currentUserID: UUID(),
            messages: [],
            unreadCount: 0
        )
        let model = ConversationModel(service: service)
        await model.start()
        service.sendFailuresRemaining = 10

        #expect(await model.send("第一則"))
        #expect(await model.send("第二則"))
        #expect(await model.send("第三則"))
        await model.waitForScheduledDelivery()
        #expect(model.messages.map(\.body) == ["第一則", "第二則", "第三則"])
        #expect(model.messages.allSatisfy { $0.deliveryState == .failed })
    }

    @MainActor
    @Test func conversationModelCoalescesRealtimeRefreshAndReconnectsDuringRecovery() async throws {
        let currentUserID = UUID()
        let partnerUserID = UUID()
        let service = ConversationRemoteServiceFake(
            currentUserID: currentUserID,
            messages: [],
            unreadCount: 0
        )
        let model = ConversationModel(service: service)
        await model.start()
        #expect(service.startObservingCallCount == 1)

        service.fetchDelay = .milliseconds(120)
        let firstRefresh = Task { await model.refresh() }
        try await Task.sleep(for: .milliseconds(20))
        service.messages.append(ChatMessage(
            id: UUID(),
            senderUserID: partnerUserID,
            body: "恢復後立即看見",
            createdAt: .now
        ))
        await service.sendChange()
        await firstRefresh.value
        #expect(model.messages.map(\.body) == ["恢復後立即看見"])

        service.fetchDelay = .zero
        await model.recoverPendingMessages()
        #expect(service.startObservingCallCount == 2)
    }

    @MainActor
    @Test func conversationModelRetriesLostAcknowledgementWithoutDuplicatingRemoteMessage() async throws {
        let service = ConversationRemoteServiceFake(
            currentUserID: UUID(),
            messages: [],
            unreadCount: 0
        )
        let model = ConversationModel(service: service)
        await model.start()
        service.acknowledgementFailuresRemaining = 1

        #expect(await model.send("只保留一則"))
        await model.waitForScheduledDelivery()
        let failedID = try #require(model.messages.last?.id)
        #expect(model.messages.last?.deliveryState == .failed)
        #expect(service.messages.count == 1)

        await model.retryMessage(id: failedID)
        #expect(service.sentClientIDs == [failedID, failedID])
        #expect(service.messages.count == 1)
        #expect(model.messages.last?.deliveryState == .synced)
    }


    @MainActor
    @Test func conversationModelShowsCachedHistoryWhenRemoteRefreshFails() async {
        let currentUserID = UUID()
        let cachedMessage = ChatMessage(
            id: UUID(),
            senderUserID: currentUserID,
            body: "離線仍看得到",
            createdAt: .now
        )
        let service = ConversationRemoteServiceFake(
            currentUserID: currentUserID,
            messages: [cachedMessage],
            unreadCount: 0
        )
        service.fetchFailuresRemaining = 1
        let model = ConversationModel(service: service)

        await model.start()

        #expect(model.messages == [cachedMessage])
        #expect(model.currentUserID == currentUserID)
    }

    @Test func momentDraftNormalizesShortTextAndRejectsInvalidContent() {
        #expect(MomentDraftPolicy.normalizedText("  想到你  ") == "想到你")
        #expect(MomentDraftPolicy.normalizedText(" \n\t ") == nil)
        #expect(MomentDraftPolicy.normalizedText(
            String(repeating: "a", count: MomentDraftPolicy.maximumTextLength + 1)
        ) == nil)
        #expect(MomentMood.allCases.map(\.rawValue) == [
            "calm", "happy", "tired", "thinking_of_you", "need_hug",
        ])
    }

    @Test func momentInteractionPoliciesKeepResponsesShortAndQuestionsFixed() {
        #expect(MomentResponsePolicy.normalizedText("  抱抱你  ") == "抱抱你")
        #expect(MomentResponsePolicy.normalizedText("   \n") == nil)
        #expect(MomentResponsePolicy.normalizedText(
            String(repeating: "a", count: MomentResponsePolicy.maximumTextLength + 1)
        ) == nil)
        #expect(MomentResponsePolicy.normalizedEmoji("  🥳  ") == "🥳")
        #expect(MomentResponsePolicy.normalizedEmoji("👩🏽‍💻") == "👩🏽‍💻")
        #expect(MomentResponsePolicy.normalizedEmoji("🥳🥰") == nil)
        #expect(MomentResponsePolicy.normalizedEmoji("A") == nil)
        #expect(MomentQuestionPolicy.normalizedAnswer("  下班一起吃飯  ") == "下班一起吃飯")
        #expect(MomentQuestionPrompt.accepted.map(\.id) == [
            "understand_today",
            "recent_small_happiness",
            "together_this_week",
            "unsaid_recently",
        ])

        let first = UUID()
        let second = UUID()
        let question = Moment(
            id: UUID(),
            creatorUserID: first,
            content: .question(MomentQuestion(key: "understand_today", prompt: "題目")),
            createdAt: .now,
            questionAnswers: [
                MomentQuestionAnswer(id: UUID(), answererUserID: first, content: "A", createdAt: .now),
                MomentQuestionAnswer(id: UUID(), answererUserID: second, content: "B", createdAt: .now),
            ]
        )
        #expect(question.isComplete)
    }

    @MainActor
    @Test func momentModelLoadsCreatesAndRefreshesFromRemoteChanges() async throws {
        let first = Moment(
            id: UUID(uuidString: "B1000000-0000-0000-0000-000000000001")!,
            creatorUserID: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
            content: .mood(.calm),
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let service = MomentRemoteServiceFake(moments: [first])
        let model = MomentModel(service: service)

        #expect(model.authorLabel(for: first, names: nil) == "留下者未確認")
        await model.start()
        #expect(model.moments == [first])
        #expect(model.authorLabel(for: first, names: nil) == "我留下的")
        #expect(service.isObserving)

        #expect(await model.create(.text("  今天看到漂亮的天空  ")))
        #expect(model.moments.first?.content == .text("今天看到漂亮的天空"))
        #expect(service.createdDrafts == [.text("  今天看到漂亮的天空  ")])

        let partnerMoment = Moment(
            id: UUID(uuidString: "B1000000-0000-0000-0000-000000000003")!,
            creatorUserID: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
            content: .mood(.happy),
            createdAt: Date(timeIntervalSince1970: 300)
        )
        service.moments.insert(partnerMoment, at: 0)
        await service.sendChange()
        #expect(model.moments.first == partnerMoment)
        #expect(model.authorLabel(for: partnerMoment, names: nil) == "伴侶留下的")

        let names = TogetherNowSnapshot(
            currentUserID: first.creatorUserID,
            partnerUserID: partnerMoment.creatorUserID,
            currentDisplayName: "小日",
            partnerDisplayName: "小月",
            privatePartnerName: "月亮",
            currentStatus: nil,
            partnerStatus: nil
        )
        #expect(model.authorLabel(for: first, names: names) == "小日留下的")
        #expect(model.authorLabel(for: partnerMoment, names: names) == "月亮留下的")

        await model.stop()
        #expect(!service.isObserving)
    }

    @MainActor
    @Test func momentModelDisplaysCachedContentBeforeDelayedOfflineRefreshFinishes() async throws {
        let cachedMoment = Moment(
            id: UUID(),
            creatorUserID: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
            content: .photo,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let cachedPhoto = Data([0x01, 0x02])
        let service = MomentRemoteServiceFake(moments: [])
        service.cachedMomentsValue = [cachedMoment]
        service.cachedPhotoDataByMomentID[cachedMoment.id] = cachedPhoto
        service.fetchDelay = .milliseconds(200)
        service.fetchFailuresRemaining = 1
        let model = MomentModel(service: service)

        let start = Task { await model.start() }
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.moments == [cachedMoment])
        #expect(model.photoDataByMomentID[cachedMoment.id] == cachedPhoto)
        await start.value
        #expect(model.moments == [cachedMoment])
        #expect(model.statusMessage != nil)
    }

    @MainActor
    @Test func momentModelCompletesPartnerResponseAndJointQuestionReveal() async throws {
        let currentUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let partnerUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        let partnerMoment = Moment(
            id: UUID(uuidString: "B1000000-0000-0000-0000-000000000011")!,
            creatorUserID: partnerUserID,
            content: .text("今天也辛苦了"),
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let questionMoment = Moment(
            id: UUID(uuidString: "B1000000-0000-0000-0000-000000000012")!,
            creatorUserID: partnerUserID,
            content: .question(MomentQuestion(
                key: "recent_small_happiness",
                prompt: "最近有哪件小事讓你感到幸福？"
            )),
            createdAt: Date(timeIntervalSince1970: 200),
            questionAnswers: [MomentQuestionAnswer(
                id: UUID(),
                answererUserID: partnerUserID,
                content: "伴侶的隱藏回答",
                createdAt: Date(timeIntervalSince1970: 200)
            )]
        )
        let service = MomentRemoteServiceFake(moments: [questionMoment, partnerMoment])
        let model = MomentModel(service: service)
        await model.start()

        #expect(!model.currentUserHasAnswered(questionMoment))
        service.responseDelay = .milliseconds(300)
        let slowResponse = Task { await model.respond(to: partnerMoment, with: .emoji(.hug)) }
        try await Task.sleep(for: .milliseconds(50))
        let optimisticMoment = try #require(model.moments.first { $0.id == partnerMoment.id })
        #expect(model.response(for: optimisticMoment)?.content == .emoji(.hug))
        #expect(await slowResponse.value)
        service.responseDelay = .zero
        let refreshedPartnerMoment = try #require(model.moments.first { $0.id == partnerMoment.id })
        #expect(refreshedPartnerMoment.isComplete)
        #expect(model.response(for: refreshedPartnerMoment)?.content == .emoji(.hug))

        #expect(await model.answer(questionMoment, text: "有人陪我吃飯"))
        let revealedQuestion = try #require(model.moments.first { $0.id == questionMoment.id })
        #expect(revealedQuestion.isComplete)
        #expect(revealedQuestion.questionAnswers.count == 2)
        #expect(model.currentUserHasAnswered(revealedQuestion))

        let draft = MomentQuestionDraft(
            questionKey: "understand_today",
            answer: "希望你知道我有點累"
        )
        #expect(await model.createQuestion(draft))
        #expect(model.moments.first?.creatorUserID == currentUserID)
        #expect(model.currentUserHasAnswered(try #require(model.moments.first)))
    }

    @MainActor
    @Test func momentInteractionRetriesReuseStableClientIdentities() async throws {
        let partnerUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        let partnerMoment = Moment(
            id: UUID(),
            creatorUserID: partnerUserID,
            content: .text("今天也辛苦了"),
            createdAt: .now
        )
        let partnerQuestion = Moment(
            id: UUID(),
            creatorUserID: partnerUserID,
            content: .question(MomentQuestion(key: "understand_today", prompt: "題目")),
            createdAt: .now,
            questionAnswers: [MomentQuestionAnswer(
                id: UUID(),
                answererUserID: partnerUserID,
                content: "隱藏回答",
                createdAt: .now
            )]
        )
        let service = MomentRemoteServiceFake(moments: [partnerQuestion, partnerMoment])
        let model = MomentModel(service: service)
        await model.start()

        service.responseFailuresRemaining = 1
        #expect(await model.respond(to: partnerMoment, with: .emoji(.heart)) == false)
        #expect(await model.respond(to: partnerMoment, with: .emoji(.heart)))
        #expect(service.responseClientIDs.count == 2)
        #expect(service.responseClientIDs[0] == service.responseClientIDs[1])

        service.answerFailuresRemaining = 1
        #expect(await model.answer(partnerQuestion, text: "希望你理解我") == false)
        #expect(await model.answer(partnerQuestion, text: "希望你理解我"))
        #expect(service.answerClientIDs.count == 2)
        #expect(service.answerClientIDs[0] == service.answerClientIDs[1])

        let draft = MomentQuestionDraft(questionKey: "understand_today", answer: "有點累")
        service.questionFailuresRemaining = 1
        #expect(await model.createQuestion(draft) == false)
        #expect(await model.createQuestion(draft))
        #expect(service.questionAttemptIDs.count == 2)
        #expect(service.questionAttemptIDs[0].0 == service.questionAttemptIDs[1].0)
        #expect(service.questionAttemptIDs[0].1 == service.questionAttemptIDs[1].1)
    }

    @Test func togetherNowPoliciesKeepNamesPrivateAndExpirationAbsolute() throws {
        #expect(TogetherNowTextPolicy.normalizedOptionalName("  小日  ") == "小日")
        #expect(TogetherNowTextPolicy.isValidOptionalNameInput("   "))
        #expect(TogetherNowTextPolicy.normalizedOptionalName(
            String(repeating: "a", count: TogetherNowTextPolicy.maximumNameLength + 1)
        ) == nil)
        #expect(TogetherNowTextPolicy.normalizedCustomStatus("  今天需要一點空間  ") == "今天需要一點空間")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Taipei"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-08-12T14:30:00Z"))
        let tonight = try #require(CurrentStatusExpiration.tonight.tonightExpiresAt(
            from: now,
            calendar: calendar
        ))
        #expect(ISO8601DateFormatter().string(from: tonight) == "2026-08-12T16:00:00Z")

        let currentUserID = UUID()
        let partnerUserID = UUID()
        let snapshot = TogetherNowSnapshot(
            currentUserID: currentUserID,
            partnerUserID: partnerUserID,
            currentDisplayName: "小日",
            partnerDisplayName: "小月",
            privatePartnerName: "月亮",
            currentStatus: nil,
            partnerStatus: nil
        )
        #expect(snapshot.currentUserLabel == "小日")
        #expect(snapshot.partnerLabel == "月亮")
        #expect(snapshot.participantPossessiveLabel(for: currentUserID) == "小日的")
        #expect(snapshot.participantPossessiveLabel(for: partnerUserID) == "月亮的")

        let unnamed = TogetherNowSnapshot(
            currentUserID: currentUserID,
            partnerUserID: partnerUserID,
            currentDisplayName: nil,
            partnerDisplayName: nil,
            privatePartnerName: nil,
            currentStatus: nil,
            partnerStatus: nil
        )
        #expect(unnamed.currentUserLabel == "我")
        #expect(unnamed.partnerLabel == "伴侶")
        #expect(unnamed.participantPossessiveLabel(for: currentUserID) == "我的")
        #expect(unnamed.participantPossessiveLabel(for: partnerUserID) == "伴侶的")
    }

    @MainActor
    @Test func togetherNowModelLoadsNamesAndFiltersExpiredStatus() async {
        let currentUserID = UUID()
        let partnerUserID = UUID()
        let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)
        let expiredPartnerStatus = CurrentRelationshipStatus(
            userID: partnerUserID,
            content: .fixed(.tired),
            expiration: .oneHour,
            expiresAt: referenceDate.addingTimeInterval(-1),
            updatedAt: referenceDate.addingTimeInterval(-3_600)
        )
        let service = TogetherNowRemoteServiceFake(snapshot: TogetherNowSnapshot(
            currentUserID: currentUserID,
            partnerUserID: partnerUserID,
            currentDisplayName: nil,
            partnerDisplayName: "小月",
            privatePartnerName: "月亮",
            currentStatus: nil,
            partnerStatus: expiredPartnerStatus
        ))
        let model = TogetherNowModel(service: service, now: { referenceDate })

        await model.start()
        #expect(model.snapshot?.currentUserLabel == "我")
        #expect(model.snapshot?.partnerLabel == "月亮")
        #expect(model.snapshot?.partnerStatus == nil)
        #expect(service.isObserving)

        #expect(await model.saveNames(displayName: "  小日  ", privatePartnerName: "  小月亮  "))
        #expect(service.savedNames.first?.0 == "小日")
        #expect(service.savedNames.first?.1 == "小月亮")

        await model.stop()
        #expect(!service.isObserving)
    }

    @MainActor
    @Test func togetherNowModelDisplaysCachedStatusBeforeDelayedOfflineRefreshFinishes() async throws {
        let cached = TogetherNowSnapshot.preview
        let service = TogetherNowRemoteServiceFake(snapshot: cached)
        service.cachedSnapshotValue = cached
        service.fetchDelay = .milliseconds(200)
        service.fetchFailuresRemaining = 1
        let model = TogetherNowModel(service: service)

        let start = Task { await model.start() }
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.snapshot == cached)
        await start.value
        #expect(model.snapshot == cached)
        #expect(model.statusMessage != nil)
    }

    @MainActor
    @Test func togetherNowMomentRetryKeepsOneStableIdentity() async {
        let service = TogetherNowRemoteServiceFake(snapshot: .preview)
        let model = TogetherNowModel(service: service)
        await model.start()
        let draft = CurrentStatusDraft(
            content: .fixed(.thinkingOfYou),
            expiration: .fourHours,
            savesAsMoment: true
        )

        service.statusFailuresRemaining = 1
        #expect(await model.saveStatus(draft) == false)
        #expect(await model.saveStatus(draft))
        #expect(service.statusMomentIDs.count == 2)
        #expect(service.statusMomentIDs[0] == service.statusMomentIDs[1])
        #expect(service.statusMomentIDs[0] != nil)
        #expect(model.snapshot?.currentStatus?.content == .fixed(.thinkingOfYou))

        #expect(await model.clearStatus())
        #expect(model.snapshot?.currentStatus == nil)
    }

    @MainActor
    @Test func togetherNowAutomaticallyRemovesStatusAtExpiration() async throws {
        let currentUserID = UUID()
        let partnerUserID = UUID()
        let referenceDate = Date()
        var currentDate = referenceDate
        let status = CurrentRelationshipStatus(
            userID: currentUserID,
            content: .fixed(.busy),
            expiration: .oneHour,
            expiresAt: referenceDate.addingTimeInterval(0.05),
            updatedAt: referenceDate
        )
        let service = TogetherNowRemoteServiceFake(snapshot: TogetherNowSnapshot(
            currentUserID: currentUserID,
            partnerUserID: partnerUserID,
            currentDisplayName: nil,
            partnerDisplayName: nil,
            privatePartnerName: nil,
            currentStatus: status,
            partnerStatus: nil
        ))
        let model = TogetherNowModel(service: service, now: { currentDate })

        await model.start()
        #expect(model.snapshot?.currentStatus != nil)
        currentDate = referenceDate.addingTimeInterval(1)
        try await Task.sleep(for: .milliseconds(250))
        #expect(model.snapshot?.currentStatus == nil)
        await model.stop()
    }

    @MainActor
    @Test func togetherNowRestoresRemoteNamesAndActiveStatusAfterModelRecreation() async {
        let service = TogetherNowRemoteServiceFake(snapshot: .preview)
        let firstModel = TogetherNowModel(service: service)
        await firstModel.start()

        #expect(await firstModel.saveNames(
            displayName: "小日",
            privatePartnerName: "小月亮"
        ))
        #expect(await firstModel.saveStatus(CurrentStatusDraft(
            content: .fixed(.thinkingOfYou),
            expiration: .manual,
            savesAsMoment: false
        )))
        await firstModel.stop()

        let restoredModel = TogetherNowModel(service: service)
        await restoredModel.start()
        #expect(restoredModel.snapshot?.currentDisplayName == "小日")
        #expect(restoredModel.snapshot?.privatePartnerName == "小月亮")
        #expect(restoredModel.snapshot?.currentStatus?.content == .fixed(.thinkingOfYou))
        await restoredModel.stop()
    }

    @Test func authenticationStateDistinguishesRestoreCancelFailureAndSignOut() {
        if case .checking = AuthenticationState.checking.phase {} else {
            Issue.record("The initial authentication state should restore the session first.")
        }

        let cancelled = AuthenticationState.signedOut(message: "已取消登入")
        if case .signedOut = cancelled.phase {} else {
            Issue.record("Cancellation should return to the signed-out state.")
        }
        #expect(cancelled.isSignedIn == false)
        #expect(cancelled.message == "已取消登入")

        let userID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let signedIn = AuthenticationState.signedIn(userID: userID)
        if case .signedIn = signedIn.phase {} else {
            Issue.record("A valid session should enter the signed-in state.")
        }
        #expect(signedIn.isSignedIn)
        #expect(signedIn.userID == userID)
        #expect(signedIn.userToken == "aaaaaaaa")

        let signingOut = signedIn.signingOut()
        if case .signingOut = signingOut.phase {} else {
            Issue.record("Sign-out should have an explicit in-progress state.")
        }
        #expect(signingOut.isSignedIn)

        let restored = signedIn.restoringAfterSignOutFailure()
        if case .signedIn = restored.phase {} else {
            Issue.record("A failed sign-out must preserve the valid signed-in session.")
        }
        #expect(restored.isSignedIn)
        #expect(restored.message == "登出失敗，請稍後再試。")
    }

    @Test func appleSignInStartsOnlyWhenNetworkIsAvailableAndNoRequestIsPending() {
        #expect(AuthenticationStartPolicy.canStartSignIn(
            phase: .signedOut,
            networkState: .available
        ))
        #expect(AuthenticationStartPolicy.canStartSignIn(
            phase: .signedOut,
            networkState: .unknown
        ) == false)
        #expect(AuthenticationStartPolicy.canStartSignIn(
            phase: .signedOut,
            networkState: .unavailable
        ) == false)
        #expect(AuthenticationStartPolicy.canStartSignIn(
            phase: .signingIn,
            networkState: .available
        ) == false)
    }

    @Test func pairingInputAcceptsOnlyACompleteUUIDAndMapsExpectedServerOutcomes() {
        let token = "11111111-2222-4333-8444-555555555555"
        #expect(PairingInputPolicy.invitationToken(from: "  \(token)\n")?.uuidString.lowercased() == token)
        #expect(PairingInputPolicy.invitationToken(from: "11111111") == nil)
        #expect(PairingErrorMessage.message(serverMessage: "invitation_not_available").contains("已失效"))
        #expect(PairingErrorMessage.message(serverMessage: "participant_already_paired").contains("已有"))
    }

    @MainActor
    @Test func pairingModelCreatesAcceptsAndDeclinesWithoutInventingClientRelationships() async {
        let relationshipID = UUID(uuidString: "90000000-0000-4000-8000-000000000004")!
        let invitationToken = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let invitation = PairingInvitation(
            relationshipID: relationshipID,
            token: invitationToken,
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
        let service = PairingRemoteServiceFake(
            currentRelationship: nil,
            invitation: invitation,
            acceptedRelationshipID: relationshipID
        )
        let model = PairingModel(service: service)

        await model.refresh()
        #expect(model.state == .unpaired)

        await model.createOrRetryInvitation()
        #expect(model.state == .waiting(
            PairingRelationship(id: relationshipID, memberCount: 1),
            invitation: invitation
        ))

        await model.createOrRetryInvitation()
        #expect(model.statusMessage == "目前的邀請仍然有效。")

        await model.cancelInvitation()
        #expect(model.state == .unpaired)
        #expect(service.cancelInvitationCallCount == 1)

        await model.createOrRetryInvitation()

        await model.acceptInvitation(rawToken: invitation.code)
        #expect(model.state == .paired(PairingRelationship(id: relationshipID, memberCount: 2)))
        #expect(service.acceptedTokens == [invitationToken])

        model.resetForAuthenticatedSession()
        #expect(model.state == .checking)

        await model.declineInvitation(rawToken: invitation.code)
        #expect(model.state == .unpaired)
        #expect(service.declinedTokens == [invitationToken])
    }

    @MainActor
    @Test func pairingModelIgnoresAResponseFromThePreviousAuthenticatedSession() async {
        let service = SuspendedPairingRemoteServiceFake()
        let model = PairingModel(service: service)
        let oldSessionRefresh = Task { await model.refresh() }

        while service.currentRelationshipContinuation == nil {
            await Task.yield()
        }

        model.resetForAuthenticatedSession()
        service.resumeCurrentRelationship(
            PairingRelationship(id: UUID(), memberCount: 2)
        )
        await oldSessionRefresh.value

        #expect(model.state == .checking)
        #expect(model.isWorking == false)
    }

    @MainActor
    @Test func pairingModelRestoresCachedRelationshipBeforeRemoteRefreshCompletes() async {
        let relationship = PairingRelationship(id: UUID(), memberCount: 2)
        let service = SuspendedPairingRemoteServiceFake(cachedRelationship: relationship)
        let model = PairingModel(service: service)

        await model.restoreCachedRelationship(userID: UUID())

        #expect(model.state == .paired(relationship))
    }
}

@MainActor
private final class ConversationRemoteServiceFake: ConversationRemoteServing {
    let currentUserID: UUID
    var messages: [ChatMessage]
    var unreadCount: Int
    var sentBodies: [String] = []
    var sentClientIDs: [UUID] = []
    var markedReadMessageIDs: [UUID] = []
    var sendFailuresRemaining = 0
    var fetchFailuresRemaining = 0
    var acknowledgementFailuresRemaining = 0
    var sendDelay: Duration = .zero
    var fetchDelay: Duration = .zero
    var nextAcceptedAt = Date(timeIntervalSince1970: 200)
    var isObserving = false
    var startObservingCallCount = 0
    private var pendingMessages: [ChatMessage] = []
    private var onChange: (@MainActor () async -> Void)?

    init(currentUserID: UUID, messages: [ChatMessage], unreadCount: Int) {
        self.currentUserID = currentUserID
        self.messages = messages
        self.unreadCount = unreadCount
    }

    func fetchPendingSnapshot() async throws -> ConversationPendingSnapshot {
        ConversationPendingSnapshot(currentUserID: currentUserID, messages: pendingMessages)
    }

    func fetchCachedSnapshot() async throws -> ConversationSnapshot? {
        ConversationSnapshot(
            currentUserID: currentUserID,
            messages: messages,
            unreadCount: unreadCount
        )
    }

    func persistCachedSnapshot(_ snapshot: ConversationSnapshot) async {}

    func enqueueMessage(body: String, clientID: UUID, localCreatedAt: Date) async throws {
        pendingMessages.append(ChatMessage(
            id: clientID,
            senderUserID: currentUserID,
            body: body,
            createdAt: localCreatedAt,
            deliveryState: .sending
        ))
    }

    func beginNextPendingMessage() async throws -> ChatMessage? {
        pendingMessages.first.map {
            ChatMessage(
                id: $0.id,
                senderUserID: $0.senderUserID,
                body: $0.body,
                createdAt: $0.createdAt,
                deliveryState: .sending
            )
        }
    }

    func acknowledgePendingMessage(clientID: UUID) async throws {
        if acknowledgementFailuresRemaining > 0 {
            acknowledgementFailuresRemaining -= 1
            throw TestServiceError.expected
        }
        guard pendingMessages.first?.id == clientID else {
            throw ConversationOutboxError.unexpectedAcknowledgement
        }
        pendingMessages.removeFirst()
    }

    func fetchSnapshot() async throws -> ConversationSnapshot {
        if fetchFailuresRemaining > 0 {
            fetchFailuresRemaining -= 1
            throw TestServiceError.expected
        }
        let snapshot = ConversationSnapshot(
            currentUserID: currentUserID,
            messages: messages,
            unreadCount: unreadCount
        )
        try await Task.sleep(for: fetchDelay)
        return snapshot
    }

    func sendMessage(body: String, clientID: UUID) async throws -> Date {
        sentBodies.append(body)
        sentClientIDs.append(clientID)
        try await Task.sleep(for: sendDelay)
        if sendFailuresRemaining > 0 {
            sendFailuresRemaining -= 1
            throw TestServiceError.expected
        }
        if let existing = messages.first(where: { $0.id == clientID }) {
            return existing.createdAt
        }
        let acceptedAt = nextAcceptedAt
        nextAcceptedAt = nextAcceptedAt.addingTimeInterval(1)
        messages.append(ChatMessage(
            id: clientID,
            senderUserID: currentUserID,
            body: body,
            createdAt: acceptedAt
        ))
        return acceptedAt
    }

    func markRead(through messageID: UUID) async throws {
        markedReadMessageIDs.append(messageID)
        unreadCount = 0
    }

    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws {
        startObservingCallCount += 1
        isObserving = true
        self.onChange = onChange
    }

    func stopObservingChanges() async {
        isObserving = false
        onChange = nil
    }

    func sendChange() async {
        await onChange?()
    }
}

private final class PairingRemoteServiceFake: PairingRemoteServing {
    var currentRelationshipValue: PairingRelationship?
    let invitation: PairingInvitation
    let acceptedRelationshipID: UUID
    var acceptedTokens: [UUID] = []
    var declinedTokens: [UUID] = []
    var cancelInvitationCallCount = 0

    init(
        currentRelationship: PairingRelationship?,
        invitation: PairingInvitation,
        acceptedRelationshipID: UUID
    ) {
        currentRelationshipValue = currentRelationship
        self.invitation = invitation
        self.acceptedRelationshipID = acceptedRelationshipID
    }

    func currentRelationship() async throws -> PairingRelationship? {
        currentRelationshipValue
    }

    func createInvitation() async throws -> PairingInvitation {
        invitation
    }

    func acceptInvitation(token: UUID) async throws -> UUID {
        acceptedTokens.append(token)
        return acceptedRelationshipID
    }

    func declineInvitation(token: UUID) async throws {
        declinedTokens.append(token)
    }

    func cancelInvitation() async throws {
        cancelInvitationCallCount += 1
    }
}

private final class SuspendedPairingRemoteServiceFake: PairingRemoteServing {
    let cachedRelationshipValue: PairingRelationship?
    var currentRelationshipContinuation: CheckedContinuation<PairingRelationship?, Never>?

    init(cachedRelationship: PairingRelationship? = nil) {
        cachedRelationshipValue = cachedRelationship
    }

    func cachedRelationship(userID: UUID) async -> PairingRelationship? {
        cachedRelationshipValue
    }

    func currentRelationship() async throws -> PairingRelationship? {
        await withCheckedContinuation { continuation in
            currentRelationshipContinuation = continuation
        }
    }

    func resumeCurrentRelationship(_ relationship: PairingRelationship?) {
        currentRelationshipContinuation?.resume(returning: relationship)
        currentRelationshipContinuation = nil
    }

    func createInvitation() async throws -> PairingInvitation {
        PairingInvitation(relationshipID: UUID(), token: UUID(), expiresAt: .now)
    }

    func acceptInvitation(token: UUID) async throws -> UUID {
        UUID()
    }

    func declineInvitation(token: UUID) async throws {}

    func cancelInvitation() async throws {}
}

@MainActor
private final class TogetherNowRemoteServiceFake: TogetherNowRemoteServing {
    var snapshot: TogetherNowSnapshot
    var cachedSnapshotValue: TogetherNowSnapshot?
    var fetchDelay: Duration = .zero
    var fetchFailuresRemaining = 0
    var savedNames: [(String?, String?)] = []
    var statusMomentIDs: [UUID?] = []
    var statusFailuresRemaining = 0
    var isObserving = false
    private var onChange: (@MainActor () async -> Void)?

    init(snapshot: TogetherNowSnapshot) {
        self.snapshot = snapshot
    }

    func cachedSnapshot() -> TogetherNowSnapshot? { cachedSnapshotValue }

    func fetchSnapshot() async throws -> TogetherNowSnapshot {
        try await Task.sleep(for: fetchDelay)
        if fetchFailuresRemaining > 0 {
            fetchFailuresRemaining -= 1
            throw TestServiceError.expected
        }
        return snapshot
    }

    func updateNames(displayName: String?, privatePartnerName: String?) async throws {
        savedNames.append((displayName, privatePartnerName))
        snapshot = TogetherNowSnapshot(
            currentUserID: snapshot.currentUserID,
            partnerUserID: snapshot.partnerUserID,
            currentDisplayName: displayName,
            partnerDisplayName: snapshot.partnerDisplayName,
            privatePartnerName: privatePartnerName,
            currentStatus: snapshot.currentStatus,
            partnerStatus: snapshot.partnerStatus
        )
    }

    func setStatus(
        _ draft: CurrentStatusDraft,
        tonightExpiresAt: Date?,
        momentClientID: UUID?
    ) async throws -> CurrentRelationshipStatus {
        statusMomentIDs.append(momentClientID)
        if statusFailuresRemaining > 0 {
            statusFailuresRemaining -= 1
            throw TestServiceError.expected
        }
        let status = CurrentRelationshipStatus(
            userID: snapshot.currentUserID,
            content: draft.content,
            expiration: draft.expiration,
            expiresAt: draft.expiration == .manual ? nil : Date().addingTimeInterval(3_600),
            updatedAt: .now
        )
        snapshot = TogetherNowSnapshot(
            currentUserID: snapshot.currentUserID,
            partnerUserID: snapshot.partnerUserID,
            currentDisplayName: snapshot.currentDisplayName,
            partnerDisplayName: snapshot.partnerDisplayName,
            privatePartnerName: snapshot.privatePartnerName,
            currentStatus: status,
            partnerStatus: snapshot.partnerStatus
        )
        return status
    }

    func clearStatus() async throws {
        snapshot = TogetherNowSnapshot(
            currentUserID: snapshot.currentUserID,
            partnerUserID: snapshot.partnerUserID,
            currentDisplayName: snapshot.currentDisplayName,
            partnerDisplayName: snapshot.partnerDisplayName,
            privatePartnerName: snapshot.privatePartnerName,
            currentStatus: nil,
            partnerStatus: snapshot.partnerStatus
        )
    }

    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws {
        isObserving = true
        self.onChange = onChange
    }

    func stopObservingChanges() async {
        isObserving = false
        onChange = nil
    }
}

private enum TestServiceError: Error {
    case expected
}

@MainActor
private final class MomentRemoteServiceFake: MomentRemoteServing {
    private let userID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
    var moments: [Moment]
    var cachedMomentsValue: [Moment]?
    var cachedPhotoDataByMomentID: [UUID: Data] = [:]
    var fetchDelay: Duration = .zero
    var fetchFailuresRemaining = 0
    var createdDrafts: [MomentDraft] = []
    var responseClientIDs: [UUID] = []
    var answerClientIDs: [UUID] = []
    var questionAttemptIDs: [(UUID, UUID)] = []
    var responseFailuresRemaining = 0
    var responseDelay: Duration = .zero
    var answerFailuresRemaining = 0
    var questionFailuresRemaining = 0
    var isObserving = false
    private var onChange: (@MainActor () async -> Void)?

    init(moments: [Moment]) {
        self.moments = moments
    }

    func currentUserID() async throws -> UUID { userID }

    func cachedMoments() -> [Moment]? { cachedMomentsValue }

    func cachedPhotoData(for momentID: UUID) -> Data? {
        cachedPhotoDataByMomentID[momentID]
    }

    func fetchMoments() async throws -> [Moment] {
        try await Task.sleep(for: fetchDelay)
        if fetchFailuresRemaining > 0 {
            fetchFailuresRemaining -= 1
            throw TestServiceError.expected
        }
        return moments
    }

    func createMoment(_ draft: MomentDraft, clientID: UUID) async throws -> Moment {
        createdDrafts.append(draft)
        let content: MomentContent
        switch draft {
        case let .mood(mood): content = .mood(mood)
        case let .text(value):
            content = .text(try #require(MomentDraftPolicy.normalizedText(value)))
        case .photo: content = .photo
        }
        let moment = Moment(
            id: clientID,
            creatorUserID: userID,
            content: content,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        moments.insert(moment, at: 0)
        return moment
    }

    func createQuestion(
        _ draft: MomentQuestionDraft,
        momentClientID: UUID,
        answerClientID: UUID
    ) async throws -> Moment {
        questionAttemptIDs.append((momentClientID, answerClientID))
        if questionFailuresRemaining > 0 {
            questionFailuresRemaining -= 1
            throw CancellationError()
        }
        let prompt = try #require(MomentQuestionPrompt.accepted.first { $0.id == draft.questionKey })
        let answer = try #require(MomentQuestionPolicy.normalizedAnswer(draft.answer))
        let moment = Moment(
            id: momentClientID,
            creatorUserID: userID,
            content: .question(MomentQuestion(key: prompt.id, prompt: prompt.prompt)),
            createdAt: Date(timeIntervalSince1970: 400),
            questionAnswers: [MomentQuestionAnswer(
                id: answerClientID,
                answererUserID: userID,
                content: answer,
                createdAt: Date(timeIntervalSince1970: 400)
            )]
        )
        moments.insert(moment, at: 0)
        return moment
    }

    func createResponse(
        to momentID: UUID,
        draft: MomentResponseDraft,
        clientID: UUID
    ) async throws -> MomentResponse {
        responseClientIDs.append(clientID)
        try await Task.sleep(for: responseDelay)
        if responseFailuresRemaining > 0 {
            responseFailuresRemaining -= 1
            throw CancellationError()
        }
        let index = try #require(moments.firstIndex { $0.id == momentID })
        let content: MomentResponseContent
        switch draft {
        case let .emoji(emoji): content = .emoji(emoji)
        case let .text(value): content = .text(try #require(MomentResponsePolicy.normalizedText(value)))
        }
        let response = MomentResponse(
            id: clientID,
            responderUserID: userID,
            content: content,
            createdAt: Date(timeIntervalSince1970: 300)
        )
        moments[index].responses.append(response)
        return response
    }

    func answerQuestion(momentID: UUID, answer: String, clientID: UUID) async throws
        -> MomentQuestionAnswer
    {
        answerClientIDs.append(clientID)
        if answerFailuresRemaining > 0 {
            answerFailuresRemaining -= 1
            throw CancellationError()
        }
        let index = try #require(moments.firstIndex { $0.id == momentID })
        let questionAnswer = MomentQuestionAnswer(
            id: clientID,
            answererUserID: userID,
            content: try #require(MomentQuestionPolicy.normalizedAnswer(answer)),
            createdAt: Date(timeIntervalSince1970: 300)
        )
        moments[index].questionAnswers.append(questionAnswer)
        return questionAnswer
    }

    func photoData(for momentID: UUID) async throws -> Data { Data() }

    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws {
        isObserving = true
        self.onChange = onChange
    }

    func stopObservingChanges() async {
        isObserving = false
        onChange = nil
    }

    func sendChange() async {
        await onChange?()
    }
}
