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

    @Test func sharedAppointmentPolicyNormalizesFieldsAndRejectsInvalidReminder() throws {
        let startsAt = Date(timeIntervalSince1970: 10_000)
        let normalized = try #require(SharedAppointmentPolicy.normalizedDraft(
            SharedAppointmentDraft(
                title: "  週末晚餐  ",
                startsAt: startsAt,
                location: "  中山站  ",
                note: "  記得訂位  ",
                reminderAt: startsAt.addingTimeInterval(-1_800),
                sourceMessageID: nil
            )
        ))

        #expect(normalized.title == "週末晚餐")
        #expect(normalized.location == "中山站")
        #expect(normalized.note == "記得訂位")
        #expect(SharedAppointmentPolicy.normalizedDraft(
            SharedAppointmentDraft(
                title: "晚餐",
                startsAt: startsAt,
                location: nil,
                note: nil,
                reminderAt: startsAt.addingTimeInterval(1),
                sourceMessageID: nil
            )
        ) == nil)
    }

    @MainActor
    @Test func appointmentReminderPolicySchedulesOnlySyncedFutureAppointmentsPrivately() {
        let now = Date(timeIntervalSince1970: 10_000)
        let futureID = UUID(uuidString: "A4000000-0000-0000-0000-0000000000A1")!
        func appointment(
            id: UUID = UUID(),
            reminderAt: Date?,
            status: SharedAppointmentStatus = .scheduled,
            deliveryState: SharedAppointmentDeliveryState = .synced
        ) -> SharedAppointment {
            SharedAppointment(
                id: id,
                creatorUserID: UUID(),
                title: "私人晚餐標題",
                startsAt: now.addingTimeInterval(7_200),
                location: "私人地點",
                note: "私人註記",
                reminderAt: reminderAt,
                status: status,
                sourceMessageID: nil,
                createdAt: now,
                updatedAt: now,
                deliveryState: deliveryState
            )
        }

        let requests = SharedAppointmentReminderPolicy.requests(
            for: [
                appointment(id: futureID, reminderAt: now.addingTimeInterval(3_600)),
                appointment(reminderAt: now),
                appointment(reminderAt: now.addingTimeInterval(3_600), status: .cancelled),
                appointment(
                    reminderAt: now.addingTimeInterval(3_600),
                    deliveryState: .sending
                ),
            ],
            identifierPrefix: "test.",
            now: now
        )

        #expect(requests == [SharedAppointmentReminderRequest(
            identifier: "test." + futureID.uuidString.lowercased(),
            appointmentID: futureID,
            fireDate: now.addingTimeInterval(3_600),
            title: "共同約定提醒",
            body: "你有一筆即將開始的共同約定。",
            userInfo: [
                "event_kind": "shared_appointment_reminder",
                "event_id": futureID.uuidString.lowercased(),
            ]
        )])
        #expect(requests[0].title.contains("私人晚餐標題") == false)
        #expect(requests[0].body.contains("私人地點") == false)
        #expect(requests[0].body.contains("私人註記") == false)
        #expect(requests[0].userInfo.keys.sorted() == ["event_id", "event_kind"])
    }

    @MainActor
    @Test func sharedAppointmentModelReconcilesRemindersAfterRemoteRefresh() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let appointment = SharedAppointment(
            id: UUID(),
            creatorUserID: UUID(),
            title: "晚餐",
            startsAt: now.addingTimeInterval(7_200),
            location: nil,
            note: nil,
            reminderAt: now.addingTimeInterval(3_600),
            status: .scheduled,
            sourceMessageID: nil,
            createdAt: now,
            updatedAt: now
        )
        let service = SharedAppointmentRemoteServiceFake()
        service.appointments = [appointment]
        let scheduler = SharedAppointmentReminderSchedulerFake()
        let model = SharedAppointmentModel(
            service: service,
            now: { now },
            reminderScheduler: scheduler
        )

        await model.refresh()

        #expect(scheduler.reconciledAppointments == [[appointment]])
        #expect(model.reminderStatusMessage == nil)
    }

    @MainActor
    @Test func deniedAppointmentReminderPermissionIsExplicitButDoesNotBlockSync() async {
        let scheduler = SharedAppointmentReminderSchedulerFake()
        scheduler.authorization = .denied
        let model = SharedAppointmentModel(
            service: SharedAppointmentRemoteServiceFake(),
            reminderScheduler: scheduler
        )

        await model.prepareReminderAuthorization()

        #expect(scheduler.authorizationRequestCount == 1)
        #expect(model.reminderStatusMessage?.contains("不會在指定時間提醒") == true)
    }

    @MainActor
    @Test func appointmentReminderRouteAcceptsOnlyOpaqueAppointmentEvents() {
        _ = SharedAppointmentNotificationRoute.consumePendingAppointmentID()
        SharedAppointmentNotificationRoute.receive(userInfo: [
            "event_kind": "message_created",
            "event_id": UUID().uuidString,
        ])
        #expect(SharedAppointmentNotificationRoute.consumePendingAppointmentID() == nil)

        let appointmentID = UUID()
        SharedAppointmentNotificationRoute.receive(userInfo: [
            "event_kind": "shared_appointment_reminder",
            "event_id": appointmentID.uuidString.lowercased(),
        ])
        #expect(SharedAppointmentNotificationRoute.consumePendingAppointmentID() == appointmentID)
        #expect(SharedAppointmentNotificationRoute.consumePendingAppointmentID() == nil)
    }

    @MainActor
    @Test func sharedAppointmentModelGroupsScheduledAndCancelledItemsByLocalDay() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let selectedDate = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 14,
            hour: 12
        )))
        let earlyID = UUID()
        let cancelledID = UUID()
        let nextDayID = UUID()
        let service = SharedAppointmentRemoteServiceFake()

        func appointment(
            id: UUID,
            day: Int,
            hour: Int,
            status: SharedAppointmentStatus
        ) throws -> SharedAppointment {
            let startsAt = try #require(calendar.date(from: DateComponents(
                year: 2026,
                month: 8,
                day: day,
                hour: hour
            )))
            return SharedAppointment(
                id: id,
                creatorUserID: UUID(),
                title: id.uuidString,
                startsAt: startsAt,
                location: nil,
                note: nil,
                reminderAt: nil,
                status: status,
                sourceMessageID: nil,
                createdAt: startsAt,
                updatedAt: startsAt
            )
        }

        service.appointments = [
            try appointment(id: cancelledID, day: 14, hour: 20, status: .cancelled),
            try appointment(id: nextDayID, day: 15, hour: 0, status: .scheduled),
            try appointment(id: earlyID, day: 14, hour: 8, status: .scheduled),
        ]
        let model = SharedAppointmentModel(service: service)
        await model.refresh()

        #expect(model.appointments(on: selectedDate, calendar: calendar).map(\.id) == [
            earlyID,
            cancelledID,
        ])
    }

    @MainActor
    @Test func sharedAppointmentModelLoadsOnlyEventsForVisibleAppointmentsInServerOrder() async {
        let appointmentID = UUID()
        let missingAppointmentID = UUID()
        let actorID = UUID()
        let firstEventID = UUID()
        let secondEventID = UUID()
        let now = Date(timeIntervalSince1970: 900)
        let service = SharedAppointmentRemoteServiceFake()
        service.appointments = [SharedAppointment(
            id: appointmentID,
            creatorUserID: actorID,
            title: "有永久紀錄的約定",
            startsAt: now.addingTimeInterval(7_200),
            location: nil,
            note: nil,
            reminderAt: nil,
            status: .cancelled,
            sourceMessageID: nil,
            createdAt: now,
            updatedAt: now
        )]
        service.appointmentEvents = [
            SharedAppointmentEvent(
                id: secondEventID,
                appointmentID: appointmentID,
                actorUserID: actorID,
                kind: .cancelled,
                previousStartsAt: nil,
                startsAt: nil,
                createdAt: now.addingTimeInterval(2)
            ),
            SharedAppointmentEvent(
                id: UUID(),
                appointmentID: missingAppointmentID,
                actorUserID: actorID,
                kind: .cancelled,
                previousStartsAt: nil,
                startsAt: nil,
                createdAt: now.addingTimeInterval(3)
            ),
            SharedAppointmentEvent(
                id: firstEventID,
                appointmentID: appointmentID,
                actorUserID: actorID,
                kind: .rescheduled,
                previousStartsAt: now.addingTimeInterval(3_600),
                startsAt: now.addingTimeInterval(7_200),
                createdAt: now.addingTimeInterval(1)
            ),
        ]
        let model = SharedAppointmentModel(service: service, now: { now })

        await model.refresh()

        #expect(model.appointmentEvents.map(\.id) == [firstEventID, secondEventID])
        #expect(model.events(for: appointmentID).map(\.kind) == [.rescheduled, .cancelled])
        #expect(model.events(for: missingAppointmentID).isEmpty)
    }

    @MainActor
    @Test func sharedAppointmentModelReusesStableIdentityAfterFailedCreate() async throws {
        let service = SharedAppointmentRemoteServiceFake()
        service.createFailuresRemaining = 1
        let now = Date(timeIntervalSince1970: 1_000)
        let model = SharedAppointmentModel(service: service, now: { now })
        let draft = SharedAppointmentDraft(
            title: "一起吃晚餐",
            startsAt: now.addingTimeInterval(3_600),
            location: nil,
            note: nil,
            reminderAt: nil,
            sourceMessageID: nil
        )

        #expect(await model.create(draft))
        let pendingID = try #require(model.nextAppointment?.id)
        #expect(model.nextAppointment?.deliveryState == .failed)
        await model.retryAppointment(id: pendingID)
        #expect(service.deliveryClientIDs.count == 2)
        #expect(service.deliveryClientIDs.first == service.deliveryClientIDs.last)
        #expect(model.nextAppointment?.title == "一起吃晚餐")
        #expect(model.nextAppointment?.deliveryState == .synced)
    }

    @MainActor
    @Test func sharedAppointmentModelOrdersRecentDiscussionsAndTotalsUnread() async throws {
        let service = SharedAppointmentRemoteServiceFake()
        let olderID = UUID()
        let newerID = UUID()
        let missingAppointmentID = UUID()
        let additionalIDs = (0..<4).map { _ in UUID() }
        let now = Date(timeIntervalSince1970: 1_500)
        service.appointments = ([olderID, newerID] + additionalIDs).map { id in
            SharedAppointment(
                id: id,
                creatorUserID: UUID(),
                title: id == newerID ? "最新討論" : "較早討論",
                startsAt: now.addingTimeInterval(3_600),
                location: nil,
                note: nil,
                reminderAt: nil,
                status: .scheduled,
                sourceMessageID: nil,
                createdAt: now,
                updatedAt: now
            )
        }
        service.discussionSummaries = [
            SharedAppointmentDiscussionSummary(
                appointmentID: olderID,
                latestActivityAt: now,
                unreadCount: 1
            ),
            SharedAppointmentDiscussionSummary(
                appointmentID: missingAppointmentID,
                latestActivityAt: now.addingTimeInterval(300),
                unreadCount: 99
            ),
            SharedAppointmentDiscussionSummary(
                appointmentID: newerID,
                latestActivityAt: now.addingTimeInterval(100),
                unreadCount: 2
            ),
        ] + additionalIDs.enumerated().map { index, id in
            SharedAppointmentDiscussionSummary(
                appointmentID: id,
                latestActivityAt: now.addingTimeInterval(TimeInterval(-100 - index)),
                unreadCount: 1
            )
        }
        let model = SharedAppointmentModel(service: service, now: { now })

        await model.refresh()

        #expect(model.recentDiscussionSummaries.count == 6)
        #expect(model.recentDiscussionSummaries.prefix(2).map(\.appointmentID) == [newerID, olderID])
        #expect(model.discussionUnreadCount == 7)
    }

    @Test func sharedAppointmentOutboxPersistsFIFOAcrossStoreRecreation() throws {
        let suiteName = "SharedAppointmentOutboxTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = UUID()
        let relationshipID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let startsAt = Date(timeIntervalSince1970: 10_000)
        let firstStore = SharedAppointmentOutboxStore(defaults: defaults)
        for (clientID, title) in [(firstID, "第一筆"), (secondID, "第二筆")] {
            try firstStore.enqueue(
                SharedAppointmentDraft(
                    title: title,
                    startsAt: startsAt,
                    location: nil,
                    note: nil,
                    reminderAt: nil,
                    sourceMessageID: nil
                ),
                userID: userID,
                relationshipID: relationshipID,
                clientID: clientID,
                localCreatedAt: startsAt.addingTimeInterval(-100)
            )
        }

        let restored = try SharedAppointmentOutboxStore(defaults: defaults).load(
            userID: userID,
            relationshipID: relationshipID
        )
        #expect(restored.entries.map(\.clientID) == [firstID, secondID])
    }

    @Test func sharedAppointmentSnapshotPersistsSyncedItemsWithinAccountRelationshipScope() throws {
        let suiteName = "SharedAppointmentSnapshotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SharedAppointmentSnapshotStore(defaults: defaults)
        let userID = UUID()
        let relationshipID = UUID()
        let now = Date(timeIntervalSince1970: 2_000)
        let appointments = (0...SharedAppointmentLocalSnapshotPolicy.maximumAppointmentCount).map { index in
            SharedAppointment(
                id: UUID(),
                creatorUserID: userID,
                title: "約定 \(index)",
                startsAt: now.addingTimeInterval(TimeInterval(index)),
                location: nil,
                note: nil,
                reminderAt: nil,
                status: .scheduled,
                sourceMessageID: nil,
                createdAt: now,
                updatedAt: now
            )
        }

        try store.save(appointments, userID: userID, relationshipID: relationshipID)

        let restored = try #require(
            try store.load(userID: userID, relationshipID: relationshipID)
        )
        #expect(restored.count == SharedAppointmentLocalSnapshotPolicy.maximumAppointmentCount)
        #expect(restored.first?.title == "約定 1")
        let latest = try #require(restored.last)
        try store.upsert(
            SharedAppointment(
                id: latest.id,
                creatorUserID: latest.creatorUserID,
                title: "伺服器已接受的更新",
                startsAt: latest.startsAt,
                location: latest.location,
                note: latest.note,
                reminderAt: latest.reminderAt,
                status: .cancelled,
                sourceMessageID: latest.sourceMessageID,
                createdAt: latest.createdAt,
                updatedAt: latest.updatedAt.addingTimeInterval(1)
            ),
            userID: userID,
            relationshipID: relationshipID
        )
        #expect(
            try store.load(userID: userID, relationshipID: relationshipID)?.last?.title
                == "伺服器已接受的更新"
        )
        #expect(try store.load(userID: UUID(), relationshipID: relationshipID) == nil)
        #expect(try store.load(userID: userID, relationshipID: UUID()) == nil)
        store.clearAll(userID: userID)
        #expect(try store.load(userID: userID, relationshipID: relationshipID) == nil)
    }

    @MainActor
    @Test func sharedAppointmentOfflineRestartRestoresCachedBaseBeforePendingEdit() async throws {
        let now = Date(timeIntervalSince1970: 2_500)
        let appointmentID = UUID()
        let base = SharedAppointment(
            id: appointmentID,
            creatorUserID: UUID(),
            title: "離線前約定",
            startsAt: now.addingTimeInterval(3_600),
            location: nil,
            note: nil,
            reminderAt: nil,
            status: .scheduled,
            sourceMessageID: UUID(),
            createdAt: now,
            updatedAt: now
        )
        let updatedStartsAt = now.addingTimeInterval(7_200)
        let operationID = UUID()
        let service = SharedAppointmentRemoteServiceFake()
        service.appointments = [base]
        service.cachedAppointments = [base]
        service.suspendFetchAppointments = true
        service.fetchAppointmentsFails = true
        service.operationFailuresRemaining = ConversationRecoveryRetryPolicy.maximumAttempts
        service.pendingOperations = [SharedAppointmentOperationOutboxEntry(
            userID: UUID(),
            relationshipID: UUID(),
            operationID: operationID,
            appointmentID: appointmentID,
            operation: .update(SharedAppointmentDraft(
                title: "離線修改後",
                startsAt: updatedStartsAt,
                location: nil,
                note: nil,
                reminderAt: nil,
                sourceMessageID: nil
            )),
            localCreatedAt: now,
            attemptCount: 0
        )]
        let model = SharedAppointmentModel(service: service, now: { now })

        let startup = Task { await model.start() }
        while service.fetchAppointmentsContinuation == nil {
            await Task.yield()
        }

        #expect(model.appointment(id: appointmentID)?.title == "離線修改後")
        #expect(model.appointment(id: appointmentID)?.startsAt == updatedStartsAt)
        #expect(model.statusMessage == "約定變更已保存在這支裝置；請確認連線後重試。")
        #expect(service.deliveredOperationIDs.isEmpty)

        service.resumeFetchAppointments()
        startup.cancel()
        await startup.value
        #expect(model.appointment(id: appointmentID)?.title == "離線修改後")
    }

    @MainActor
    @Test func sharedAppointmentLostAcknowledgementRetriesWithoutDuplicate() async throws {
        let service = SharedAppointmentRemoteServiceFake()
        service.acknowledgementFailuresRemaining = 1
        let now = Date(timeIntervalSince1970: 2_000)
        let model = SharedAppointmentModel(service: service, now: { now })

        #expect(await model.create(SharedAppointmentDraft(
            title: "不重複的約定",
            startsAt: now.addingTimeInterval(3_600),
            location: nil,
            note: nil,
            reminderAt: nil,
            sourceMessageID: nil
        )))
        let pendingID = try #require(model.nextAppointment?.id)
        #expect(model.nextAppointment?.deliveryState == .failed)

        await model.retryAppointment(id: pendingID)

        #expect(service.appointments.count == 1)
        #expect(service.deliveryClientIDs == [pendingID, pendingID])
        #expect(model.nextAppointment?.deliveryState == .synced)
    }

    @Test func sharedAppointmentOperationOutboxPersistsFIFOAndRejectsEditAfterCancellation() throws {
        let suiteName = "SharedAppointmentOperationOutboxTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SharedAppointmentOperationOutboxStore(defaults: defaults)
        let userID = UUID()
        let relationshipID = UUID()
        let appointmentID = UUID()
        let editID = UUID()
        let cancelID = UUID()
        let localCreatedAt = Date(timeIntervalSince1970: 2_500)
        let draft = SharedAppointmentDraft(
            title: "更新後",
            startsAt: localCreatedAt.addingTimeInterval(3_600),
            location: nil,
            note: nil,
            reminderAt: nil,
            sourceMessageID: UUID()
        )

        try store.enqueue(
            appointmentID: appointmentID,
            operationID: editID,
            operation: .update(draft),
            userID: userID,
            relationshipID: relationshipID,
            localCreatedAt: localCreatedAt
        )
        try store.enqueue(
            appointmentID: appointmentID,
            operationID: cancelID,
            operation: .cancel,
            userID: userID,
            relationshipID: relationshipID,
            localCreatedAt: localCreatedAt.addingTimeInterval(1)
        )

        let restored = try SharedAppointmentOperationOutboxStore(defaults: defaults).load(
            userID: userID,
            relationshipID: relationshipID
        )
        #expect(restored.entries.map(\.operationID) == [editID, cancelID])
        #expect(try store.load(userID: UUID(), relationshipID: relationshipID).isEmpty)
        #expect(try store.load(userID: userID, relationshipID: UUID()).isEmpty)
        #expect(throws: SharedAppointmentOperationOutboxError.self) {
            try store.enqueue(
                appointmentID: appointmentID,
                operationID: UUID(),
                operation: .update(draft),
                userID: userID,
                relationshipID: relationshipID,
                localCreatedAt: localCreatedAt.addingTimeInterval(2)
            )
        }
    }

    @MainActor
    @Test func sharedAppointmentEditLostAcknowledgementRetriesStableOperation() async throws {
        let now = Date(timeIntervalSince1970: 2_700)
        let appointmentID = UUID()
        let service = SharedAppointmentRemoteServiceFake()
        service.operationAcknowledgementFailuresRemaining = 1
        service.appointments = [SharedAppointment(
            id: appointmentID,
            creatorUserID: UUID(),
            title: "原本",
            startsAt: now.addingTimeInterval(3_600),
            location: nil,
            note: nil,
            reminderAt: nil,
            status: .scheduled,
            sourceMessageID: UUID(),
            createdAt: now,
            updatedAt: now
        )]
        let model = SharedAppointmentModel(service: service, now: { now })
        await model.refresh()

        #expect(await model.update(
            id: appointmentID,
            draft: SharedAppointmentDraft(
                title: "更新後",
                startsAt: now.addingTimeInterval(7_200),
                location: nil,
                note: nil,
                reminderAt: nil,
                sourceMessageID: nil
            )
        ))
        let operationID = try #require(service.pendingOperations.first?.operationID)
        #expect(model.appointment(id: appointmentID)?.title == "更新後")

        await model.recoverPendingAppointments()

        #expect(service.deliveredOperationIDs == [operationID, operationID])
        #expect(service.pendingOperations.isEmpty)
        #expect(service.appointments.count == 1)
        #expect(model.appointment(id: appointmentID)?.title == "更新後")
    }

    @MainActor
    @Test func sharedAppointmentCancellationRecoversAfterModelRecreation() async throws {
        let now = Date(timeIntervalSince1970: 2_900)
        let appointmentID = UUID()
        let service = SharedAppointmentRemoteServiceFake()
        service.operationFailuresRemaining = 1
        service.appointments = [SharedAppointment(
            id: appointmentID,
            creatorUserID: UUID(),
            title: "待取消",
            startsAt: now.addingTimeInterval(3_600),
            location: nil,
            note: nil,
            reminderAt: nil,
            status: .scheduled,
            sourceMessageID: nil,
            createdAt: now,
            updatedAt: now
        )]
        let firstModel = SharedAppointmentModel(service: service, now: { now })
        await firstModel.refresh()

        #expect(await firstModel.cancel(id: appointmentID))
        #expect(firstModel.appointment(id: appointmentID)?.status == .cancelled)
        #expect(service.appointments.first?.status == .scheduled)

        let restoredModel = SharedAppointmentModel(service: service, now: { now })
        await restoredModel.recoverPendingAppointments()

        #expect(service.pendingOperations.isEmpty)
        #expect(service.appointments.first?.status == .cancelled)
        #expect(restoredModel.appointment(id: appointmentID)?.status == .cancelled)
    }

    @MainActor
    @Test func terminalAppointmentOperationDoesNotBlockLaterFIFOEntries() async throws {
        let now = Date(timeIntervalSince1970: 2_950)
        let cancelledID = UUID()
        let scheduledID = UUID()
        let rejectedOperationID = UUID()
        let acceptedOperationID = UUID()
        let service = SharedAppointmentRemoteServiceFake()
        service.appointments = [
            SharedAppointment(
                id: cancelledID,
                creatorUserID: UUID(),
                title: "已被伴侶取消",
                startsAt: now.addingTimeInterval(3_600),
                location: nil,
                note: nil,
                reminderAt: nil,
                status: .cancelled,
                sourceMessageID: nil,
                createdAt: now,
                updatedAt: now
            ),
            SharedAppointment(
                id: scheduledID,
                creatorUserID: UUID(),
                title: "仍可編輯",
                startsAt: now.addingTimeInterval(7_200),
                location: nil,
                note: nil,
                reminderAt: nil,
                status: .scheduled,
                sourceMessageID: nil,
                createdAt: now,
                updatedAt: now
            ),
        ]
        service.terminallyRejectedAppointmentIDs = [cancelledID]
        service.pendingOperations = [
            SharedAppointmentOperationOutboxEntry(
                userID: UUID(),
                relationshipID: UUID(),
                operationID: rejectedOperationID,
                appointmentID: cancelledID,
                operation: .update(SharedAppointmentDraft(
                    title: "不能復活",
                    startsAt: now.addingTimeInterval(3_600),
                    location: nil,
                    note: nil,
                    reminderAt: nil,
                    sourceMessageID: nil
                )),
                localCreatedAt: now,
                attemptCount: 0
            ),
            SharedAppointmentOperationOutboxEntry(
                userID: UUID(),
                relationshipID: UUID(),
                operationID: acceptedOperationID,
                appointmentID: scheduledID,
                operation: .update(SharedAppointmentDraft(
                    title: "後續操作已送達",
                    startsAt: now.addingTimeInterval(7_200),
                    location: nil,
                    note: nil,
                    reminderAt: nil,
                    sourceMessageID: nil
                )),
                localCreatedAt: now.addingTimeInterval(1),
                attemptCount: 0
            ),
        ]
        let model = SharedAppointmentModel(service: service, now: { now })

        await model.recoverPendingAppointments()

        #expect(service.deliveredOperationIDs == [rejectedOperationID, acceptedOperationID])
        #expect(service.pendingOperations.isEmpty)
        #expect(model.appointment(id: cancelledID)?.status == .cancelled)
        #expect(model.appointment(id: scheduledID)?.title == "後續操作已送達")
        #expect(model.statusMessage == "這筆約定已取消，未再套用待送編輯。")
    }

    @MainActor
    @Test func archivedRelationshipOperationFailureIsTerminal() {
        #expect(SupabaseSharedAppointmentService.isTerminalOperationError(
            "relationship_not_accessible"
        ))
    }

    @MainActor
    @Test func sharedAppointmentRecoveryKeepsOfflineDeliveryExplanation() async throws {
        let service = SharedAppointmentRemoteServiceFake()
        service.createFailuresRemaining = ConversationRecoveryRetryPolicy.maximumAttempts
        let now = Date(timeIntervalSince1970: 3_000)
        let clientID = UUID()
        service.pendingEntries = [SharedAppointmentOutboxEntry(
            userID: UUID(),
            relationshipID: UUID(),
            clientID: clientID,
            draft: SharedAppointmentDraft(
                title: "離線待同步約定",
                startsAt: now.addingTimeInterval(3_600),
                location: nil,
                note: nil,
                reminderAt: nil,
                sourceMessageID: nil
            ),
            localCreatedAt: now,
            attemptCount: 0
        )]
        let model = SharedAppointmentModel(service: service, now: { now })

        await model.recoverPendingAppointments()

        #expect(model.nextAppointment?.id == clientID)
        #expect(model.nextAppointment?.deliveryState == .failed)
        #expect(model.statusMessage == "共同約定已保存在這支裝置；請確認連線後重試。")
    }

    @MainActor
    @Test func sharedAppointmentModelEditsThenCancelsWithoutLosingSource() async throws {
        let now = Date(timeIntervalSince1970: 4_000)
        let appointmentID = UUID()
        let sourceMessageID = UUID()
        let service = SharedAppointmentRemoteServiceFake()
        service.appointments = [SharedAppointment(
            id: appointmentID,
            creatorUserID: UUID(),
            title: "原本的約定",
            startsAt: now.addingTimeInterval(3_600),
            location: nil,
            note: nil,
            reminderAt: nil,
            status: .scheduled,
            sourceMessageID: sourceMessageID,
            createdAt: now,
            updatedAt: now
        )]
        let model = SharedAppointmentModel(service: service, now: { now })
        await model.refresh()

        #expect(await model.update(
            id: appointmentID,
            draft: SharedAppointmentDraft(
                title: "更新後的約定",
                startsAt: now.addingTimeInterval(7_200),
                location: "中山站",
                note: "記得訂位",
                reminderAt: now.addingTimeInterval(5_400),
                sourceMessageID: UUID()
            )
        ))
        #expect(model.appointment(id: appointmentID)?.title == "更新後的約定")
        #expect(model.appointment(id: appointmentID)?.sourceMessageID == sourceMessageID)
        #expect(model.events(for: appointmentID).map(\.kind) == [.rescheduled])

        #expect(await model.cancel(id: appointmentID))
        #expect(model.appointment(id: appointmentID)?.status == .cancelled)
        #expect(model.events(for: appointmentID).map(\.kind) == [.rescheduled, .cancelled])
        #expect(model.nextAppointment == nil)
        #expect(model.pastOrCancelledAppointments.map(\.id) == [appointmentID])

        #expect(await model.update(
            id: appointmentID,
            draft: SharedAppointmentDraft(
                title: "不應復活",
                startsAt: now.addingTimeInterval(10_800),
                location: nil,
                note: nil,
                reminderAt: nil,
                sourceMessageID: nil
            )
        ) == false)
        #expect(model.appointment(id: appointmentID)?.status == .cancelled)
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

    @Test func appointmentDiscussionOutboxAndSnapshotStayIsolatedFromMainChat() throws {
        let suiteName = "AppointmentDiscussionConversationScopeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let userID = UUID()
        let relationshipID = UUID()
        let otherRelationshipID = UUID()
        let firstAppointmentID = UUID()
        let secondAppointmentID = UUID()
        let mainMessageID = UUID()
        let firstDiscussionMessageID = UUID()
        let secondDiscussionMessageID = UUID()
        let otherRelationshipMessageID = UUID()
        let mainStore = ConversationOutboxStore(
            defaults: defaults,
            directoryURL: directoryURL
        )
        let firstDiscussionStore = ConversationOutboxStore(
            defaults: defaults,
            directoryURL: directoryURL,
            availableCapacity: { _ in Int64.max },
            appointmentScopeID: firstAppointmentID
        )
        let secondDiscussionStore = ConversationOutboxStore(
            defaults: defaults,
            directoryURL: directoryURL,
            appointmentScopeID: secondAppointmentID
        )
        let otherRelationshipStore = ConversationOutboxStore(
            defaults: defaults,
            directoryURL: directoryURL,
            appointmentScopeID: firstAppointmentID
        )

        try mainStore.enqueueText(
            "主對話",
            userID: userID,
            relationshipID: relationshipID,
            clientID: mainMessageID,
            localCreatedAt: .now
        )
        let discussionPhotoData = Data([0x01, 0x02, 0x03])
        try firstDiscussionStore.enqueuePhoto(
            discussionPhotoData,
            userID: userID,
            relationshipID: relationshipID,
            clientID: firstDiscussionMessageID,
            localCreatedAt: .now
        )
        try secondDiscussionStore.enqueueText(
            "第二個約定",
            userID: userID,
            relationshipID: relationshipID,
            clientID: secondDiscussionMessageID,
            localCreatedAt: .now
        )
        try otherRelationshipStore.enqueueText(
            "另一段關係",
            userID: userID,
            relationshipID: otherRelationshipID,
            clientID: otherRelationshipMessageID,
            localCreatedAt: .now
        )

        #expect(try mainStore.load(userID: userID, relationshipID: relationshipID)
            .entries.map(\.clientID) == [mainMessageID])
        #expect(try firstDiscussionStore.load(userID: userID, relationshipID: relationshipID)
            .entries.map(\.clientID) == [firstDiscussionMessageID])
        #expect(try secondDiscussionStore.load(userID: userID, relationshipID: relationshipID)
            .entries.map(\.clientID) == [secondDiscussionMessageID])
        let discussionPhotoEntry = try #require(
            try firstDiscussionStore.load(userID: userID, relationshipID: relationshipID)
                .entries.first
        )
        #expect(try firstDiscussionStore.data(for: discussionPhotoEntry) == discussionPhotoData)
        #expect(Set(mainStore.appointmentDiscussionScopeIDs(
            userID: userID,
            relationshipID: relationshipID
        )) == Set([firstAppointmentID, secondAppointmentID]))

        let mainSnapshotStore = ConversationSnapshotStore(defaults: defaults)
        let discussionSnapshotStore = ConversationSnapshotStore(
            defaults: defaults,
            appointmentScopeID: firstAppointmentID
        )
        try mainSnapshotStore.save(
            ConversationSnapshot(
                currentUserID: userID,
                messages: [ChatMessage(
                    id: mainMessageID,
                    senderUserID: userID,
                    body: "主對話",
                    createdAt: .now
                )],
                unreadCount: 0
            ),
            userID: userID,
            relationshipID: relationshipID
        )
        try discussionSnapshotStore.save(
            ConversationSnapshot(
                currentUserID: userID,
                messages: [ChatMessage(
                    id: firstDiscussionMessageID,
                    senderUserID: userID,
                    body: "第一個約定",
                    createdAt: .now
                )],
                unreadCount: 1
            ),
            userID: userID,
            relationshipID: relationshipID
        )
        #expect(try mainSnapshotStore.load(userID: userID, relationshipID: relationshipID)?
            .messages.map(\.id) == [mainMessageID])
        #expect(try discussionSnapshotStore.load(userID: userID, relationshipID: relationshipID)?
            .messages.map(\.id) == [firstDiscussionMessageID])

        mainStore.clearAppointmentDiscussions(userID: userID, relationshipID: relationshipID)

        #expect(try mainStore.load(userID: userID, relationshipID: relationshipID)
            .entries.map(\.clientID) == [mainMessageID])
        #expect(try firstDiscussionStore.load(userID: userID, relationshipID: relationshipID).isEmpty)
        #expect(try secondDiscussionStore.load(userID: userID, relationshipID: relationshipID).isEmpty)
        #expect(throws: ConversationOutboxError.missingLocalFile) {
            try firstDiscussionStore.data(for: discussionPhotoEntry)
        }
        #expect(try otherRelationshipStore.load(userID: userID, relationshipID: otherRelationshipID)
            .entries.map(\.clientID) == [otherRelationshipMessageID])
    }

    @Test func conversationClosingAndArchiveDiscardUnsentText() throws {
        let content = ConversationOutboxContent.text("關係結束前尚未送出")

        #expect(try ConversationOutboxLifecyclePolicy.actionForClosingRelationship(
            content: content,
            remoteCreatorID: nil,
            remoteItemKind: nil,
            currentUserID: UUID()
        ) == .discardUnsentText)
        #expect(try ConversationOutboxLifecyclePolicy.actionForArchivedRelationship(
            content: content,
            archivedItemKind: nil
        ) == .discardUnsentText)
    }

    @Test func conversationClosingReconcilesDeliveredAndOrphanPhotos() throws {
        let userID = UUID()
        let photo = ConversationOutboxContent.photo(localFileName: "photo.jpg", byteSize: 3)

        #expect(try ConversationOutboxLifecyclePolicy.actionForClosingRelationship(
            content: photo,
            remoteCreatorID: userID,
            remoteItemKind: "photo",
            currentUserID: userID
        ) == .acknowledgeDeliveredPhoto)
        #expect(try ConversationOutboxLifecyclePolicy.actionForClosingRelationship(
            content: photo,
            remoteCreatorID: nil,
            remoteItemKind: nil,
            currentUserID: userID
        ) == .deleteOrphanPhoto)
    }

    @Test func conversationClosingPreservesPhotoOnRemoteIdentityMismatch() {
        let userID = UUID()
        let photo = ConversationOutboxContent.photo(localFileName: "photo.jpg", byteSize: 3)

        #expect(throws: ConversationOutboxLifecyclePolicy.ReconciliationError.remoteIdentityMismatch) {
            try ConversationOutboxLifecyclePolicy.actionForClosingRelationship(
                content: photo,
                remoteCreatorID: UUID(),
                remoteItemKind: "photo",
                currentUserID: userID
            )
        }
        #expect(throws: ConversationOutboxLifecyclePolicy.ReconciliationError.remoteIdentityMismatch) {
            try ConversationOutboxLifecyclePolicy.actionForClosingRelationship(
                content: photo,
                remoteCreatorID: userID,
                remoteItemKind: "message",
                currentUserID: userID
            )
        }
    }

    @Test func conversationArchiveReconcilesPhotoFromSealedMetadata() throws {
        let photo = ConversationOutboxContent.photo(localFileName: "photo.jpg", byteSize: 3)

        #expect(try ConversationOutboxLifecyclePolicy.actionForArchivedRelationship(
            content: photo,
            archivedItemKind: "photo"
        ) == .acknowledgeDeliveredPhoto)
        #expect(try ConversationOutboxLifecyclePolicy.actionForArchivedRelationship(
            content: photo,
            archivedItemKind: nil
        ) == .deleteOrphanPhoto)
        #expect(throws: ConversationOutboxLifecyclePolicy.ReconciliationError.remoteIdentityMismatch) {
            try ConversationOutboxLifecyclePolicy.actionForArchivedRelationship(
                content: photo,
                archivedItemKind: "message"
            )
        }
    }

    @Test func conversationV1OutboxAndSnapshotRemainDecodable() throws {
        let suiteName = "ConversationV1CompatibilityTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = UUID()
        let relationshipID = UUID()
        let messageID = UUID()
        let createdAt = Date(timeIntervalSince1970: 123)

        let legacyOutbox = LegacyConversationOutboxQueue(entries: [
            LegacyConversationOutboxEntry(
                userID: userID,
                relationshipID: relationshipID,
                clientID: messageID,
                body: "升級前待送訊息",
                localCreatedAt: createdAt,
                attemptCount: 1
            ),
        ])
        defaults.set(
            try JSONEncoder().encode(legacyOutbox),
            forKey: "couplespace.conversation-outbox.v1.\(userID.uuidString.lowercased()).\(relationshipID.uuidString.lowercased())"
        )

        let restoredOutbox = try ConversationOutboxStore(defaults: defaults).load(
            userID: userID,
            relationshipID: relationshipID
        )
        #expect(restoredOutbox.entries.first?.content == .text("升級前待送訊息"))
        #expect(restoredOutbox.entries.first?.attemptCount == 1)

        let legacySnapshot = LegacyConversationSnapshot(
            messages: [LegacyConversationCachedMessage(
                id: messageID,
                senderUserID: userID,
                body: "升級前對話",
                createdAt: createdAt
            )],
            unreadCount: 2
        )
        defaults.set(
            try JSONEncoder().encode(legacySnapshot),
            forKey: "couplespace.conversation-snapshot.v1.\(userID.uuidString.lowercased()).\(relationshipID.uuidString.lowercased())"
        )

        let restoredSnapshot = try #require(
            try ConversationSnapshotStore(defaults: defaults).load(
                userID: userID,
                relationshipID: relationshipID
            )
        )
        #expect(restoredSnapshot.messages.first?.content == .text("升級前對話"))
        #expect(restoredSnapshot.unreadCount == 2)
    }

    @Test func conversationOutboxPersistsMixedFIFOAndDeletesAcknowledgedPhoto() throws {
        let suiteName = "ConversationMixedOutboxTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConversationMixedOutboxTests.\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let userID = UUID()
        let relationshipID = UUID()
        let firstTextID = UUID()
        let photoID = UUID()
        let lastTextID = UUID()
        let photoData = Data([0x01, 0x02, 0x03])
        let store = ConversationOutboxStore(
            defaults: defaults,
            directoryURL: directoryURL,
            availableCapacity: { _ in Int64.max }
        )

        try store.enqueueText(
            "第一則",
            userID: userID,
            relationshipID: relationshipID,
            clientID: firstTextID,
            localCreatedAt: Date(timeIntervalSince1970: 100)
        )
        try store.enqueuePhoto(
            photoData,
            userID: userID,
            relationshipID: relationshipID,
            clientID: photoID,
            localCreatedAt: Date(timeIntervalSince1970: 101)
        )
        try store.enqueueText(
            "第三則",
            userID: userID,
            relationshipID: relationshipID,
            clientID: lastTextID,
            localCreatedAt: Date(timeIntervalSince1970: 102)
        )

        let rebuiltStore = ConversationOutboxStore(
            defaults: defaults,
            directoryURL: directoryURL,
            availableCapacity: { _ in Int64.max }
        )
        let restored = try rebuiltStore.load(userID: userID, relationshipID: relationshipID)
        #expect(restored.entries.map(\.clientID) == [firstTextID, photoID, lastTextID])
        #expect(restored.messages.map(\.content) == [.text("第一則"), .photo, .text("第三則")])
        let photoEntry = try #require(restored.entries.first { $0.clientID == photoID })
        #expect(try rebuiltStore.data(for: photoEntry) == photoData)

        try rebuiltStore.acknowledgeFirst(
            clientID: firstTextID,
            userID: userID,
            relationshipID: relationshipID
        )
        try rebuiltStore.acknowledgeFirst(
            clientID: photoID,
            userID: userID,
            relationshipID: relationshipID
        )
        #expect(throws: ConversationOutboxError.missingLocalFile) {
            try rebuiltStore.data(for: photoEntry)
        }
        #expect(
            try rebuiltStore.load(userID: userID, relationshipID: relationshipID).entries.map(\.clientID)
                == [lastTextID]
        )
    }

    @Test func conversationPhotoOutboxRejectsLowCapacityAndClearsOnlyTheUserScope() throws {
        let suiteName = "ConversationPhotoOutboxBoundaryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConversationPhotoOutboxBoundaryTests.\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let userID = UUID()
        let otherUserID = UUID()
        let relationshipID = UUID()
        let photoID = UUID()
        let otherPhotoID = UUID()
        let photoData = Data([0x01, 0x02])
        let lowCapacityStore = ConversationOutboxStore(
            defaults: defaults,
            directoryURL: directoryURL,
            availableCapacity: { _ in 1 }
        )

        #expect(throws: ConversationOutboxError.insufficientCapacity) {
            try lowCapacityStore.enqueuePhoto(
                photoData,
                userID: userID,
                relationshipID: relationshipID,
                clientID: photoID,
                localCreatedAt: .now
            )
        }
        #expect(try lowCapacityStore.load(userID: userID, relationshipID: relationshipID).isEmpty)

        let store = ConversationOutboxStore(
            defaults: defaults,
            directoryURL: directoryURL,
            availableCapacity: { _ in Int64.max }
        )
        try store.enqueuePhoto(
            photoData,
            userID: userID,
            relationshipID: relationshipID,
            clientID: photoID,
            localCreatedAt: .now
        )
        try store.enqueuePhoto(
            photoData,
            userID: otherUserID,
            relationshipID: relationshipID,
            clientID: otherPhotoID,
            localCreatedAt: .now
        )
        let photoEntry = try #require(
            try store.load(userID: userID, relationshipID: relationshipID).entries.first
        )
        let otherPhotoEntry = try #require(
            try store.load(userID: otherUserID, relationshipID: relationshipID).entries.first
        )

        store.clearAll(userID: userID)

        #expect(try store.load(userID: userID, relationshipID: relationshipID).isEmpty)
        #expect(throws: ConversationOutboxError.missingLocalFile) {
            try store.data(for: photoEntry)
        }
        #expect(try store.data(for: otherPhotoEntry) == photoData)
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
        #expect(restored.messages.first?.textBody == "訊息 1")
        #expect(restored.messages.last?.textBody == "訊息 200")
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
        #expect(model.messages.last?.textBody == "立即顯示")
        #expect(model.messages.last?.deliveryState == .sending)
        #expect(await slowSend.value)
        await model.waitForScheduledDelivery()
        #expect(model.messages.last?.deliveryState == .synced)

        service.sendDelay = .zero
        service.sendFailuresRemaining = 1
        #expect(await model.send("  我很好  "))
        await model.waitForScheduledDelivery()
        #expect(model.messages.last?.textBody == "我很好")
        #expect(model.messages.last?.deliveryState == .failed)
        let failedMessageID = try #require(model.messages.last?.id)
        await model.retryMessage(id: failedMessageID)
        #expect(service.sentBodies == ["立即顯示", "我很好", "我很好"])
        #expect(service.sentClientIDs[1] == service.sentClientIDs[2])
        #expect(model.messages.last?.textBody == "我很好")
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
        #expect(model.messages.compactMap(\.textBody) == ["第一則", "第二則"])
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
        #expect(model.messages.compactMap(\.textBody) == ["第一則", "第二則", "第三則"])
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
        #expect(model.messages.compactMap(\.textBody) == ["恢復後立即看見"])

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

    @MainActor
    @Test func conversationRejectedRecoveredPhotoIsAcknowledgedWithoutLosingQuotaStatus() async {
        let currentUserID = UUID()
        let pendingPhotoID = UUID()
        let rejectionMessage = "本月照片新增已達目前上限。"
        let service = ConversationRemoteServiceFake(
            currentUserID: currentUserID,
            messages: [],
            unreadCount: 0
        )
        service.seedPendingMessage(ChatMessage(
            id: pendingPhotoID,
            senderUserID: currentUserID,
            content: .photo,
            createdAt: Date(timeIntervalSince1970: 100),
            deliveryState: .failed
        ))
        service.deliveryResultOverride = .rejected(rejectionMessage)
        let model = ConversationModel(service: service)

        await model.start()

        #expect(service.pendingMessageCount == 0)
        #expect(!model.messages.contains { $0.id == pendingPhotoID })
        #expect(model.statusMessage == rejectionMessage)

        await model.refresh()
        #expect(model.statusMessage == rejectionMessage)
    }

    @MainActor
    @Test func conversationReactionOptimismRollsBackAndRetryReusesIdentity() async throws {
        let currentUserID = UUID()
        let partnerUserID = UUID()
        let originalReactionID = UUID()
        let partnerMessage = ChatMessage(
            id: UUID(),
            senderUserID: partnerUserID,
            body: "今天辛苦了",
            createdAt: .now,
            reaction: ChatMessageReaction(
                id: originalReactionID,
                reactorUserID: currentUserID,
                emoji: .heart,
                updatedAt: .now
            )
        )
        let service = ConversationRemoteServiceFake(
            currentUserID: currentUserID,
            messages: [partnerMessage],
            unreadCount: 0
        )
        let model = ConversationModel(service: service)
        await model.start()

        service.reactionDelay = .milliseconds(200)
        service.reactionFailuresRemaining = 1
        let firstReplace = Task {
            await model.react(to: partnerMessage, with: .hug)
        }
        try await Task.sleep(for: .milliseconds(30))
        #expect(model.messages.first?.reaction?.emoji == .hug)
        await firstReplace.value
        #expect(model.messages.first?.reaction?.id == originalReactionID)
        #expect(model.messages.first?.reaction?.emoji == .heart)

        service.reactionDelay = .zero
        await model.react(to: try #require(model.messages.first), with: .hug)
        #expect(service.reactionClientIDs.count == 2)
        #expect(service.reactionClientIDs[0] == service.reactionClientIDs[1])
        #expect(model.messages.first?.reaction?.emoji == .hug)

        service.removeReactionDelay = .milliseconds(200)
        service.removeReactionFailuresRemaining = 1
        let reactedMessage = try #require(model.messages.first)
        let remove = Task {
            await model.react(to: reactedMessage, with: .hug)
        }
        try await Task.sleep(for: .milliseconds(30))
        #expect(model.messages.first?.reaction == nil)
        await remove.value
        #expect(model.messages.first?.reaction?.emoji == .hug)

        await model.react(to: try #require(model.messages.first), withEmoji: "🥳")
        #expect(model.messages.first?.reaction?.emojiValue == "🥳")
        await model.react(to: try #require(model.messages.first), withEmoji: "🥳")
        #expect(model.messages.first?.reaction == nil)
    }

    @MainActor
    @Test func conversationSaveAsMomentRetryReusesStableMomentIdentity() async throws {
        let message = ChatMessage(
            id: UUID(),
            senderUserID: UUID(),
            body: "把這句留下來",
            createdAt: .now
        )
        let service = ConversationRemoteServiceFake(
            currentUserID: UUID(),
            messages: [message],
            unreadCount: 0
        )
        let model = ConversationModel(service: service)
        await model.start()
        service.saveMomentFailuresRemaining = 1

        #expect(await model.saveAsMoment(message) == false)
        #expect(await model.saveAsMoment(message))
        #expect(service.savedMomentClientIDs.count == 2)
        #expect(service.savedMomentClientIDs[0] == service.savedMomentClientIDs[1])
        #expect(model.savedMomentMessageIDs == Set([message.id]))

        let restoredModel = ConversationModel(service: service)
        await restoredModel.start()
        #expect(restoredModel.savedMomentMessageIDs == Set([message.id]))
    }

    @MainActor
    @Test func conversationSourceLookupRefreshesWhenTheMessageIsNotInLocalHistory() async {
        let source = ChatMessage(
            id: UUID(),
            senderUserID: UUID(),
            body: "較早的來源訊息",
            createdAt: .now.addingTimeInterval(-10_000)
        )
        let service = ConversationRemoteServiceFake(
            currentUserID: UUID(),
            messages: [],
            unreadCount: 0
        )
        let model = ConversationModel(service: service)
        await model.start()

        service.messages = [source]

        #expect(await model.ensureMessageAvailable(id: source.id))
        #expect(model.messages.contains(source))
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

    @Test func legacyMomentSnapshotDecodesWithoutSourceMessageID() throws {
        let legacy = LegacyMoment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .text("升級前的 Moment"),
            createdAt: Date(timeIntervalSince1970: 100),
            responses: [],
            questionAnswers: []
        )

        let decoded = try JSONDecoder().decode(
            Moment.self,
            from: JSONEncoder().encode(legacy)
        )
        #expect(decoded.id == legacy.id)
        #expect(decoded.content == legacy.content)
        #expect(decoded.sourceMessageID == nil)
        #expect(decoded.sourceAppointmentID == nil)
    }

    @Test func appointmentDiscussionMomentKeepsAnExactSource() {
        let sourceMessageID = UUID()
        let sourceAppointmentID = UUID()
        let moment = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .photo,
            createdAt: .now,
            sourceMessageID: sourceMessageID,
            sourceAppointmentID: sourceAppointmentID
        )

        #expect(moment.source == MomentSource(
            messageID: sourceMessageID,
            appointmentID: sourceAppointmentID
        ))
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

    @Test func pairingInputAcceptsShortCodesShareTextAndLegacyUUID() {
        let token = "11111111-2222-4333-8444-555555555555"
        #expect(PairingInputPolicy.invitationIdentifier(from: "  \(token)\n") == token)
        #expect(PairingInputPolicy.invitationIdentifier(from: "7k3m-w9qp") == "7K3MW9QP")
        #expect(PairingInputPolicy.invitationIdentifier(from: "7K3M W9QP") == "7K3MW9QP")
        #expect(PairingInputPolicy.invitationIdentifier(
            from: "加入我在方心的私人空間。\n邀請碼：7K3M-W9QP"
        ) == "7K3MW9QP")
        #expect(PairingInputPolicy.invitationIdentifier(from: "一般文字 7K3M-W9QP") == nil)
        #expect(PairingInputPolicy.invitationIdentifier(from: "7K3M-W9QO") == nil)
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
            shortCode: "7K3MW9QP",
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
        #expect(invitation.code == "7K3M-W9QP")
        #expect(!invitation.code.contains(invitationToken.uuidString.lowercased()))
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
        #expect(service.acceptedIdentifiers == ["7K3MW9QP"])

        model.resetForAuthenticatedSession()
        #expect(model.state == .checking)

        await model.declineInvitation(rawToken: invitation.code)
        #expect(model.state == .unpaired)
        #expect(service.declinedIdentifiers == ["7K3MW9QP"])
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
    @Test func pairingAuthenticatedBootstrapDoesNotMountCachedRelationshipBeforeRemoteRefresh() async {
        let relationship = PairingRelationship(id: UUID(), memberCount: 2)
        let service = SuspendedPairingRemoteServiceFake(cachedRelationship: relationship)
        let model = PairingModel(service: service)
        let bootstrap = Task {
            await model.refreshForAuthenticatedSession(userID: UUID())
        }

        while service.currentRelationshipContinuation == nil {
            await Task.yield()
        }
        #expect(model.state == .checking)

        service.resumeCurrentRelationship(relationship)
        await bootstrap.value

        #expect(model.state == .paired(relationship))
    }

    @MainActor
    @Test func pairingAuthenticatedBootstrapFallsBackToCacheOnlyAfterRemoteFailure() async {
        let relationship = PairingRelationship(id: UUID(), memberCount: 2)
        let service = SuspendedPairingRemoteServiceFake(cachedRelationship: relationship)
        let model = PairingModel(service: service)
        let bootstrap = Task {
            await model.refreshForAuthenticatedSession(userID: UUID())
        }

        while service.currentRelationshipContinuation == nil {
            await Task.yield()
        }
        #expect(model.state == .checking)

        service.failCurrentRelationship()
        await bootstrap.value

        #expect(model.state == .paired(relationship))
        #expect(model.statusMessage != nil)
    }
}

@MainActor
private final class SharedAppointmentRemoteServiceFake: SharedAppointmentRemoteServing {
    var appointments: [SharedAppointment] = []
    var cachedAppointments: [SharedAppointment]?
    var appointmentEvents: [SharedAppointmentEvent] = []
    var discussionSummaries: [SharedAppointmentDiscussionSummary] = []
    var pendingEntries: [SharedAppointmentOutboxEntry] = []
    var pendingOperations: [SharedAppointmentOperationOutboxEntry] = []
    var deliveryClientIDs: [UUID] = []
    var deliveredOperationIDs: [UUID] = []
    var createFailuresRemaining = 0
    var acknowledgementFailuresRemaining = 0
    var operationFailuresRemaining = 0
    var operationAcknowledgementFailuresRemaining = 0
    var terminallyRejectedAppointmentIDs: Set<UUID> = []
    var fetchAppointmentsFails = false
    var suspendFetchAppointments = false
    var fetchAppointmentsContinuation: CheckedContinuation<Void, Never>?
    private var onChange: (@MainActor () async -> Void)?

    func fetchCachedAppointments() async throws -> [SharedAppointment]? { cachedAppointments }

    func fetchAppointments() async throws -> [SharedAppointment] {
        if suspendFetchAppointments {
            await withCheckedContinuation { continuation in
                fetchAppointmentsContinuation = continuation
            }
        }
        if fetchAppointmentsFails { throw CancellationError() }
        cachedAppointments = appointments
        return appointments
    }

    func resumeFetchAppointments() {
        suspendFetchAppointments = false
        fetchAppointmentsContinuation?.resume()
        fetchAppointmentsContinuation = nil
    }

    func fetchAppointmentEvents() async throws -> [SharedAppointmentEvent] {
        appointmentEvents
    }

    func fetchRecentDiscussionSummaries() async throws -> [SharedAppointmentDiscussionSummary] {
        discussionSummaries
    }

    func fetchPendingAppointments() async throws -> [SharedAppointment] {
        pendingEntries.map(\.appointment)
    }

    func enqueueAppointment(
        _ draft: SharedAppointmentDraft,
        clientID: UUID,
        localCreatedAt: Date
    ) async throws {
        pendingEntries.append(SharedAppointmentOutboxEntry(
            userID: UUID(),
            relationshipID: UUID(),
            clientID: clientID,
            draft: draft,
            localCreatedAt: localCreatedAt,
            attemptCount: 0
        ))
    }

    func beginNextPendingAppointment() async throws -> SharedAppointmentOutboxEntry? {
        guard !pendingEntries.isEmpty else { return nil }
        pendingEntries[0].attemptCount += 1
        return pendingEntries[0]
    }

    func deliverPendingAppointment(
        _ entry: SharedAppointmentOutboxEntry
    ) async throws -> SharedAppointment {
        deliveryClientIDs.append(entry.clientID)
        if createFailuresRemaining > 0 {
            createFailuresRemaining -= 1
            throw CancellationError()
        }
        if let existing = appointments.first(where: { $0.id == entry.clientID }) {
            return existing
        }
        let appointment = SharedAppointment(
            id: entry.clientID,
            creatorUserID: UUID(),
            title: entry.draft.title,
            startsAt: entry.draft.startsAt,
            location: entry.draft.location,
            note: entry.draft.note,
            reminderAt: entry.draft.reminderAt,
            status: .scheduled,
            sourceMessageID: entry.draft.sourceMessageID,
            createdAt: .now,
            updatedAt: .now
        )
        appointments.append(appointment)
        return appointment
    }

    func acknowledgePendingAppointment(clientID: UUID) async throws {
        if acknowledgementFailuresRemaining > 0 {
            acknowledgementFailuresRemaining -= 1
            throw CancellationError()
        }
        guard pendingEntries.first?.clientID == clientID else {
            throw SharedAppointmentOutboxError.unexpectedAcknowledgement
        }
        pendingEntries.removeFirst()
    }

    func fetchPendingAppointmentOperations() async throws -> [SharedAppointmentOperationOutboxEntry] {
        pendingOperations
    }

    func enqueueAppointmentOperation(
        appointmentID: UUID,
        operationID: UUID,
        operation: SharedAppointmentOperation,
        localCreatedAt: Date
    ) async throws {
        pendingOperations.append(SharedAppointmentOperationOutboxEntry(
            userID: UUID(),
            relationshipID: UUID(),
            operationID: operationID,
            appointmentID: appointmentID,
            operation: operation,
            localCreatedAt: localCreatedAt,
            attemptCount: 0
        ))
    }

    func beginNextPendingAppointmentOperation() async throws -> SharedAppointmentOperationOutboxEntry? {
        guard !pendingOperations.isEmpty else { return nil }
        pendingOperations[0].attemptCount += 1
        return pendingOperations[0]
    }

    func deliverPendingAppointmentOperation(
        _ entry: SharedAppointmentOperationOutboxEntry
    ) async throws -> SharedAppointmentOperationDeliveryResult {
        deliveredOperationIDs.append(entry.operationID)
        if operationFailuresRemaining > 0 {
            operationFailuresRemaining -= 1
            throw CancellationError()
        }
        if terminallyRejectedAppointmentIDs.contains(entry.appointmentID) {
            return .rejected(
                appointments.first { $0.id == entry.appointmentID },
                "這筆約定已取消，未再套用待送編輯。"
            )
        }
        switch entry.operation {
        case let .update(draft):
            return .accepted(try performUpdateAppointment(
                id: entry.appointmentID,
                operationID: entry.operationID,
                actorUserID: entry.userID,
                draft: draft
            ))
        case .cancel:
            return .accepted(try performCancelAppointment(
                id: entry.appointmentID,
                operationID: entry.operationID,
                actorUserID: entry.userID
            ))
        }
    }

    func acknowledgePendingAppointmentOperation(operationID: UUID) async throws {
        if operationAcknowledgementFailuresRemaining > 0 {
            operationAcknowledgementFailuresRemaining -= 1
            throw CancellationError()
        }
        guard pendingOperations.first?.operationID == operationID else {
            throw SharedAppointmentOperationOutboxError.unexpectedAcknowledgement
        }
        pendingOperations.removeFirst()
    }

    private func performUpdateAppointment(
        id: UUID,
        operationID: UUID,
        actorUserID: UUID,
        draft: SharedAppointmentDraft
    ) throws -> SharedAppointment {
        guard let index = appointments.firstIndex(where: { $0.id == id }),
              appointments[index].status == .scheduled,
              let normalized = SharedAppointmentPolicy.normalizedDraft(draft) else {
            throw SharedAppointmentOutboxError.unexpectedAcknowledgement
        }
        let current = appointments[index]
        let updated = SharedAppointment(
            id: current.id,
            creatorUserID: current.creatorUserID,
            title: normalized.title,
            startsAt: normalized.startsAt,
            location: normalized.location,
            note: normalized.note,
            reminderAt: normalized.reminderAt,
            status: .scheduled,
            sourceMessageID: current.sourceMessageID,
            createdAt: current.createdAt,
            updatedAt: .now
        )
        appointments[index] = updated
        if current.startsAt != updated.startsAt,
           !appointmentEvents.contains(where: { $0.id == operationID }) {
            appointmentEvents.append(SharedAppointmentEvent(
                id: operationID,
                appointmentID: id,
                actorUserID: actorUserID,
                kind: .rescheduled,
                previousStartsAt: current.startsAt,
                startsAt: updated.startsAt,
                createdAt: .now
            ))
        }
        return updated
    }

    private func performCancelAppointment(
        id: UUID,
        operationID: UUID,
        actorUserID: UUID
    ) throws -> SharedAppointment {
        guard let index = appointments.firstIndex(where: { $0.id == id }) else {
            throw SharedAppointmentOutboxError.unexpectedAcknowledgement
        }
        let current = appointments[index]
        let cancelled = SharedAppointment(
            id: current.id,
            creatorUserID: current.creatorUserID,
            title: current.title,
            startsAt: current.startsAt,
            location: current.location,
            note: current.note,
            reminderAt: current.reminderAt,
            status: .cancelled,
            sourceMessageID: current.sourceMessageID,
            createdAt: current.createdAt,
            updatedAt: .now
        )
        appointments[index] = cancelled
        if !appointmentEvents.contains(where: { $0.id == operationID }) {
            appointmentEvents.append(SharedAppointmentEvent(
                id: operationID,
                appointmentID: id,
                actorUserID: actorUserID,
                kind: .cancelled,
                previousStartsAt: nil,
                startsAt: nil,
                createdAt: .now
            ))
        }
        return cancelled
    }

    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws {
        self.onChange = onChange
    }

    func stopObservingChanges() async { onChange = nil }
}

@MainActor
private final class SharedAppointmentReminderSchedulerFake: SharedAppointmentReminderScheduling {
    var authorization: SharedAppointmentReminderAuthorization = .authorized
    var authorizationRequestCount = 0
    var reconciledAppointments: [[SharedAppointment]] = []
    var removeAllCount = 0

    func authorizationStatus() async -> SharedAppointmentReminderAuthorization {
        authorization
    }

    func requestAuthorization() async -> SharedAppointmentReminderAuthorization {
        authorizationRequestCount += 1
        return authorization
    }

    func reconcile(_ appointments: [SharedAppointment]) async throws {
        reconciledAppointments.append(appointments)
    }

    func removeAll() async {
        removeAllCount += 1
    }
}

@MainActor
private final class ConversationRemoteServiceFake: ConversationRemoteServing {
    let currentUserID: UUID
    var messages: [ChatMessage]
    var unreadCount: Int
    var sentBodies: [String] = []
    var sentClientIDs: [UUID] = []
    var cachedPhotoDataByMessageID: [UUID: Data] = [:]
    var reactionClientIDs: [UUID] = []
    var savedMomentClientIDs: [UUID] = []
    var savedMomentMessageIDs: Set<UUID> = []
    var markedReadMessageIDs: [UUID] = []
    var sendFailuresRemaining = 0
    var fetchFailuresRemaining = 0
    var acknowledgementFailuresRemaining = 0
    var reactionFailuresRemaining = 0
    var removeReactionFailuresRemaining = 0
    var saveMomentFailuresRemaining = 0
    var sendDelay: Duration = .zero
    var fetchDelay: Duration = .zero
    var reactionDelay: Duration = .zero
    var removeReactionDelay: Duration = .zero
    var deliveryResultOverride: ConversationDeliveryResult?
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

    var pendingMessageCount: Int { pendingMessages.count }

    func seedPendingMessage(_ message: ChatMessage) {
        pendingMessages.append(message)
    }

    func fetchPendingSnapshot() async throws -> ConversationPendingSnapshot {
        ConversationPendingSnapshot(currentUserID: currentUserID, messages: pendingMessages)
    }

    func fetchCachedSnapshot() async throws -> ConversationSnapshot? {
        ConversationSnapshot(
            currentUserID: currentUserID,
            messages: messages,
            unreadCount: unreadCount,
            savedMomentMessageIDs: savedMomentMessageIDs
        )
    }

    func persistCachedSnapshot(_ snapshot: ConversationSnapshot) async {}

    func enqueueMessage(
        _ draft: ChatMessageDraft,
        clientID: UUID,
        localCreatedAt: Date
    ) async throws {
        let content: ChatMessageContent
        switch draft {
        case let .text(body):
            content = .text(body)
        case let .photo(data):
            content = .photo
            cachedPhotoDataByMessageID[clientID] = data
        }
        pendingMessages.append(ChatMessage(
            id: clientID,
            senderUserID: currentUserID,
            content: content,
            createdAt: localCreatedAt,
            deliveryState: .sending
        ))
    }

    func beginNextPendingMessage() async throws -> ChatMessage? {
        pendingMessages.first.map {
            ChatMessage(
                id: $0.id,
                senderUserID: $0.senderUserID,
                content: $0.content,
                createdAt: $0.createdAt,
                deliveryState: .sending,
                reaction: $0.reaction
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
            unreadCount: unreadCount,
            savedMomentMessageIDs: savedMomentMessageIDs
        )
        try await Task.sleep(for: fetchDelay)
        return snapshot
    }

    func deliverPendingMessage(_ message: ChatMessage) async throws -> ConversationDeliveryResult {
        if let body = message.textBody { sentBodies.append(body) }
        sentClientIDs.append(message.id)
        try await Task.sleep(for: sendDelay)
        if sendFailuresRemaining > 0 {
            sendFailuresRemaining -= 1
            throw TestServiceError.expected
        }
        if let deliveryResultOverride { return deliveryResultOverride }
        if let existing = messages.first(where: { $0.id == message.id }) {
            return .accepted(existing.createdAt)
        }
        let acceptedAt = nextAcceptedAt
        nextAcceptedAt = nextAcceptedAt.addingTimeInterval(1)
        messages.append(ChatMessage(
            id: message.id,
            senderUserID: currentUserID,
            content: message.content,
            createdAt: acceptedAt,
            reaction: message.reaction
        ))
        return .accepted(acceptedAt)
    }

    func cachedPhotoData(for messageID: UUID) -> Data? {
        cachedPhotoDataByMessageID[messageID]
    }

    func photoData(for messageID: UUID) async throws -> Data {
        guard let data = cachedPhotoDataByMessageID[messageID] else {
            throw TestServiceError.expected
        }
        return data
    }

    func setReaction(
        messageID: UUID,
        emojiValue: String,
        clientID: UUID
    ) async throws -> ChatMessageReaction {
        guard let emojiValue = ChatReactionPolicy.normalizedEmojiValue(emojiValue) else {
            throw TestServiceError.expected
        }
        reactionClientIDs.append(clientID)
        try await Task.sleep(for: reactionDelay)
        if reactionFailuresRemaining > 0 {
            reactionFailuresRemaining -= 1
            throw TestServiceError.expected
        }
        let reaction = ChatMessageReaction(
            id: clientID,
            reactorUserID: currentUserID,
            emojiValue: emojiValue,
            updatedAt: .now
        )
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            throw TestServiceError.expected
        }
        messages[index].reaction = reaction
        return reaction
    }

    func removeReaction(messageID: UUID) async throws {
        try await Task.sleep(for: removeReactionDelay)
        if removeReactionFailuresRemaining > 0 {
            removeReactionFailuresRemaining -= 1
            throw TestServiceError.expected
        }
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            throw TestServiceError.expected
        }
        messages[index].reaction = nil
    }

    func saveAsMoment(messageID: UUID, momentClientID: UUID) async throws -> UUID {
        savedMomentClientIDs.append(momentClientID)
        if saveMomentFailuresRemaining > 0 {
            saveMomentFailuresRemaining -= 1
            throw TestServiceError.expected
        }
        guard messages.contains(where: { $0.id == messageID }) else {
            throw TestServiceError.expected
        }
        savedMomentMessageIDs.insert(messageID)
        return momentClientID
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
    var acceptedIdentifiers: [String] = []
    var declinedIdentifiers: [String] = []
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

    func acceptInvitation(identifier: String) async throws -> UUID {
        acceptedIdentifiers.append(identifier)
        return acceptedRelationshipID
    }

    func declineInvitation(identifier: String) async throws {
        declinedIdentifiers.append(identifier)
    }

    func cancelInvitation() async throws {
        cancelInvitationCallCount += 1
    }
}

private final class SuspendedPairingRemoteServiceFake: PairingRemoteServing {
    let cachedRelationshipValue: PairingRelationship?
    var currentRelationshipContinuation: CheckedContinuation<PairingRelationship?, Error>?

    init(cachedRelationship: PairingRelationship? = nil) {
        cachedRelationshipValue = cachedRelationship
    }

    func cachedRelationship(userID: UUID) async -> PairingRelationship? {
        cachedRelationshipValue
    }

    func currentRelationship() async throws -> PairingRelationship? {
        try await withCheckedThrowingContinuation { continuation in
            currentRelationshipContinuation = continuation
        }
    }

    func resumeCurrentRelationship(_ relationship: PairingRelationship?) {
        currentRelationshipContinuation?.resume(returning: relationship)
        currentRelationshipContinuation = nil
    }

    func failCurrentRelationship() {
        currentRelationshipContinuation?.resume(
            throwing: NSError(domain: "PairingBootstrapTests", code: 1)
        )
        currentRelationshipContinuation = nil
    }

    func createInvitation() async throws -> PairingInvitation {
        PairingInvitation(
            relationshipID: UUID(),
            token: UUID(),
            shortCode: "7K3MW9QP",
            expiresAt: .now
        )
    }

    func acceptInvitation(identifier: String) async throws -> UUID {
        UUID()
    }

    func declineInvitation(identifier: String) async throws {}

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

    func photoData(for moment: Moment) async throws -> Data {
        cachedPhotoDataByMomentID[moment.id] ?? Data()
    }

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

private struct LegacyConversationOutboxQueue: Encodable {
    let entries: [LegacyConversationOutboxEntry]
}

private struct LegacyConversationOutboxEntry: Encodable {
    let userID: UUID
    let relationshipID: UUID
    let clientID: UUID
    let body: String
    let localCreatedAt: Date
    let attemptCount: Int
}

private struct LegacyConversationSnapshot: Encodable {
    let messages: [LegacyConversationCachedMessage]
    let unreadCount: Int
}

private struct LegacyConversationCachedMessage: Encodable {
    let id: UUID
    let senderUserID: UUID
    let body: String
    let createdAt: Date
}

private struct LegacyMoment: Encodable {
    let id: UUID
    let creatorUserID: UUID
    let content: MomentContent
    let createdAt: Date
    let responses: [MomentResponse]
    let questionAnswers: [MomentQuestionAnswer]
}
