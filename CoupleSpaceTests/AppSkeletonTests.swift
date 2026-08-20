import Foundation
import Supabase
import Testing
#if os(iOS)
import UIKit
#endif
@testable import CoupleSpace

struct AppSkeletonTests {
    @MainActor
    @Test func currentSessionSignOutUsesTheLocalServiceOperation() async {
        let userID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let service = AuthSessionSignOutServiceFake()
        let model = SupabaseAppleAuthenticationModel(
            client: CoupleSpaceSupabaseClient.preview,
            sessionSignOutService: service,
            initialState: .signedIn(userID: userID)
        )

        await model.signOut()

        #expect(service.currentSessionSignOutCount == 1)
        #expect(model.state.isSignedIn == false)
    }

    @MainActor
    @Test func productionLocalSignOutDrainsRefreshBeforeItsFinalLocalCleanup() async throws {
        var events: [String] = []
        let service = SupabaseAuthSessionSignOutService(
            currentRefreshToken: { "prior-refresh-token" },
            signOut: { scope in events.append("signOut:\(scope.rawValue)") },
            refreshSession: { token in events.append("refresh:\(token)") }
        )

        try await service.signOutCurrentSession()

        #expect(events == [
            "signOut:local",
            "refresh:prior-refresh-token",
            "signOut:local",
        ])
    }

    @MainActor
    @Test func productionLocalSignOutStillDrainsAfterTheInitialLogoutRequestFails() async {
        var events: [String] = []
        var signOutCount = 0
        let service = SupabaseAuthSessionSignOutService(
            currentRefreshToken: { "prior-refresh-token" },
            signOut: { scope in
                signOutCount += 1
                events.append("signOut:\(scope.rawValue)")
                if signOutCount == 1 { throw AuthSessionSignOutTestError.failed }
            },
            refreshSession: { token in events.append("refresh:\(token)") }
        )

        do {
            try await service.signOutCurrentSession()
            Issue.record("Expected the initial logout request error to be reported")
        } catch {}

        #expect(events == [
            "signOut:local",
            "refresh:prior-refresh-token",
            "signOut:local",
        ])
    }

    @MainActor
    @Test func productionLocalSignOutStillFinishesCleanupWhenRefreshIsRejected() async throws {
        var events: [String] = []
        let service = SupabaseAuthSessionSignOutService(
            currentRefreshToken: { "prior-refresh-token" },
            signOut: { scope in events.append("signOut:\(scope.rawValue)") },
            refreshSession: { token in
                events.append("refresh:\(token)")
                throw AuthSessionSignOutTestError.failed
            }
        )

        try await service.signOutCurrentSession()

        #expect(events == [
            "signOut:local",
            "refresh:prior-refresh-token",
            "signOut:local",
        ])
    }

    @MainActor
    @Test func localSignOutFailureDoesNotRestoreTheSDKRemovedSession() async {
        let userID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let service = AuthSessionSignOutServiceFake(
            currentSessionSignOutError: AuthSessionSignOutTestError.failed
        )
        let model = SupabaseAppleAuthenticationModel(
            client: CoupleSpaceSupabaseClient.preview,
            sessionSignOutService: service,
            initialState: .signedIn(userID: userID),
            currentSession: { nil }
        )

        await model.signOut()

        #expect(model.state.isSignedIn == false)
    }

    @MainActor
    @Test func authEventsDoNotOverrideARequestedLocalSignOutBeforeItFinishes() async {
        let userID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let service = AuthSessionSignOutServiceFake(suspendsCurrentSessionSignOut: true)
        let model = SupabaseAppleAuthenticationModel(
            client: CoupleSpaceSupabaseClient.preview,
            sessionSignOutService: service,
            initialState: .signedIn(userID: userID),
            currentSession: { nil }
        )

        let signOut = Task { await model.signOut() }
        while service.currentSessionSignOutCount == 0 { await Task.yield() }

        model.reconcileObservedSession(nil)
        #expect(model.state.phase == .signingOut)
        #expect(model.state.userID == userID)

        let refreshedSession = Session(
            accessToken: "test-access-token",
            tokenType: "bearer",
            expiresIn: 3_600,
            expiresAt: Date().addingTimeInterval(3_600).timeIntervalSince1970,
            refreshToken: "test-refresh-token",
            user: User(
                id: userID,
                appMetadata: [:],
                userMetadata: [:],
                aud: "authenticated",
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        model.reconcileObservedSession(refreshedSession)
        #expect(model.state.phase == .signingOut)
        #expect(model.state.userID == userID)

        service.resumeCurrentSessionSignOut()
        await signOut.value
        #expect(model.state.isSignedIn == false)

        model.reconcileObservedSession(refreshedSession)
        #expect(model.state.phase == .signedOut)
        #expect(model.state.userID == nil)
    }

    @MainActor
    @Test func aRemoteSignedOutEventMovesAnAuthenticatedDeviceToSignIn() {
        let model = SupabaseAppleAuthenticationModel(
            client: CoupleSpaceSupabaseClient.preview,
            sessionSignOutService: AuthSessionSignOutServiceFake(),
            initialState: .signedIn(userID: UUID()),
            currentSession: { nil }
        )

        model.reconcileObservedSession(nil)

        #expect(model.state.phase == .signedOut)
        #expect(model.state.userID == nil)
    }

    @MainActor
    @Test func appLockLocksOnInactiveAndBackgroundAndOnlyUnlocksAfterDeviceAuthentication() async {
        let preferences = UserDefaults(suiteName: "AppSkeletonTests.appLock")!
        preferences.removePersistentDomain(forName: "AppSkeletonTests.appLock")
        let authenticator = AppLockAuthenticatorFake(result: .authenticated)
        let model = AppLockModel(
            preferences: preferences,
            preferenceKey: "enabled",
            authenticator: authenticator,
            initiallyEnabled: false
        )

        model.setEnabled(true)
        #expect(model.isLocked)

        await model.unlockIfNeeded()
        #expect(model.isLocked == false)

        await model.handleLifecyclePhase(.inactive)
        #expect(model.isLocked)

        await model.handleLifecyclePhase(.active)
        #expect(model.isLocked == false)

        await model.handleLifecyclePhase(.background)
        #expect(model.isLocked)

        authenticator.result = .failed
        await model.handleLifecyclePhase(.active)
        #expect(model.isLocked)
        #expect(model.statusMessage == "尚未驗證，內容仍受保護。")
    }

    @MainActor
    @Test func appLockKeepsContentCoveredWhenDeviceAuthenticationIsUnavailable() async {
        let preferences = UserDefaults(suiteName: "AppSkeletonTests.appLockUnavailable")!
        preferences.removePersistentDomain(forName: "AppSkeletonTests.appLockUnavailable")
        let model = AppLockModel(
            preferences: preferences,
            preferenceKey: "enabled",
            authenticator: AppLockAuthenticatorFake(result: .unavailable),
            initiallyEnabled: true
        )

        await model.handleLifecyclePhase(.active)

        #expect(model.isLocked)
        #expect(model.statusMessage == "此裝置無法使用 Face ID 或裝置密碼解鎖。")
    }

    @MainActor
    @Test func disablingAppLockImmediatelyRestoresContentAndPersistsPreference() {
        let preferences = UserDefaults(suiteName: "AppSkeletonTests.appLockPreference")!
        preferences.removePersistentDomain(forName: "AppSkeletonTests.appLockPreference")
        let model = AppLockModel(
            preferences: preferences,
            preferenceKey: "enabled",
            authenticator: AppLockAuthenticatorFake(result: .unavailable),
            initiallyEnabled: true
        )

        model.setEnabled(false)
        #expect(model.isLocked == false)
        #expect(preferences.bool(forKey: "enabled") == false)
    }

    @MainActor
    @Test func appLockRestoresPersistedPreferenceWithoutChangingUnlockedStateWhenDisabled() async {
        let preferences = UserDefaults(suiteName: "AppSkeletonTests.appLockRestoration")!
        preferences.removePersistentDomain(forName: "AppSkeletonTests.appLockRestoration")
        let authenticator = AppLockAuthenticatorFake(result: .authenticated)
        let enabledModel = AppLockModel(
            preferences: preferences,
            preferenceKey: "enabled",
            authenticator: authenticator,
            initiallyEnabled: false
        )
        enabledModel.setEnabled(true)

        let restoredEnabledModel = AppLockModel(
            preferences: preferences,
            preferenceKey: "enabled",
            authenticator: authenticator
        )
        #expect(restoredEnabledModel.isEnabled)
        #expect(restoredEnabledModel.isLocked)

        restoredEnabledModel.setEnabled(false)
        let restoredDisabledModel = AppLockModel(
            preferences: preferences,
            preferenceKey: "enabled",
            authenticator: authenticator
        )
        await restoredDisabledModel.handleLifecyclePhase(.active)

        #expect(restoredDisabledModel.isEnabled == false)
        #expect(restoredDisabledModel.isLocked == false)
        #expect(authenticator.authenticationCount == 0)
    }

    @Test func uiTestingLaunchOptionIsExplicitAndOrderIndependent() {
        #expect(AppLaunchOptions(arguments: []).isUITesting == false)
        #expect(AppLaunchOptions(arguments: ["--other", "--ui-testing"]).isUITesting)
        #expect(AppLaunchOptions(arguments: ["--ui-testing-pairing"]).isPairingUITesting)
        #expect(AppLaunchOptions(
            arguments: ["--ui-testing", "--ui-testing-formal-unpairing"]
        ).isFormalUnpairingUITesting)
    }

    @Test func timeFormatUsesTheSelectedHourConvention() {
        let date = Date(timeIntervalSince1970: 0)

        let twelveHour = CoupleSpaceDateFormat.string(
            date,
            date: .omitted,
            time: .shortened,
            timeFormat: .twelveHour
        )
        let twentyFourHour = CoupleSpaceDateFormat.string(
            date,
            date: .omitted,
            time: .shortened,
            timeFormat: .twentyFourHour
        )

        #expect(twelveHour.contains("上午") || twelveHour.contains("下午"))
        #expect(twentyFourHour.contains(":"))
        #expect(!twentyFourHour.contains("上午") && !twentyFourHour.contains("下午"))
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

#if DEBUG
    @Test func sessionCapabilityProbeRequiresItsExplicitLaunchArgument() {
        #expect(SessionCapabilityProbeAvailability.isEnabled(arguments: []) == false)
        #expect(SessionCapabilityProbeAvailability.isEnabled(arguments: [
            "--ui-testing",
            SessionCapabilityProbeAvailability.launchArgument,
        ]))
    }

    @Test func sessionCapabilityProbeUsesAOneWayShortFingerprint() {
        let firstSessionID = "11111111-2222-3333-4444-555555555555"
        let secondSessionID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"

        let first = SessionCapabilityProbeIdentity(sessionID: firstSessionID, expiresAt: 1_800_000_000)
        let duplicate = SessionCapabilityProbeIdentity(sessionID: firstSessionID, expiresAt: 1_800_000_000)
        let second = SessionCapabilityProbeIdentity(sessionID: secondSessionID, expiresAt: 1_800_000_000)

        #expect(first.fingerprint == duplicate.fingerprint)
        #expect(first.fingerprint != second.fingerprint)
        #expect(first.fingerprint.count == 12)
        #expect(first.fingerprint.contains(firstSessionID) == false)
    }

    @MainActor
    @Test func sessionProtectedDataProbePublishesOnlyRemoteMetadataEvidence() async {
        let expected = SessionProtectedDataSnapshot(
            hasAuthSession: true,
            relationship: .succeeded(SessionProtectedRelationshipEvidence(
                fingerprint: "A1B2C3D4E5F6",
                status: "active"
            )),
            activeMemberCount: .succeeded(2),
            sharedItemCount: .succeeded(3),
            personalArchive: .succeeded(SessionProtectedArchiveEvidence(
                fingerprint: "010203040506",
                relationshipFingerprint: "A1B2C3D4E5F6"
            )),
            personalArchiveItemCount: .succeeded(3)
        )
        let inspector = SessionProtectedDataInspectorFake(snapshot: expected)
        let model = SessionProtectedDataProbeModel(inspector: inspector)

        await model.inspect()

        #expect(inspector.inspectionCount == 1)
        #expect(model.isWorking == false)
        #expect(model.snapshot == expected)
    }
#endif

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
            badge: nil,
            userInfo: [:]
        )])
        #expect(requests[0].title.contains("私人晚餐標題") == false)
        #expect(requests[0].body.contains("私人地點") == false)
        #expect(requests[0].body.contains("私人註記") == false)
        #expect(requests[0].badge == nil)
        #expect(requests[0].userInfo.isEmpty)
    }

    @MainActor
    @Test func appointmentReminderPolicyKeepsOneIdentifierWhenTheSameAppointmentIsRescheduled() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let appointmentID = UUID()
        func appointment(reminderAt: Date) -> SharedAppointment {
            SharedAppointment(
                id: appointmentID,
                creatorUserID: UUID(),
                title: "不應出現在通知的標題",
                startsAt: now.addingTimeInterval(7_200),
                location: "不應出現在通知的地點",
                note: "不應出現在通知的註記",
                reminderAt: reminderAt,
                status: .scheduled,
                sourceMessageID: nil,
                createdAt: now,
                updatedAt: now
            )
        }

        let original = try #require(SharedAppointmentReminderPolicy.requests(
            for: [appointment(reminderAt: now.addingTimeInterval(1_800))],
            identifierPrefix: "test.",
            now: now
        ).first)
        let rescheduled = try #require(SharedAppointmentReminderPolicy.requests(
            for: [appointment(reminderAt: now.addingTimeInterval(3_600))],
            identifierPrefix: "test.",
            now: now
        ).first)

        #expect(original.identifier == rescheduled.identifier)
        #expect(original.appointmentID == rescheduled.appointmentID)
        #expect(original.fireDate != rescheduled.fireDate)
        #expect(rescheduled.badge == nil)
        #expect(rescheduled.userInfo.isEmpty)
    }

    @Test func backgroundPushRefreshesOnlyAppointmentReminderLifecycleEvents() {
        #expect(BackgroundAppointmentReminderRefreshPolicy.requiresRefresh(userInfo: [
            "event_kind": "appointment_created",
        ]))
        #expect(BackgroundAppointmentReminderRefreshPolicy.requiresRefresh(userInfo: [
            "event_kind": "appointment_updated",
        ]))
        #expect(BackgroundAppointmentReminderRefreshPolicy.requiresRefresh(userInfo: [
            "event_kind": "appointment_cancelled",
        ]))
        #expect(BackgroundAppointmentReminderRefreshPolicy.requiresRefresh(userInfo: [
            "event_kind": "chat_message_created",
        ]) == false)
        #expect(BackgroundAppointmentReminderRefreshPolicy.requiresRefresh(userInfo: [:]) == false)
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
    @Test func sharedAppointmentModelSeparatesUpcomingFromPastAndCancelledNewestFirst() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let upcomingID = UUID()
        let recentCancelledID = UUID()
        let olderPastID = UUID()
        let service = SharedAppointmentRemoteServiceFake()

        func appointment(
            id: UUID,
            startsAt: Date,
            status: SharedAppointmentStatus
        ) -> SharedAppointment {
            SharedAppointment(
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
            appointment(
                id: olderPastID,
                startsAt: now.addingTimeInterval(-7_200),
                status: .scheduled
            ),
            appointment(
                id: upcomingID,
                startsAt: now.addingTimeInterval(3_600),
                status: .scheduled
            ),
            appointment(
                id: recentCancelledID,
                startsAt: now.addingTimeInterval(-3_600),
                status: .cancelled
            ),
        ]
        let model = SharedAppointmentModel(service: service, now: { now })

        await model.refresh()

        #expect(model.upcomingAppointments.map(\.id) == [upcomingID])
        #expect(model.pastOrCancelledAppointments.map(\.id) == [
            recentCancelledID,
            olderPastID,
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

    @MainActor
    @Test func sharedAppointmentReadUsesTheRenderedServerBoundary() async {
        let appointmentID = UUID()
        let renderedBoundaryID = UUID()
        let newerBoundaryID = UUID()
        let now = Date(timeIntervalSince1970: 2_000)
        let service = SharedAppointmentRemoteServiceFake()
        service.appointments = [SharedAppointment(
            id: appointmentID,
            creatorUserID: UUID(),
            title: "精確清讀邊界",
            startsAt: now.addingTimeInterval(3_600),
            location: nil,
            note: nil,
            reminderAt: nil,
            status: .scheduled,
            sourceMessageID: nil,
            interactionBoundarySourceIdentity: renderedBoundaryID,
            createdAt: now,
            updatedAt: now
        )]
        let model = SharedAppointmentModel(service: service, now: { now })
        await model.start()
        let renderedBoundary = model.appointment(id: appointmentID)?.interactionBoundarySourceIdentity
        service.appointments = [SharedAppointment(
            id: appointmentID,
            creatorUserID: UUID(),
            title: "稍後才抵達的更新",
            startsAt: now.addingTimeInterval(7_200),
            location: nil,
            note: nil,
            reminderAt: nil,
            status: .scheduled,
            sourceMessageID: nil,
            interactionBoundarySourceIdentity: newerBoundaryID,
            createdAt: now,
            updatedAt: now.addingTimeInterval(1)
        )]
        await model.refresh()
        #expect(model.appointment(id: appointmentID)?.interactionBoundarySourceIdentity == newerBoundaryID)
        let generationBeforeRead = model.refreshGeneration

        await model.markInteractionRead(
            for: appointmentID,
            visibleSourceIdentity: renderedBoundary
        )

        #expect(service.markedInteractionAppointmentIDs == [appointmentID])
        #expect(service.markedInteractionSourceIdentities == [renderedBoundaryID])
        #expect(model.refreshGeneration > generationBeforeRead)
        await model.stop()
    }

    @MainActor
    @Test func backgroundAppointmentFetchCannotRestoreAClearedSnapshot() async throws {
        let suiteName = "BackgroundAppointmentFetchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = UUID()
        let relationshipID = UUID()
        let snapshotStore = SharedAppointmentSnapshotStore(defaults: defaults)
        let staleAppointment = SharedAppointment(
            id: UUID(),
            creatorUserID: userID,
            title: "登出前的約定",
            startsAt: Date(timeIntervalSince1970: 3_600),
            location: nil,
            note: nil,
            reminderAt: nil,
            status: .scheduled,
            sourceMessageID: nil,
            interactionBoundarySourceIdentity: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        try snapshotStore.save(
            [staleAppointment],
            userID: userID,
            relationshipID: relationshipID
        )
        var fetchContinuation: CheckedContinuation<Void, Never>?
        let service = SupabaseSharedAppointmentService(
            client: CoupleSpaceSupabaseClient.preview,
            currentUserID: userID,
            relationshipID: relationshipID,
            outboxStore: SharedAppointmentOutboxStore(defaults: defaults),
            operationOutboxStore: SharedAppointmentOperationOutboxStore(defaults: defaults),
            snapshotStore: snapshotStore,
            appointmentSessionUserID: { userID },
            fetchAppointmentsOverride: {
                await withCheckedContinuation { continuation in
                    fetchContinuation = continuation
                }
                return [staleAppointment]
            }
        )
        let fetch = Task {
            try await service.fetchAppointmentsWithoutUpdatingSnapshot()
        }
        while fetchContinuation == nil {
            await Task.yield()
        }

        snapshotStore.clearAll(userID: userID)
        fetchContinuation?.resume()

        #expect(try await fetch.value == [staleAppointment])
        #expect(try snapshotStore.load(userID: userID, relationshipID: relationshipID) == nil)
    }

    @Test func sharedAppointmentSnapshotPersistsSyncedItemsWithinAccountRelationshipScope() throws {
        let suiteName = "SharedAppointmentSnapshotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SharedAppointmentSnapshotStore(defaults: defaults)
        let userID = UUID()
        let relationshipID = UUID()
        let interactionBoundaryID = UUID()
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
                interactionBoundarySourceIdentity: index == SharedAppointmentLocalSnapshotPolicy.maximumAppointmentCount
                    ? interactionBoundaryID
                    : nil,
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
        #expect(latest.interactionBoundarySourceIdentity == interactionBoundaryID)
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
                interactionBoundarySourceIdentity: latest.interactionBoundarySourceIdentity,
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
        #expect(
            try store.load(userID: userID, relationshipID: relationshipID)?
                .last?.interactionBoundarySourceIdentity == interactionBoundaryID
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
        let operationIdentity = MomentOperationIdentity.deleteMoment(momentID)
        let operationID = try store.loadOrCreateMomentOperationID(
            for: operationIdentity,
            userID: userID,
            relationshipID: relationshipID
        )
        let reconstructedStore = TodaySnapshotStore(
            defaults: defaults,
            photoRootURL: photoRootURL
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
        #expect(reconstructedStore.momentOperationID(
            for: operationIdentity,
            userID: userID,
            relationshipID: relationshipID
        ) == operationID)
        #expect(reconstructedStore.momentOperationID(
            for: operationIdentity,
            userID: UUID(),
            relationshipID: relationshipID
        ) == nil)

        store.clearAll(userID: userID)
        #expect(try store.loadMoments(userID: userID, relationshipID: relationshipID) == nil)
        #expect(try store.loadTogetherNow(userID: userID, relationshipID: relationshipID) == nil)
        #expect(try store.loadPhoto(
            userID: userID,
            relationshipID: relationshipID,
            momentID: momentID
        ) == nil)
        #expect(reconstructedStore.momentOperationID(
            for: operationIdentity,
            userID: userID,
            relationshipID: relationshipID
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

        model.setConversationVisible(true)
        await model.markVisibleMessagesRead()
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
    @Test func conversationModelKeepsNewUnreadAfterLeavingWhileAnOlderReadIsInFlight() async {
        let currentUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
        let partnerUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!
        let olderMessage = ChatMessage(
            id: UUID(uuidString: "C2000000-0000-0000-0000-000000000001")!,
            senderUserID: partnerUserID,
            body: "先前未讀",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let service = ConversationRemoteServiceFake(
            currentUserID: currentUserID,
            messages: [olderMessage],
            unreadCount: 1
        )
        service.markReadDelay = .milliseconds(200)
        let model = ConversationModel(service: service)
        await model.start()

        model.setConversationVisible(true)
        let readTask = Task { await model.markVisibleMessagesRead() }
        while service.markedReadMessageIDs.isEmpty { await Task.yield() }
        model.setConversationVisible(false)

        let newerMessage = ChatMessage(
            id: UUID(uuidString: "C2000000-0000-0000-0000-000000000002")!,
            senderUserID: partnerUserID,
            body: "離開後才收到",
            createdAt: Date(timeIntervalSince1970: 200)
        )
        service.messages.append(newerMessage)
        service.unreadCount = 1
        await service.sendChange()
        #expect(model.unreadCount == 1)

        await readTask.value
        #expect(model.unreadCount == 1)
        #expect(service.markedReadMessageIDs == [olderMessage.id])
    }

    @MainActor
    @Test func conversationModelKeepsIncomingTextAndPhotoUnreadWhileHidden() async {
        let currentUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
        let partnerUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!
        let service = ConversationRemoteServiceFake(
            currentUserID: currentUserID,
            messages: [],
            unreadCount: 0
        )
        let model = ConversationModel(service: service)
        await model.start()
        model.setConversationVisible(false)

        let text = ChatMessage(
            id: UUID(uuidString: "C3000000-0000-0000-0000-000000000001")!,
            senderUserID: partnerUserID,
            body: "Today 收到文字",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        service.messages.append(text)
        service.unreadCount = 1
        await service.sendChange()
        #expect(model.unreadCount == 1)

        let photo = ChatMessage(
            id: UUID(uuidString: "C3000000-0000-0000-0000-000000000002")!,
            senderUserID: partnerUserID,
            content: .photo,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        service.messages.append(photo)
        service.unreadCount = 2
        await service.sendChange()
        #expect(model.unreadCount == 2)
        #expect(service.markedReadMessageIDs.isEmpty)
    }

    @Test func relationshipUnreadRefreshGateAcceptsOnlyTheLatestRequest() {
        var gate = RelationshipUnreadRefreshGate()
        #expect(gate.begin() == nil)

        gate.activate()
        let olderRequest = gate.begin()!
        let latestRequest = gate.begin()!

        #expect(!gate.accepts(olderRequest))
        #expect(gate.accepts(latestRequest))
        gate.deactivate()
        #expect(!gate.accepts(latestRequest))
        #expect(gate.begin() == nil)
    }

    @Test func mainConversationVisibilityRequiresTheActualUnlockedForegroundSurface() {
        #expect(MainConversationVisibilityPolicy.isVisible(
            sceneIsActive: true,
            isConversationSelected: true,
            isPresented: true,
            isLocked: false
        ))
        #expect(!MainConversationVisibilityPolicy.isVisible(
            sceneIsActive: false,
            isConversationSelected: true,
            isPresented: true,
            isLocked: false
        ))
        #expect(!MainConversationVisibilityPolicy.isVisible(
            sceneIsActive: true,
            isConversationSelected: false,
            isPresented: true,
            isLocked: false
        ))
        #expect(!MainConversationVisibilityPolicy.isVisible(
            sceneIsActive: true,
            isConversationSelected: true,
            isPresented: false,
            isLocked: false
        ))
        #expect(!MainConversationVisibilityPolicy.isVisible(
            sceneIsActive: true,
            isConversationSelected: true,
            isPresented: true,
            isLocked: true
        ))
        #expect(!MainConversationVisibilityPolicy.isVisible(
            sceneIsActive: true,
            isConversationSelected: true,
            isPresented: true,
            isLocked: false,
            isAppointmentRoutePending: true
        ))
    }

    @Test func appointmentDetailReadRequiresTheUnlockedForegroundSurface() {
        #expect(SharedAppointmentDetailVisibilityPolicy.isVisible(
            sceneIsActive: true,
            isPresented: true,
            isLocked: false
        ))
        #expect(!SharedAppointmentDetailVisibilityPolicy.isVisible(
            sceneIsActive: false,
            isPresented: true,
            isLocked: false
        ))
        #expect(!SharedAppointmentDetailVisibilityPolicy.isVisible(
            sceneIsActive: true,
            isPresented: false,
            isLocked: false
        ))
        #expect(!SharedAppointmentDetailVisibilityPolicy.isVisible(
            sceneIsActive: true,
            isPresented: true,
            isLocked: true
        ))
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
    @Test func conversationRecoveryRereadsMessagesBeforeRealtimeReconnectCompletes() async throws {
        let currentUserID = UUID()
        let partnerUserID = UUID()
        let service = ConversationRemoteServiceFake(
            currentUserID: currentUserID,
            messages: [],
            unreadCount: 0
        )
        let model = ConversationModel(service: service)
        await model.start()
        let incoming = ChatMessage(
            id: UUID(),
            senderUserID: partnerUserID,
            body: "恢復時立即顯示",
            createdAt: .now
        )
        service.messages = [incoming]
        service.unreadCount = 1
        service.startObservingDelay = .milliseconds(250)

        let recovery = Task { await model.recoverPendingMessages() }
        try await Task.sleep(for: .milliseconds(50))

        #expect(model.messages == [incoming])
        await recovery.value
    }

    @MainActor
    @Test func conversationModelLoadsStablePagesAndKeepsOlderHistoryDuringRefresh() async throws {
        let currentUserID = UUID()
        let partnerUserID = UUID()
        let remoteMessages = (0..<55).map { index in
            ChatMessage(
                id: UUID(),
                senderUserID: partnerUserID,
                body: "分頁訊息 \(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_000 - index))
            )
        }
        let service = ConversationRemoteServiceFake(
            currentUserID: currentUserID,
            messages: remoteMessages,
            unreadCount: 0
        )
        service.returnsCachedSnapshot = false
        let model = ConversationModel(service: service)

        await model.start()
        #expect(model.messages.count == 50)
        #expect(model.hasMoreMessages)

        #expect(await model.loadMoreMessages())
        #expect(model.messages.count == 55)
        #expect(!model.hasMoreMessages)
        #expect(Set(model.messages.map(\.id)).count == 55)

        let newest = ChatMessage(
            id: UUID(),
            senderUserID: partnerUserID,
            body: "Realtime 新訊息",
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        service.messages.append(newest)
        await model.refresh()

        #expect(model.messages.count == 56)
        #expect(model.messages.last?.id == newest.id)
        #expect(model.messages.first?.id == remoteMessages.last?.id)
        #expect(!model.hasMoreMessages)
    }

    @MainActor
    @Test func conversationPageCursorDoesNotSkipMessagesWithTheSameTimestamp() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let messages = (0..<52).map { index in
            ChatMessage(
                id: UUID(),
                senderUserID: UUID(),
                body: "同時訊息 \(index)",
                createdAt: timestamp
            )
        }
        let service = ConversationRemoteServiceFake(
            currentUserID: UUID(),
            messages: messages,
            unreadCount: 0
        )

        let first = try await service.fetchPage(before: nil, limit: 50)
        let oldestOnFirstPage = try #require(first.snapshot.messages.first)
        let second = try await service.fetchPage(
            before: ConversationPageCursor(
                createdAt: oldestOnFirstPage.createdAt,
                clientID: oldestOnFirstPage.id
            ),
            limit: 50
        )
        let fetchedIDs = first.snapshot.messages.map(\.id) + second.snapshot.messages.map(\.id)

        #expect(first.hasMore)
        #expect(!second.hasMore)
        #expect(fetchedIDs.count == 52)
        #expect(Set(fetchedIDs) == Set(messages.map(\.id)))
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

    @Test func momentTimelineGroupsMonthsNewestFirstWithStableMomentOrder() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let june = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 15
        )))
        let julyEarlier = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 2
        )))
        let julyLater = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 20
        )))
        let earlierID = try #require(UUID(uuidString: "A1000000-0000-0000-0000-000000000001"))
        let laterID = try #require(UUID(uuidString: "A1000000-0000-0000-0000-000000000002"))
        let juneID = try #require(UUID(uuidString: "A1000000-0000-0000-0000-000000000003"))
        let moments = [
            Moment(id: earlierID, creatorUserID: UUID(), content: .text("七月初"), createdAt: julyEarlier),
            Moment(id: juneID, creatorUserID: UUID(), content: .text("六月"), createdAt: june),
            Moment(id: laterID, creatorUserID: UUID(), content: .text("七月下旬"), createdAt: julyLater),
        ]

        let sections = MomentTimelinePolicy.monthSections(from: moments, calendar: calendar)

        #expect(sections.count == 2)
        #expect(calendar.component(.month, from: sections[0].monthStart) == 7)
        #expect(sections[0].moments.map(\.id) == [laterID, earlierID])
        #expect(calendar.component(.month, from: sections[1].monthStart) == 6)
        #expect(sections[1].moments.map(\.id) == [juneID])
    }

    @Test func sharedPhotosKeepOnlyPhotoMomentsInOldestToNewestOrder() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        func date(month: Int, day: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(
                year: 2026,
                month: month,
                day: day
            )))
        }
        let juneID = UUID()
        let julyID = UUID()
        let augustID = UUID()
        let sections = MomentTimelinePolicy.photoMonthSections(from: [
            Moment(id: augustID, creatorUserID: UUID(), content: .photo, createdAt: try date(month: 8, day: 2)),
            Moment(id: UUID(), creatorUserID: UUID(), content: .text("不應出現"), createdAt: try date(month: 7, day: 5)),
            Moment(id: juneID, creatorUserID: UUID(), content: .photo, createdAt: try date(month: 6, day: 1)),
            Moment(id: julyID, creatorUserID: UUID(), content: .photo, createdAt: try date(month: 7, day: 3)),
        ], calendar: calendar)

        #expect(sections.map { calendar.component(.month, from: $0.monthStart) } == [6, 7, 8])
        #expect(sections.flatMap(\.moments).map(\.id) == [juneID, julyID, augustID])
    }

    @Test func momentTimelineDayDestinationsUseTheNewestMomentOnEachLoadedDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        func date(day: Int, hour: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(
                year: 2026,
                month: 8,
                day: day,
                hour: hour
            )))
        }
        let newestSameDayID = UUID()
        let olderSameDayID = UUID()
        let previousDayID = UUID()
        let destinations = MomentTimelinePolicy.dayDestinations(from: [
            Moment(
                id: olderSameDayID,
                creatorUserID: UUID(),
                content: .text("早上"),
                createdAt: try date(day: 17, hour: 8)
            ),
            Moment(
                id: previousDayID,
                creatorUserID: UUID(),
                content: .text("昨天"),
                createdAt: try date(day: 16, hour: 20)
            ),
            Moment(
                id: newestSameDayID,
                creatorUserID: UUID(),
                content: .text("晚上"),
                createdAt: try date(day: 17, hour: 21)
            ),
        ], calendar: calendar)

        #expect(destinations.map(\.momentID) == [newestSameDayID, previousDayID])
        #expect(destinations.map { calendar.component(.day, from: $0.dayStart) } == [17, 16])
    }

    @Test func momentContentFilterKeepsOnlyTheSelectedContentType() {
        let moments = [
            Moment(id: UUID(), creatorUserID: UUID(), content: .mood(.happy), createdAt: .now),
            Moment(id: UUID(), creatorUserID: UUID(), content: .text("一起散步"), createdAt: .now),
            Moment(id: UUID(), creatorUserID: UUID(), content: .photo, createdAt: .now),
            Moment(
                id: UUID(),
                creatorUserID: UUID(),
                content: .question(MomentQuestion(key: "key", prompt: "最近好嗎？")),
                createdAt: .now
            ),
        ]

        #expect(moments.filter(MomentContentFilter.all.includes).count == 4)
        #expect(moments.filter(MomentContentFilter.mood.includes).map(\.content) == [.mood(.happy)])
        #expect(moments.filter(MomentContentFilter.text.includes).map(\.content) == [.text("一起散步")])
        #expect(moments.filter(MomentContentFilter.photo.includes).map(\.content) == [.photo])
        #expect(moments.filter(MomentContentFilter.question.includes).count == 1)
    }

    @Test func weeklyReviewUsesTheLatestSevenLocalCalendarDaysThroughNow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        func date(day: Int, hour: Int, minute: Int = 0) throws -> Date {
            try #require(calendar.date(from: DateComponents(
                year: 2026,
                month: 8,
                day: day,
                hour: hour,
                minute: minute
            )))
        }
        let now = try date(day: 17, hour: 14)
        let expectedStartDay = try date(day: 11, hour: 0)
        let expectedEndDay = try date(day: 17, hour: 0)
        let boundaryID = UUID()
        let latestID = UUID()
        let moments = [
            Moment(
                id: UUID(),
                creatorUserID: UUID(),
                content: .text("範圍外"),
                createdAt: try date(day: 10, hour: 23, minute: 59)
            ),
            Moment(
                id: boundaryID,
                creatorUserID: UUID(),
                content: .mood(.happy),
                createdAt: try date(day: 11, hour: 0)
            ),
            Moment(
                id: latestID,
                creatorUserID: UUID(),
                content: .text("最新"),
                createdAt: now
            ),
            Moment(
                id: UUID(),
                creatorUserID: UUID(),
                content: .photo,
                createdAt: try date(day: 17, hour: 15)
            ),
        ]

        let review = MomentTimelinePolicy.weeklyReview(
            from: moments,
            now: now,
            calendar: calendar
        )

        #expect(review.startDay == expectedStartDay)
        #expect(review.endDay == expectedEndDay)
        #expect(review.moments.map(\.id) == [latestID, boundaryID])
        #expect(review.count(for: .text) == 1)
        #expect(review.count(for: .mood) == 1)
        #expect(review.count(for: .photo) == 0)
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
        #expect(service.firstFetchObservedState == true)

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
    @Test func momentModelLoadsStablePagesAndKeepsOlderHistoryDuringRefresh() async throws {
        let creatorID = UUID()
        let remoteMoments = (0..<55).map { index in
            Moment(
                id: UUID(),
                creatorUserID: creatorID,
                content: .text("Moment \(index)"),
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_000 - index))
            )
        }
        let service = MomentRemoteServiceFake(moments: remoteMoments)
        let model = MomentModel(service: service)

        await model.start()
        #expect(model.moments.count == 50)
        #expect(model.hasMoreMoments)

        await model.loadMoreMoments()
        #expect(model.moments.count == 55)
        #expect(!model.hasMoreMoments)
        #expect(Set(model.moments.map(\.id)).count == 55)

        let newest = Moment(
            id: UUID(),
            creatorUserID: creatorID,
            content: .text("Realtime 新增"),
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        service.moments.insert(newest, at: 0)
        await model.refresh()

        #expect(model.moments.count == 56)
        #expect(model.moments.first?.id == newest.id)
        #expect(model.moments.last?.id == remoteMoments.last?.id)
        #expect(!model.hasMoreMoments)
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
    @Test func momentModelLoadsPhotoDataOnlyWhenRequestedAndOnlyOnce() async {
        let firstPhoto = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .photo,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let secondPhoto = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .photo,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let service = MomentRemoteServiceFake(moments: [firstPhoto, secondPhoto])
        service.cachedPhotoDataByMomentID[firstPhoto.id] = Data([0x01])
        service.cachedPhotoDataByMomentID[secondPhoto.id] = Data([0x02])
        let model = MomentModel(service: service)

        await model.start()
        #expect(service.photoDataRequestIDs.isEmpty)

        await model.loadPhotoIfNeeded(firstPhoto)
        await model.loadPhotoIfNeeded(firstPhoto)

        #expect(service.photoDataRequestIDs == [firstPhoto.id])
        #expect(model.photoDataByMomentID[firstPhoto.id] == Data([0x01]))
        #expect(model.photoDataByMomentID[secondPhoto.id] == nil)
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

    @MainActor
    @Test func momentLifecycleRetriesReuseStableOperationIDsAfterLostAcknowledgements() async throws {
        let currentUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let relationshipID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
        let suiteName = "MomentOperationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let photoRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MomentOperationTests.\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: photoRootURL)
        }
        let moment = Moment(
            id: UUID(),
            creatorUserID: currentUserID,
            content: .text("只套用一次"),
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let firstStore = TodaySnapshotStore(defaults: defaults, photoRootURL: photoRootURL)
        let service = MomentRemoteServiceFake(moments: [moment], operationStore: firstStore)
        let firstModel = MomentModel(service: service)
        await firstModel.start()

        service.deleteApplyThenFailRemaining = 1
        #expect(await firstModel.delete(moment) == false)
        let deleteIdentity = MomentOperationIdentity.deleteMoment(moment.id)
        let persistedDeleteID = try #require(firstStore.momentOperationID(
            for: deleteIdentity,
            userID: currentUserID,
            relationshipID: relationshipID
        ))
        await firstModel.stop()

        let secondStore = TodaySnapshotStore(defaults: defaults, photoRootURL: photoRootURL)
        service.operationStore = secondStore
        let secondModel = MomentModel(service: service)
        await secondModel.start()
        #expect(await secondModel.delete(moment))
        #expect(service.deleteOperationIDs.count == 2)
        #expect(service.deleteOperationIDs == [persistedDeleteID, persistedDeleteID])
        #expect(service.deleteApplicationCount == 1)
        #expect(!secondModel.moments.contains(where: { $0.id == moment.id }))
        #expect(secondStore.momentOperationID(
            for: deleteIdentity,
            userID: currentUserID,
            relationshipID: relationshipID
        ) == nil)

        let deleted = try #require(secondModel.recentlyDeletedMoments.first)
        service.restoreApplyThenFailRemaining = 1
        #expect(await secondModel.restore(deleted) == false)
        let restoreIdentity = MomentOperationIdentity.restoreMoment(moment.id)
        let persistedRestoreID = try #require(secondStore.momentOperationID(
            for: restoreIdentity,
            userID: currentUserID,
            relationshipID: relationshipID
        ))
        await secondModel.stop()

        let thirdStore = TodaySnapshotStore(defaults: defaults, photoRootURL: photoRootURL)
        service.operationStore = thirdStore
        let thirdModel = MomentModel(service: service)
        await thirdModel.start()
        #expect(await thirdModel.restore(deleted))
        #expect(service.restoreOperationIDs.count == 2)
        #expect(service.restoreOperationIDs == [persistedRestoreID, persistedRestoreID])
        #expect(service.restoreApplicationCount == 1)
        #expect(thirdModel.moments.filter { $0.id == moment.id }.count == 1)
        #expect(thirdStore.momentOperationID(
            for: restoreIdentity,
            userID: currentUserID,
            relationshipID: relationshipID
        ) == nil)
    }

    @MainActor
    @Test func momentInteractionRemovalRetriesReuseDurableIDsAfterModelAndStoreRebuild() async throws {
        let currentUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let relationshipID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
        let suiteName = "MomentInteractionOperationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let photoRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MomentInteractionOperationTests.\(UUID().uuidString)")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: photoRootURL)
        }
        let response = MomentResponse(
            id: UUID(),
            responderUserID: currentUserID,
            content: .emoji(.hug),
            createdAt: .now
        )
        let responseMoment = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .text("回應"),
            createdAt: .now,
            responses: [response]
        )
        let answer = MomentQuestionAnswer(
            id: UUID(),
            answererUserID: currentUserID,
            content: "回答",
            createdAt: .now
        )
        let question = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .question(MomentQuestion(key: "understand_today", prompt: "題目")),
            createdAt: .now,
            questionAnswers: [answer]
        )
        let firstStore = TodaySnapshotStore(defaults: defaults, photoRootURL: photoRootURL)
        let service = MomentRemoteServiceFake(
            moments: [question, responseMoment],
            operationStore: firstStore
        )
        let firstModel = MomentModel(service: service)
        await firstModel.start()

        service.removeResponseApplyThenFailRemaining = 1
        #expect(await firstModel.removeOwnResponse(from: responseMoment, response: response) == false)
        let responseIdentity = MomentOperationIdentity.removeResponse(
            momentID: responseMoment.id,
            responseID: response.id
        )
        let responseOperationID = try #require(firstStore.momentOperationID(
            for: responseIdentity,
            userID: currentUserID,
            relationshipID: relationshipID
        ))
        await firstModel.stop()

        let secondStore = TodaySnapshotStore(defaults: defaults, photoRootURL: photoRootURL)
        service.operationStore = secondStore
        let secondModel = MomentModel(service: service)
        await secondModel.start()
        #expect(await secondModel.removeOwnResponse(from: responseMoment, response: response))
        #expect(service.removeResponseOperationIDs == [responseOperationID, responseOperationID])
        #expect(service.removeResponseApplicationCount == 1)
        #expect(secondStore.momentOperationID(
            for: responseIdentity,
            userID: currentUserID,
            relationshipID: relationshipID
        ) == nil)

        service.removeAnswerApplyThenFailRemaining = 1
        #expect(await secondModel.removeOwnAnswer(from: question, answer: answer) == false)
        let answerIdentity = MomentOperationIdentity.removeAnswer(
            momentID: question.id,
            answerID: answer.id
        )
        let answerOperationID = try #require(secondStore.momentOperationID(
            for: answerIdentity,
            userID: currentUserID,
            relationshipID: relationshipID
        ))
        await secondModel.stop()

        let thirdStore = TodaySnapshotStore(defaults: defaults, photoRootURL: photoRootURL)
        service.operationStore = thirdStore
        let thirdModel = MomentModel(service: service)
        await thirdModel.start()
        #expect(await thirdModel.removeOwnAnswer(from: question, answer: answer))
        #expect(service.removeAnswerOperationIDs == [answerOperationID, answerOperationID])
        #expect(service.removeAnswerApplicationCount == 1)
        #expect(thirdStore.momentOperationID(
            for: answerIdentity,
            userID: currentUserID,
            relationshipID: relationshipID
        ) == nil)
    }

    @MainActor
    @Test func momentSupersededLifecycleReceiptClearsStaleDurableIdentityAndRefreshes() async throws {
        let currentUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let relationshipID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
        let suiteName = "MomentSupersededOperationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TodaySnapshotStore(defaults: defaults)
        let moment = Moment(
            id: UUID(),
            creatorUserID: currentUserID,
            content: .text("跨裝置狀態"),
            createdAt: .now
        )
        let service = MomentRemoteServiceFake(moments: [moment], operationStore: store)
        let model = MomentModel(service: service)
        await model.start()

        let deleteIdentity = MomentOperationIdentity.deleteMoment(moment.id)
        service.deleteSupersededRemaining = 1
        #expect(await model.delete(moment) == false)
        #expect(model.moments == [moment])
        #expect(store.momentOperationID(
            for: deleteIdentity,
            userID: currentUserID,
            relationshipID: relationshipID
        ) == nil)
        #expect(await model.delete(moment))
        #expect(service.deleteOperationIDs.count == 2)
        #expect(service.deleteOperationIDs[0] != service.deleteOperationIDs[1])

        let deleted = try #require(model.recentlyDeletedMoments.first)
        let restoreIdentity = MomentOperationIdentity.restoreMoment(moment.id)
        service.restoreSupersededRemaining = 1
        #expect(await model.restore(deleted) == false)
        #expect(model.moments.isEmpty)
        #expect(store.momentOperationID(
            for: restoreIdentity,
            userID: currentUserID,
            relationshipID: relationshipID
        ) == nil)
        #expect(await model.restore(deleted))
        #expect(service.restoreOperationIDs.count == 2)
        #expect(service.restoreOperationIDs[0] != service.restoreOperationIDs[1])
    }

    @MainActor
    @Test func momentRestoreDuringRecentlyDeletedFetchCannotReviveStaleListEntry() async {
        let currentUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let moment = Moment(
            id: UUID(),
            creatorUserID: currentUserID,
            content: .text("等待復原"),
            createdAt: .now
        )
        let deleted = RecentlyDeletedMoment(
            moment: moment,
            deletedAt: Date(timeIntervalSince1970: 1_000),
            purgeAfter: Date(timeIntervalSince1970: 1_000 + 30 * 86_400)
        )
        let service = MomentRemoteServiceFake(moments: [])
        service.recentlyDeletedMoments = [deleted]
        service.hiddenMomentIDs = [moment.id]
        service.syncHints = [MomentSyncHint(
            momentID: moment.id,
            isDeleted: true,
            sourceMessageID: nil,
            revision: 1
        )]
        let model = MomentModel(service: service)
        await model.start()
        service.suspendFetchRecentlyDeleted = true
        let loadDeleted = Task { await model.loadRecentlyDeletedMoments() }
        guard await waitForLifecycleCondition({
            service.fetchRecentlyDeletedContinuation != nil
        }) else {
            Issue.record("Recently deleted fetch did not suspend")
            service.resumeFetchRecentlyDeleted()
            await loadDeleted.value
            return
        }

        #expect(await model.restore(deleted))
        service.resumeFetchRecentlyDeleted()
        await loadDeleted.value

        #expect(model.recentlyDeletedMoments.isEmpty)
        #expect(model.moments.contains { $0.id == moment.id })
    }

    @MainActor
    @Test func delayedDeleteAcknowledgementCannotOverrideNewerRemoteRestore() async throws {
        let currentUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let moment = Moment(
            id: UUID(),
            creatorUserID: currentUserID,
            content: .text("較新的復原應勝出"),
            createdAt: .now
        )
        let service = MomentRemoteServiceFake(moments: [moment])
        let model = MomentModel(service: service)
        await model.start()
        service.suspendDeleteAcknowledgement = true
        let deletion = Task { await model.delete(moment) }
        guard await waitForLifecycleCondition({
            service.deleteAcknowledgementContinuation != nil
        }) else {
            Issue.record("Delete acknowledgement did not suspend")
            service.resumeDeleteAcknowledgement()
            _ = await deletion.value
            return
        }

        _ = try await service.restoreMoment(id: moment.id, operationID: UUID())
        await service.sendChange(.momentChanged(moment.id))
        service.resumeDeleteAcknowledgement()

        #expect(await deletion.value)
        #expect(model.moments == [moment])
        #expect(model.recentlyDeletedMoments.isEmpty)
    }

    @MainActor
    @Test func successfulDeleteAckFailsClosedWhenReconciliationFails() async throws {
        let currentUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let target = Moment(
            id: UUID(),
            creatorUserID: currentUserID,
            content: .text("刪除 ack 後不得殘留"),
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let unrelated = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .text("不相關更新"),
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let service = MomentRemoteServiceFake(moments: [target, unrelated])
        let model = MomentModel(service: service)
        await model.start()
        service.suspendDeleteAcknowledgement = true
        let deletion = Task { await model.delete(target) }
        guard await waitForLifecycleCondition({
            service.deleteAcknowledgementContinuation != nil
        }) else {
            Issue.record("Delete acknowledgement did not suspend")
            service.resumeDeleteAcknowledgement()
            _ = await deletion.value
            return
        }

        await service.sendChange(.momentChanged(unrelated.id))
        service.syncHintFailuresRemaining = 1
        service.resumeDeleteAcknowledgement()

        #expect(await deletion.value)
        #expect(!model.moments.contains { $0.id == target.id })
        #expect(service.cachedMomentsValue?.contains { $0.id == target.id } != true)
        #expect(service.cacheEvictionMomentIDs.contains(target.id))
    }

    @MainActor
    @Test func delayedResponseRemovalAcknowledgementCannotEraseNewerInteraction() async {
        let currentUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let oldResponse = MomentResponse(
            id: UUID(),
            responderUserID: currentUserID,
            content: .emoji(.heart),
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let moment = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .text("較新的互動應勝出"),
            createdAt: .now,
            responses: [oldResponse]
        )
        let service = MomentRemoteServiceFake(moments: [moment])
        let model = MomentModel(service: service)
        await model.start()
        service.suspendRemoveResponseAcknowledgement = true
        let removal = Task {
            await model.removeOwnResponse(from: moment, response: oldResponse)
        }
        guard await waitForLifecycleCondition({
            service.removeResponseAcknowledgementContinuation != nil
        }) else {
            Issue.record("Response removal acknowledgement did not suspend")
            service.resumeRemoveResponseAcknowledgement()
            _ = await removal.value
            return
        }

        let newerResponse = MomentResponse(
            id: UUID(),
            responderUserID: currentUserID,
            content: .emoji(.hug),
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let newerMoment = Moment(
            id: moment.id,
            creatorUserID: moment.creatorUserID,
            content: moment.content,
            createdAt: moment.createdAt,
            responses: [newerResponse]
        )
        service.moments = [newerMoment]
        service.syncHints = [MomentSyncHint(
            momentID: moment.id,
            isDeleted: false,
            sourceMessageID: nil,
            revision: 2
        )]
        await service.sendChange(.reloadFirstPage)
        service.resumeRemoveResponseAcknowledgement()

        #expect(await removal.value)
        #expect(model.moments.first?.responses == [newerResponse])
    }

    @MainActor
    @Test func successfulInteractionRemovalAckRedactsTargetWhenReconciliationFails() async {
        let currentUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let response = MomentResponse(
            id: UUID(),
            responderUserID: currentUserID,
            content: .text("移除後不得殘留"),
            createdAt: .now
        )
        let target = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .text("互動 ack"),
            createdAt: Date(timeIntervalSince1970: 200),
            responses: [response]
        )
        let unrelated = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .text("不相關更新"),
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let service = MomentRemoteServiceFake(moments: [target, unrelated])
        let model = MomentModel(service: service)
        await model.start()
        service.suspendRemoveResponseAcknowledgement = true
        let removal = Task {
            await model.removeOwnResponse(from: target, response: response)
        }
        guard await waitForLifecycleCondition({
            service.removeResponseAcknowledgementContinuation != nil
        }) else {
            Issue.record("Response removal acknowledgement did not suspend")
            service.resumeRemoveResponseAcknowledgement()
            _ = await removal.value
            return
        }

        await service.sendChange(.momentChanged(unrelated.id))
        service.syncHintFailuresRemaining = 1
        service.resumeRemoveResponseAcknowledgement()

        #expect(await removal.value)
        #expect(model.moments.first(where: { $0.id == target.id })?.responses.isEmpty == true)
        #expect(service.cachedMomentsValue?.first(where: {
            $0.id == target.id
        })?.responses.isEmpty == true)
        #expect(!service.cacheEvictionMomentIDs.contains(target.id))
    }

    @MainActor
    @Test func unavailableLiveHintPrunesBeforeLaterTargetedHydrationThrows() async throws {
        let unavailableID = try #require(UUID(
            uuidString: "00000000-0000-0000-0000-000000000010"
        ))
        let failingID = try #require(UUID(
            uuidString: "00000000-0000-0000-0000-000000000020"
        ))
        let sourceMessageID = UUID()
        let unavailable = Moment(
            id: unavailableID,
            creatorUserID: UUID(),
            content: .photo,
            createdAt: Date(timeIntervalSince1970: 10),
            sourceMessageID: sourceMessageID
        )
        let failing = Moment(
            id: failingID,
            creatorUserID: UUID(),
            content: .text("later fetch throws"),
            createdAt: Date(timeIntervalSince1970: 20)
        )
        let firstPage = (0..<50).map { index in
            Moment(
                id: UUID(),
                creatorUserID: UUID(),
                content: .text("page \(index)"),
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_000 - index))
            )
        }
        let service = MomentRemoteServiceFake(moments: firstPage + [failing])
        service.cachedMomentsValue = [unavailable]
        service.cachedPhotoDataByMomentID[unavailable.id] = Data([0x01])
        service.syncHints = [
            MomentSyncHint(
                momentID: unavailable.id,
                isDeleted: false,
                sourceMessageID: sourceMessageID,
                revision: 1
            ),
            MomentSyncHint(
                momentID: failing.id,
                isDeleted: false,
                sourceMessageID: nil,
                revision: 1
            ),
        ]
        service.fetchMomentFailureIDs = [failing.id]
        let model = MomentModel(service: service)

        await model.start()

        #expect(!model.moments.contains { $0.id == unavailable.id })
        #expect(model.photoDataByMomentID[unavailable.id] == nil)
        #expect(service.cachedMomentsValue?.contains { $0.id == unavailable.id } != true)
        #expect(service.cachedPhotoDataByMomentID[unavailable.id] == nil)
        #expect(model.hiddenMomentSourceMessageIDs.contains(sourceMessageID))
        #expect(Array(service.fetchMomentRequestIDs.prefix(2)) == [unavailable.id, failing.id])
    }

    @MainActor
    @Test func deletedHintPrunesBeforeUnrelatedLiveHydrationFailure() async {
        let sourceMessageID = UUID()
        let deleted = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .photo,
            createdAt: Date(timeIntervalSince1970: 10),
            sourceMessageID: sourceMessageID
        )
        let liveOffPage = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .text("targeted fetch 將失敗"),
            createdAt: Date(timeIntervalSince1970: 20)
        )
        let firstPage = (0..<50).map { index in
            Moment(
                id: UUID(),
                creatorUserID: UUID(),
                content: .text("page \(index)"),
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_000 - index))
            )
        }
        let service = MomentRemoteServiceFake(moments: firstPage + [liveOffPage])
        service.cachedMomentsValue = [deleted]
        service.cachedPhotoDataByMomentID[deleted.id] = Data([0x01, 0x02])
        service.syncHints = [
            MomentSyncHint(
                momentID: deleted.id,
                isDeleted: true,
                sourceMessageID: sourceMessageID,
                revision: 1
            ),
            MomentSyncHint(
                momentID: liveOffPage.id,
                isDeleted: false,
                sourceMessageID: nil,
                revision: 1
            ),
        ]
        service.fetchMomentFailureIDs = [liveOffPage.id]
        let model = MomentModel(service: service)

        await model.start()

        #expect(!model.moments.contains { $0.id == deleted.id })
        #expect(model.photoDataByMomentID[deleted.id] == nil)
        #expect(service.cachedMomentsValue?.contains { $0.id == deleted.id } != true)
        #expect(service.cachedPhotoDataByMomentID[deleted.id] == nil)
        #expect(model.hiddenMomentSourceMessageIDs.contains(sourceMessageID))
        #expect(service.fetchMomentRequestIDs.contains(liveOffPage.id))
    }

    @MainActor
    @Test func inconsistentDeletedHintPrunesMemoryPhotoCacheAndSourceBeforeRetry() async {
        let sourceMessageID = UUID()
        let deleted = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .photo,
            createdAt: .now,
            sourceMessageID: sourceMessageID
        )
        let service = MomentRemoteServiceFake(moments: [deleted])
        service.cachedMomentsValue = [deleted]
        service.cachedPhotoDataByMomentID[deleted.id] = Data([0x01, 0x02])
        service.syncHints = [MomentSyncHint(
            momentID: deleted.id,
            isDeleted: true,
            sourceMessageID: sourceMessageID,
            revision: 1
        )]
        service.failNextFetchAfterSuccessfulSnapshot = true
        let model = MomentModel(service: service)

        await model.start()

        #expect(model.moments.isEmpty)
        #expect(model.photoDataByMomentID[deleted.id] == nil)
        #expect(service.cachedMomentsValue?.contains { $0.id == deleted.id } != true)
        #expect(service.cachedPhotoDataByMomentID[deleted.id] == nil)
        #expect(model.hiddenMomentSourceMessageIDs.contains(sourceMessageID))
        #expect(service.cacheEvictionMomentIDs.contains(deleted.id))
    }

    @MainActor
    @Test func momentRefreshPrunesHiddenCachedAndPreviouslyPaginatedRows() async throws {
        let cached = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .photo,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let cachedService = MomentRemoteServiceFake(moments: [])
        cachedService.cachedMomentsValue = [cached]
        cachedService.cachedPhotoDataByMomentID[cached.id] = Data([0x01])
        cachedService.hiddenMomentIDs = [cached.id]
        let cachedModel = MomentModel(service: cachedService)
        await cachedModel.start()
        #expect(cachedModel.moments.isEmpty)
        #expect(cachedModel.photoDataByMomentID[cached.id] == nil)

        let rows = (0..<55).map { index in
            Moment(
                id: UUID(),
                creatorUserID: UUID(),
                content: .text("row \(index)"),
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_000 - index))
            )
        }
        let service = MomentRemoteServiceFake(moments: rows)
        let model = MomentModel(service: service)
        await model.start()
        await model.loadMoreMoments()
        let hidden = try #require(model.moments.last)
        service.hiddenMomentIDs.insert(hidden.id)
        service.moments.removeAll { $0.id == hidden.id }
        await model.refresh()
        #expect(!model.moments.contains(where: { $0.id == hidden.id }))
        #expect(model.moments.count == 54)
    }

    @MainActor
    @Test func momentSyncHintsRepairMissedRestoreAndChildRemovalOutsideFirstPage() async throws {
        let currentUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let sourceMessageID = UUID()
        let response = MomentResponse(
            id: UUID(),
            responderUserID: currentUserID,
            content: .emoji(.heart),
            createdAt: Date(timeIntervalSince1970: 101)
        )
        let oldMoment = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .text("舊分頁 Moment"),
            createdAt: Date(timeIntervalSince1970: 100),
            sourceMessageID: sourceMessageID,
            responses: [response]
        )
        let newerMoments = (0..<99).map { index in
            Moment(
                id: UUID(),
                creatorUserID: UUID(),
                content: .text("row \(index)"),
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_000 - index))
            )
        }
        let service = MomentRemoteServiceFake(moments: newerMoments)
        service.cachedMomentsValue = newerMoments + [oldMoment]
        service.syncHints = [MomentSyncHint(
            momentID: oldMoment.id,
            isDeleted: true,
            sourceMessageID: sourceMessageID,
            revision: 1
        )]
        let model = MomentModel(service: service)

        await model.start()
        #expect(!model.moments.contains { $0.id == oldMoment.id })
        #expect(model.hiddenMomentSourceMessageIDs == [sourceMessageID])

        service.moments.append(oldMoment)
        service.syncHints = [MomentSyncHint(
            momentID: oldMoment.id,
            isDeleted: false,
            sourceMessageID: sourceMessageID,
            revision: 2
        )]
        service.fetchMomentRequestIDs = []
        await model.refresh()

        #expect(model.moments.contains { $0.id == oldMoment.id })
        #expect(model.hiddenMomentSourceMessageIDs.isEmpty)
        #expect(service.fetchMomentRequestIDs == [oldMoment.id])

        await model.loadMoreMoments()
        #expect(model.moments.count == 100)
        #expect(!model.hasMoreMoments)

        let withoutResponse = Moment(
            id: oldMoment.id,
            creatorUserID: oldMoment.creatorUserID,
            content: oldMoment.content,
            createdAt: oldMoment.createdAt,
            sourceMessageID: sourceMessageID
        )
        service.moments.removeAll { $0.id == oldMoment.id }
        service.moments.append(withoutResponse)
        service.syncHints = [
            MomentSyncHint(
                momentID: oldMoment.id,
                isDeleted: false,
                sourceMessageID: sourceMessageID,
                revision: 3
            ),
            MomentSyncHint(
                momentID: newerMoments[0].id,
                isDeleted: false,
                sourceMessageID: nil,
                revision: 1
            ),
        ]
        service.fetchMomentRequestIDs = []
        await model.refresh()

        let repaired = try #require(model.moments.first { $0.id == oldMoment.id })
        #expect(repaired.responses.isEmpty)
        #expect(service.fetchMomentRequestIDs == [oldMoment.id])
        #expect(model.moments.count == 100)
        #expect(!model.hasMoreMoments)
    }

    @MainActor
    @Test func momentSyncHintsReadAllPagesBeyondPostgRESTRowCap() async throws {
        let hints = try (1...1_001).map { index in
            let suffix = String(format: "%012X", index)
            return MomentSyncHint(
                momentID: try #require(UUID(
                    uuidString: "00000000-0000-0000-0000-\(suffix)"
                )),
                isDeleted: true,
                sourceMessageID: nil,
                revision: 1
            )
        }
        let service = MomentRemoteServiceFake(moments: [])
        service.syncHints = hints
        let remote: MomentRemoteServing = service

        let loaded = try await remote.fetchMomentSyncHints()

        #expect(loaded.map(\.momentID) == hints.map(\.momentID))
        #expect(service.syncHintPageRequests.count == 3)
        #expect(service.syncHintPageRequests.map(\.limit) == [500, 500, 500])
        #expect(service.syncHintPageRequests[0].after == nil)
        #expect(service.syncHintPageRequests[1].after == hints[499].momentID)
        #expect(service.syncHintPageRequests[2].after == hints[999].momentID)
    }

    @MainActor
    @Test func staleCreateAcknowledgementCannotReviveDeletedPhotoOrCache() async throws {
        let photoData = Data([0x01, 0x02, 0x03])
        let service = MomentRemoteServiceFake(moments: [])
        let model = MomentModel(service: service)
        await model.start()
        service.suspendCreateAcknowledgement = true
        let create = Task { await model.create(.photo(photoData)) }
        guard await waitForLifecycleCondition({
            service.createAcknowledgementContinuation != nil
        }) else {
            Issue.record("Moment create acknowledgement did not suspend")
            service.resumeCreateAcknowledgement()
            _ = await create.value
            return
        }
        let created = try #require(service.moments.first)

        service.moments = []
        service.hiddenMomentIDs.insert(created.id)
        service.syncHints = [MomentSyncHint(
            momentID: created.id,
            isDeleted: true,
            sourceMessageID: nil,
            revision: 1
        )]
        await service.sendChange(.momentDeleted(created.id))
        service.resumeCreateAcknowledgement()

        #expect(await create.value)
        #expect(model.moments.isEmpty)
        #expect(model.photoDataByMomentID[created.id] == nil)
        #expect(service.cachedMomentsValue?.contains { $0.id == created.id } != true)
        #expect(service.cachedPhotoDataByMomentID[created.id] == nil)
    }

    @MainActor
    @Test func acceptedResponseInvalidatesOlderFirstPageSnapshotWithoutBroadcast() async {
        let parent = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .text("回應競態"),
            createdAt: .now
        )
        let service = MomentRemoteServiceFake(moments: [parent])
        let model = MomentModel(service: service)
        await model.start()
        service.suspendFetchMoments = true
        service.returnCapturedMomentsAfterSuspension = true
        let refresh = Task { await model.refresh() }
        guard await waitForLifecycleCondition({ service.fetchMomentsContinuation != nil }) else {
            Issue.record("Moment response race refresh did not suspend")
            service.resumeFetchMoments()
            await refresh.value
            return
        }

        #expect(await model.respond(to: parent, with: .emoji(.heart)))
        service.resumeFetchMoments()
        await refresh.value

        #expect(model.moments.first?.responses.count == 1)
        #expect(service.cachedMomentsValue?.first?.responses.count == 1)
    }

    @MainActor
    @Test func acceptedAnswerInvalidatesOlderFirstPageSnapshotWithoutBroadcast() async {
        let question = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .question(MomentQuestion(key: "understand_today", prompt: "今天好嗎？")),
            createdAt: .now
        )
        let service = MomentRemoteServiceFake(moments: [question])
        let model = MomentModel(service: service)
        await model.start()
        service.suspendFetchMoments = true
        service.returnCapturedMomentsAfterSuspension = true
        let staleRefresh = Task { await model.refresh() }
        guard await waitForLifecycleCondition({ service.fetchMomentsContinuation != nil }) else {
            Issue.record("Moment answer race refresh did not suspend")
            service.resumeFetchMoments()
            await staleRefresh.value
            return
        }
        let answer = Task { await model.answer(question, text: "很好") }
        guard await waitForLifecycleCondition({ service.answerClientIDs.count == 1 }) else {
            Issue.record("Moment answer acknowledgement did not complete")
            service.resumeFetchMoments()
            _ = await answer.value
            await staleRefresh.value
            return
        }

        service.resumeFetchMoments()
        #expect(await answer.value)
        await staleRefresh.value

        #expect(model.moments.first?.questionAnswers.count == 1)
        #expect(service.cachedMomentsValue?.first?.questionAnswers.count == 1)
    }

    @MainActor
    @Test func staleResponseAcknowledgementCannotRestoreNewerRemoval() async throws {
        let parent = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .text("等候回應"),
            createdAt: .now
        )
        let service = MomentRemoteServiceFake(moments: [parent])
        let model = MomentModel(service: service)
        await model.start()
        service.suspendCreateResponseAcknowledgement = true
        let response = Task { await model.respond(to: parent, with: .emoji(.heart)) }
        guard await waitForLifecycleCondition({
            service.createResponseAcknowledgementContinuation != nil
        }) else {
            Issue.record("Moment response acknowledgement did not suspend")
            service.resumeCreateResponseAcknowledgement()
            _ = await response.value
            return
        }

        service.moments[0].responses = []
        service.syncHints = [MomentSyncHint(
            momentID: parent.id,
            isDeleted: false,
            sourceMessageID: nil,
            revision: 1
        )]
        await service.sendChange(.momentChanged(parent.id))
        service.resumeCreateResponseAcknowledgement()

        #expect(await response.value)
        #expect(model.moments.first?.responses.isEmpty == true)
        #expect(service.cachedMomentsValue?.first?.responses.isEmpty == true)
    }

    @MainActor
    @Test func staleFirstPageCannotOverwriteAcceptedChildRemovalCacheOnRetryFailure() async throws {
        let oldResponse = MomentResponse(
            id: UUID(),
            responderUserID: UUID(),
            content: .text("已被另一台移除"),
            createdAt: Date(timeIntervalSince1970: 101)
        )
        let original = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .text("快取邊界"),
            createdAt: Date(timeIntervalSince1970: 100),
            responses: [oldResponse]
        )
        let accepted = Moment(
            id: original.id,
            creatorUserID: original.creatorUserID,
            content: original.content,
            createdAt: original.createdAt
        )
        let service = MomentRemoteServiceFake(moments: [original])
        let model = MomentModel(service: service)
        await model.start()
        service.suspendFetchMoments = true
        service.returnCapturedMomentsAfterSuspension = true
        service.failNextFetchAfterSuspendedSnapshot = true
        let refresh = Task { await model.refresh() }
        guard await waitForLifecycleCondition({ service.fetchMomentsContinuation != nil }) else {
            Issue.record("Moment first-page refresh did not suspend")
            service.resumeFetchMoments()
            await refresh.value
            return
        }

        service.moments = [accepted]
        service.syncHints = [MomentSyncHint(
            momentID: original.id,
            isDeleted: false,
            sourceMessageID: nil,
            revision: 1
        )]
        await service.sendChange(.momentChanged(original.id))
        service.resumeFetchMoments()
        await refresh.value

        #expect(model.moments == [accepted])
        #expect(service.cachedMomentsValue == [accepted])

        await model.stop()
        service.fetchFailuresRemaining = 1
        let restarted = MomentModel(service: service)
        await restarted.start()
        #expect(restarted.moments == [accepted])
        #expect(restarted.moments.first?.responses.isEmpty == true)
    }

    @MainActor
    @Test func momentDeleteDuringInitialRefreshCannotReviveStalePageSnapshot() async {
        let sourceMessageID = UUID()
        let moment = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .text("刪除前快照"),
            createdAt: .now,
            sourceMessageID: sourceMessageID
        )
        let service = MomentRemoteServiceFake(moments: [moment])
        service.suspendFetchMoments = true
        service.returnCapturedMomentsAfterSuspension = true
        let model = MomentModel(service: service)
        let start = Task { await model.start() }
        guard await waitForLifecycleCondition({ service.fetchMomentsContinuation != nil }) else {
            Issue.record("Initial Moment fetch did not suspend")
            service.resumeFetchMoments()
            await start.value
            return
        }

        service.moments = []
        service.hiddenMomentIDs.insert(moment.id)
        service.syncHints = [MomentSyncHint(
            momentID: moment.id,
            isDeleted: true,
            sourceMessageID: sourceMessageID,
            revision: 1
        )]
        await service.sendChange(.momentDeleted(moment.id))
        service.resumeFetchMoments()
        await start.value

        #expect(model.moments.isEmpty)
        #expect(model.hiddenMomentSourceMessageIDs == [sourceMessageID])
        #expect(service.cachedMomentsValue?.contains { $0.id == moment.id } != true)
        #expect(service.cacheEvictionMomentIDs.contains(moment.id))
    }

    @MainActor
    @Test func momentDeleteDuringLoadMoreCannotMergeStalePageOrAdvanceItsCursor() async {
        let sourceMessageID = UUID()
        let rows = (0..<100).map { index in
            Moment(
                id: UUID(),
                creatorUserID: UUID(),
                content: .text("row \(index)"),
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_000 - index)),
                sourceMessageID: index == 70 ? sourceMessageID : nil
            )
        }
        let target = rows[70]
        let service = MomentRemoteServiceFake(moments: rows)
        let model = MomentModel(service: service)
        await model.start()
        service.suspendFetchMoments = true
        service.returnCapturedMomentsAfterSuspension = true
        let loadMore = Task { await model.loadMoreMoments() }
        guard await waitForLifecycleCondition({ service.fetchMomentsContinuation != nil }) else {
            Issue.record("Older Moment page did not suspend")
            service.resumeFetchMoments()
            await loadMore.value
            return
        }

        service.moments.removeAll { $0.id == target.id }
        service.hiddenMomentIDs.insert(target.id)
        service.syncHints = [MomentSyncHint(
            momentID: target.id,
            isDeleted: true,
            sourceMessageID: sourceMessageID,
            revision: 1
        )]
        await service.sendChange(.momentDeleted(target.id))
        service.resumeFetchMoments()
        await loadMore.value

        #expect(model.moments.count == 99)
        #expect(!model.moments.contains { $0.id == target.id })
        #expect(!model.hasMoreMoments)
        #expect(model.hiddenMomentSourceMessageIDs.contains(sourceMessageID))
    }

    @MainActor
    @Test func momentPhotoCompletionAfterDeleteCannotReviveMemoryOrPersistentCache() async {
        let photo = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .photo,
            createdAt: .now
        )
        let service = MomentRemoteServiceFake(moments: [photo])
        service.remotePhotoDataByMomentID[photo.id] = Data([0x01, 0x02, 0x03])
        let model = MomentModel(service: service)
        await model.start()
        service.suspendPhotoData = true
        let loadPhoto = Task { await model.loadPhotoIfNeeded(photo) }
        guard await waitForLifecycleCondition({ service.photoDataContinuation != nil }) else {
            Issue.record("Photo download did not suspend")
            service.resumePhotoData()
            await loadPhoto.value
            return
        }

        service.moments = []
        service.hiddenMomentIDs.insert(photo.id)
        service.syncHints = [MomentSyncHint(
            momentID: photo.id,
            isDeleted: true,
            sourceMessageID: nil,
            revision: 1
        )]
        await service.sendChange(.momentDeleted(photo.id))
        service.resumePhotoData()
        await loadPhoto.value

        #expect(model.photoDataByMomentID[photo.id] == nil)
        #expect(service.cachedPhotoDataByMomentID[photo.id] == nil)
        #expect(service.cacheEvictionMomentIDs.filter { $0 == photo.id }.count >= 2)
    }

    @MainActor
    @Test func momentOwnInteractionRemovalKeepsJointQuestionRevealed() async throws {
        let currentUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let partnerUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        let ownResponse = MomentResponse(
            id: UUID(),
            responderUserID: currentUserID,
            content: .text("我的回應"),
            createdAt: .now
        )
        let responseMoment = Moment(
            id: UUID(),
            creatorUserID: partnerUserID,
            content: .text("伴侶的 Moment"),
            createdAt: .now,
            responses: [ownResponse]
        )
        let ownAnswer = MomentQuestionAnswer(
            id: UUID(),
            answererUserID: currentUserID,
            content: "我的答案",
            createdAt: .now
        )
        let question = Moment(
            id: UUID(),
            creatorUserID: partnerUserID,
            content: .question(MomentQuestion(key: "understand_today", prompt: "題目")),
            createdAt: .now,
            questionAnswers: [
                MomentQuestionAnswer(
                    id: UUID(),
                    answererUserID: partnerUserID,
                    content: "伴侶答案",
                    createdAt: .now
                ),
                ownAnswer,
            ]
        )
        let service = MomentRemoteServiceFake(moments: [question, responseMoment])
        let model = MomentModel(service: service)
        await model.start()

        #expect(await model.removeOwnResponse(from: responseMoment, response: ownResponse))
        let withoutResponse = try #require(model.moments.first { $0.id == responseMoment.id })
        #expect(withoutResponse.responses.isEmpty)

        #expect(await model.removeOwnAnswer(from: question, answer: ownAnswer))
        let redacted = try #require(model.moments.first { $0.id == question.id })
        let marker = try #require(redacted.questionAnswers.first { $0.id == ownAnswer.id })
        #expect(marker.content == nil)
        #expect(marker.removedAt != nil)
        #expect(redacted.isComplete)
        #expect(model.currentUserHasAnswered(redacted))
    }

    @MainActor
    @Test func momentOwnAnswerRemovalBeforeRevealKeepsAnsweredStateWithoutCompletingQuestion() async throws {
        let currentUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let ownAnswer = MomentQuestionAnswer(
            id: UUID(),
            answererUserID: currentUserID,
            content: "尚未一起揭曉的回答",
            createdAt: .now
        )
        let question = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .question(MomentQuestion(key: "understand_today", prompt: "題目")),
            createdAt: .now,
            questionAnswers: [ownAnswer]
        )
        let service = MomentRemoteServiceFake(moments: [question])
        let model = MomentModel(service: service)
        await model.start()

        #expect(await model.removeOwnAnswer(from: question, answer: ownAnswer))
        let updated = try #require(model.moments.first { $0.id == question.id })
        let marker = try #require(updated.questionAnswers.first { $0.id == ownAnswer.id })
        #expect(marker.content == nil)
        #expect(marker.removedAt != nil)
        #expect(!updated.isComplete)
        #expect(model.currentUserHasAnswered(updated))
    }

    @MainActor
    @Test func momentInteractionEmptyReceiptIsAcceptedWhenWholeMomentIsAlreadyHidden() async throws {
        let currentUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let relationshipID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
        let suiteName = "MomentEmptyReceiptTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TodaySnapshotStore(defaults: defaults)
        let response = MomentResponse(
            id: UUID(),
            responderUserID: currentUserID,
            content: .emoji(.heart),
            createdAt: .now
        )
        let responseMoment = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .text("已被整筆刪除"),
            createdAt: .now,
            responses: [response]
        )
        let responseService = MomentRemoteServiceFake(
            moments: [responseMoment],
            operationStore: store
        )
        let responseModel = MomentModel(service: responseService)
        await responseModel.start()
        responseService.removeResponseReturnsEmpty = true

        #expect(await responseModel.removeOwnResponse(from: responseMoment, response: response))
        #expect(responseModel.moments.isEmpty)
        #expect(store.momentOperationID(
            for: .removeResponse(momentID: responseMoment.id, responseID: response.id),
            userID: currentUserID,
            relationshipID: relationshipID
        ) == nil)

        let answer = MomentQuestionAnswer(
            id: UUID(),
            answererUserID: currentUserID,
            content: "回答",
            createdAt: .now
        )
        let question = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .question(MomentQuestion(key: "understand_today", prompt: "題目")),
            createdAt: .now,
            questionAnswers: [answer]
        )
        let answerService = MomentRemoteServiceFake(moments: [question], operationStore: store)
        let answerModel = MomentModel(service: answerService)
        await answerModel.start()
        answerService.removeAnswerReturnsEmpty = true

        #expect(await answerModel.removeOwnAnswer(from: question, answer: answer))
        #expect(answerModel.moments.isEmpty)
        #expect(store.momentOperationID(
            for: .removeAnswer(momentID: question.id, answerID: answer.id),
            userID: currentUserID,
            relationshipID: relationshipID
        ) == nil)
    }

    @MainActor
    @Test func momentLifecycleBroadcastPrunesAndTargetedlyReloadsOneMoment() async throws {
        let original = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .text("原內容"),
            createdAt: .now
        )
        let service = MomentRemoteServiceFake(moments: [original])
        let model = MomentModel(service: service)
        await model.start()

        await service.sendChange(.momentDeleted(original.id))
        #expect(model.moments.isEmpty)

        let updated = Moment(
            id: original.id,
            creatorUserID: original.creatorUserID,
            content: .text("復原後內容"),
            createdAt: original.createdAt
        )
        service.moments = [updated]
        service.hiddenMomentIDs.remove(original.id)
        await service.sendChange(.momentChanged(original.id))
        #expect(model.moments == [updated])
    }

    @MainActor
    @Test func momentDeleteBroadcastUsesDurableHintToHidePageExternalSourceImmediately() async {
        let unrelated = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .text("目前頁面"),
            createdAt: .now
        )
        let deletedMomentID = UUID()
        let sourceMessageID = UUID()
        let service = MomentRemoteServiceFake(moments: [unrelated])
        let model = MomentModel(service: service)
        await model.start()

        service.syncHints = [MomentSyncHint(
            momentID: deletedMomentID,
            isDeleted: true,
            sourceMessageID: sourceMessageID,
            revision: 1
        )]
        await service.sendChange(.momentDeleted(deletedMomentID))

        #expect(model.moments == [unrelated])
        #expect(model.hiddenMomentSourceMessageIDs == [sourceMessageID])
    }

    @MainActor
    @Test func staleDeleteBroadcastCannotHideMomentRestoredAtNewerRevision() async {
        let sourceMessageID = UUID()
        let restored = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .text("已在另一台復原"),
            createdAt: .now,
            sourceMessageID: sourceMessageID
        )
        let service = MomentRemoteServiceFake(moments: [restored])
        service.syncHints = [MomentSyncHint(
            momentID: restored.id,
            isDeleted: false,
            sourceMessageID: sourceMessageID,
            revision: 2
        )]
        let model = MomentModel(service: service)
        await model.start()

        await service.sendChange(.momentDeleted(restored.id))

        #expect(model.moments == [restored])
        #expect(!model.hiddenMomentSourceMessageIDs.contains(sourceMessageID))
    }

    @MainActor
    @Test func staleTargetedFetchCannotRewriteCacheAfterNewerDelete() async {
        let moment = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .text("舊 targeted snapshot"),
            createdAt: .now
        )
        let service = MomentRemoteServiceFake(moments: [moment])
        service.syncHints = [MomentSyncHint(
            momentID: moment.id,
            isDeleted: false,
            sourceMessageID: nil,
            revision: 1
        )]
        let model = MomentModel(service: service)
        await model.start()
        service.suspendedFetchMomentID = moment.id
        service.returnCapturedMomentAfterSuspension = true
        let staleChange = Task { await service.sendChange(.momentChanged(moment.id)) }
        guard await waitForLifecycleCondition({ service.fetchMomentContinuation != nil }) else {
            Issue.record("Targeted Moment fetch did not suspend")
            service.resumeFetchMoment()
            await staleChange.value
            return
        }

        service.moments = []
        service.hiddenMomentIDs.insert(moment.id)
        service.syncHints = [MomentSyncHint(
            momentID: moment.id,
            isDeleted: true,
            sourceMessageID: nil,
            revision: 2
        )]
        await service.sendChange(.momentDeleted(moment.id))
        service.resumeFetchMoment()
        await staleChange.value

        #expect(model.moments.isEmpty)
        #expect(service.cachedMomentsValue?.contains { $0.id == moment.id } != true)
        #expect(service.cacheEvictionMomentIDs.contains(moment.id))
    }

    @MainActor
    @Test func conversationRefreshRemovesDeletedMomentSourceMarker() async throws {
        let source = ChatMessage(
            id: UUID(),
            senderUserID: UUID(),
            body: "來源",
            createdAt: .now
        )
        let service = ConversationRemoteServiceFake(
            currentUserID: UUID(),
            messages: [source],
            unreadCount: 0
        )
        service.savedMomentMessageIDs = [source.id]
        let model = ConversationModel(service: service)
        await model.start()
        #expect(model.savedMomentMessageIDs == [source.id])

        service.savedMomentMessageIDs = []
        await model.refresh()
        #expect(model.savedMomentMessageIDs.isEmpty)
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

    @Test func authenticationStateDistinguishesRestoreCancelAndSignOut() {
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
    @Test func pairingModelRestoresClosingRelationshipAndCompletesItsPersonalArchive() async {
        let relationship = PairingRelationship(
            id: UUID(),
            memberCount: 2,
            status: "closing"
        )
        let service = PairingRemoteServiceFake(
            currentRelationship: relationship,
            invitation: PairingInvitation(
                relationshipID: UUID(),
                token: UUID(),
                shortCode: "7K3MW9QP",
                expiresAt: .now
            ),
            acceptedRelationshipID: UUID()
        )
        let model = PairingModel(service: service)

        await model.refreshForAuthenticatedSession(userID: UUID())
        #expect(model.state == .closing(relationship))

        let archive = PersonalArchive(id: UUID(), relationshipID: relationship.id)
        service.currentRelationshipValue = nil
        service.personalArchiveValue = archive
        await model.sealPersonalArchive()

        #expect(service.sealedRelationshipIDs == [relationship.id])
        #expect(model.state == .archived(archive))
        #expect(model.statusMessage == "解除配對已完成；你的個人封存可以匯出。")

        model.resetForAuthenticatedSession()
        await model.refreshForAuthenticatedSession(userID: UUID())
        #expect(model.state == .archived(archive))

        await model.createOrRetryInvitation()
        #expect(model.state == .waiting(
            PairingRelationship(id: service.invitation.relationshipID, memberCount: 1),
            invitation: service.invitation
        ))
    }

    @MainActor
    @Test func pairingModelBeginsAndSealsFromOneConfirmedUserAction() async {
        let relationship = PairingRelationship(id: UUID(), memberCount: 2)
        let archive = PersonalArchive(id: UUID(), relationshipID: relationship.id)
        let service = PairingRemoteServiceFake(
            currentRelationship: relationship,
            invitation: PairingInvitation(
                relationshipID: UUID(),
                token: UUID(),
                shortCode: "7K3MW9QP",
                expiresAt: .now
            ),
            acceptedRelationshipID: UUID()
        )
        service.personalArchiveByRelationshipID[relationship.id] = archive
        let model = PairingModel(service: service, initialState: .paired(relationship))

        await model.beginUnpairingAndSealPersonalArchive(hasInFlightContent: false)

        #expect(service.begunUnpairingRelationshipIDs == [relationship.id])
        #expect(service.sealedRelationshipIDs == [relationship.id])
        #expect(model.state == .closing(PairingRelationship(
            id: relationship.id,
            memberCount: 2,
            status: "closing"
        )))
        #expect(model.closingPersonalArchive == archive)
        #expect(model.statusMessage == "你的個人封存已安全保存，等待另一方完成。")
    }

    @MainActor
    @Test func pairingModelBlocksUnpairingWhenContentIsStillPendingOrSending() async {
        let relationship = PairingRelationship(id: UUID(), memberCount: 2)
        let service = PairingRemoteServiceFake(
            currentRelationship: relationship,
            invitation: PairingInvitation(
                relationshipID: UUID(),
                token: UUID(),
                shortCode: "7K3MW9QP",
                expiresAt: .now
            ),
            acceptedRelationshipID: UUID()
        )
        let model = PairingModel(service: service, initialState: .paired(relationship))

        await model.beginUnpairingAndSealPersonalArchive(hasInFlightContent: true)
        #expect(service.begunUnpairingRelationshipIDs.isEmpty)
        #expect(model.state == .paired(relationship))
        #expect(model.statusMessage?.contains("正在傳送") == true)

        service.unpairingReadinessValue = .pendingContent(count: 2)
        await model.beginUnpairingAndSealPersonalArchive(hasInFlightContent: false)
        #expect(service.begunUnpairingRelationshipIDs.isEmpty)
        #expect(model.statusMessage?.contains("2 筆待送內容") == true)
    }

    @MainActor
    @Test func pairingModelLeavesClosingWithoutRestartAfterPartnerCompletesArchive() async {
        let relationship = PairingRelationship(
            id: UUID(),
            memberCount: 2,
            status: "closing"
        )
        let archive = PersonalArchive(id: UUID(), relationshipID: relationship.id)
        let service = PairingRemoteServiceFake(
            currentRelationship: relationship,
            invitation: PairingInvitation(
                relationshipID: UUID(),
                token: UUID(),
                shortCode: "7K3MW9QP",
                expiresAt: Date(timeIntervalSince1970: 2_000_000_000)
            ),
            acceptedRelationshipID: UUID()
        )
        service.personalArchiveValue = archive
        let model = PairingModel(service: service, initialState: .closing(relationship))

        await model.sealPersonalArchive()
        #expect(model.state == .closing(relationship))
        #expect(model.statusMessage == "你的個人封存已建立，等待另一方完成。")

        service.currentRelationshipValue = nil
        await model.refresh()
        #expect(model.state == .archived(archive))
        #expect(model.statusMessage == nil)
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
private func waitForLifecycleCondition(
    attempts: Int = 10_000,
    _ condition: @escaping @MainActor () -> Bool
) async -> Bool {
    for _ in 0..<attempts {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}

@Suite struct ModelLifecycleTests {
    @MainActor
    @Test func momentModelStopRejectsAnOlderDelayedRefresh() async {
        let baseline = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .text("基線"),
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let staleIncoming = Moment(
            id: UUID(),
            creatorUserID: UUID(),
            content: .text("stop 後不得寫入"),
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let service = MomentRemoteServiceFake(moments: [baseline])
        let model = MomentModel(service: service)
        await model.start()

        service.moments = [staleIncoming]
        service.suspendFetchMoments = true
        let refresh = Task { await model.refresh() }
        guard await waitForLifecycleCondition({
            service.fetchMomentsContinuation != nil
        }) else {
            Issue.record("Moment refresh did not reach the deterministic suspension point.")
            refresh.cancel()
            return
        }
        let resume = Task { @MainActor in
            for _ in 0..<20 { await Task.yield() }
            service.resumeFetchMoments()
        }
        await model.stop()
        service.cachedMomentsValue = nil
        await resume.value
        await refresh.value

        #expect(model.moments == [baseline])
        #expect(service.cachedMomentsValue == nil)
        #expect(!service.isObserving)
    }

    @MainActor
    @Test func togetherNowModelStopRejectsAnOlderDelayedRefresh() async {
        let baseline = TogetherNowSnapshot.preview
        let staleIncoming = TogetherNowSnapshot(
            currentUserID: baseline.currentUserID,
            partnerUserID: baseline.partnerUserID,
            currentDisplayName: "stop 後不得寫入",
            partnerDisplayName: baseline.partnerDisplayName,
            privatePartnerName: baseline.privatePartnerName,
            currentStatus: baseline.currentStatus,
            partnerStatus: baseline.partnerStatus
        )
        let service = TogetherNowRemoteServiceFake(snapshot: baseline)
        let model = TogetherNowModel(service: service)
        await model.start()

        service.snapshot = staleIncoming
        service.suspendFetchSnapshot = true
        let refresh = Task { await model.refresh() }
        guard await waitForLifecycleCondition({
            service.fetchSnapshotContinuation != nil
        }) else {
            Issue.record("Together refresh did not reach the deterministic suspension point.")
            refresh.cancel()
            return
        }
        let resume = Task { @MainActor in
            for _ in 0..<20 { await Task.yield() }
            service.resumeFetchSnapshot()
        }
        await model.stop()
        service.cachedSnapshotValue = nil
        await resume.value
        await refresh.value

        #expect(model.snapshot == baseline)
        #expect(service.cachedSnapshotValue == nil)
        #expect(!service.isObserving)
    }

    @MainActor
    @Test func conversationModelStopRejectsAnOlderDelayedRefreshAndCacheWrite() async {
        let currentUserID = UUID()
        let partnerUserID = UUID()
        let baseline = ChatMessage(
            id: UUID(),
            senderUserID: partnerUserID,
            body: "基線",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let staleIncoming = ChatMessage(
            id: UUID(),
            senderUserID: partnerUserID,
            body: "stop 後不得寫入",
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let service = ConversationRemoteServiceFake(
            currentUserID: currentUserID,
            messages: [baseline],
            unreadCount: 1
        )
        let model = ConversationModel(service: service)
        await model.start()
        let persistedSnapshotCount = service.persistedSnapshots.count

        service.messages = [staleIncoming]
        service.suspendFetchSnapshot = true
        let refresh = Task { await model.refresh() }
        guard await waitForLifecycleCondition({
            service.fetchSnapshotContinuation != nil
        }) else {
            Issue.record("Conversation refresh did not reach the deterministic suspension point.")
            refresh.cancel()
            return
        }
        let stop = Task { await model.stop() }
        await Task.yield()
        service.resumeFetchSnapshot()
        await refresh.value
        await stop.value

        #expect(model.messages == [baseline])
        #expect(service.persistedSnapshots.count == persistedSnapshotCount)
        #expect(!service.isObserving)
    }

    @MainActor
    @Test func sharedAppointmentModelStopInvalidatesADelayedStartBeforeItCanReconcileOrObserve() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let appointment = SharedAppointment(
            id: UUID(),
            creatorUserID: UUID(),
            title: "不應在 stop 後復活",
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
        service.suspendFetchAppointments = true
        let scheduler = SharedAppointmentReminderSchedulerFake()
        let model = SharedAppointmentModel(
            service: service,
            now: { now },
            reminderScheduler: scheduler
        )

        let start = Task { await model.start() }
        guard await waitForLifecycleCondition({
            service.fetchAppointmentsContinuation != nil
        }) else {
            Issue.record("Appointment start did not reach the deterministic suspension point.")
            start.cancel()
            return
        }
        let stop = Task { await model.stop() }
        await Task.yield()
        await scheduler.removeAll()
        service.resumeFetchAppointments()
        await start.value
        await stop.value

        #expect(model.appointments.isEmpty)
        #expect(scheduler.reconciledAppointments.isEmpty)
        #expect(scheduler.removeAllCount == 1)
        #expect(!service.isObserving)
    }

    @MainActor
    @Test func sharedAppointmentModelStopSerializesAnInFlightObserverAndRejectsItsStaleCallback() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let baseline = SharedAppointment(
            id: UUID(),
            creatorUserID: UUID(),
            title: "基線",
            startsAt: now.addingTimeInterval(7_200),
            location: nil,
            note: nil,
            reminderAt: nil,
            status: .scheduled,
            sourceMessageID: nil,
            createdAt: now,
            updatedAt: now
        )
        let staleIncoming = SharedAppointment(
            id: UUID(),
            creatorUserID: UUID(),
            title: "舊 observer 不得復活",
            startsAt: now.addingTimeInterval(10_800),
            location: nil,
            note: nil,
            reminderAt: nil,
            status: .scheduled,
            sourceMessageID: nil,
            createdAt: now,
            updatedAt: now
        )
        let service = SharedAppointmentRemoteServiceFake()
        service.appointments = [baseline]
        service.suspendStartObserving = true
        let scheduler = SharedAppointmentReminderSchedulerFake()
        let model = SharedAppointmentModel(
            service: service,
            now: { now },
            reminderScheduler: scheduler
        )

        let start = Task { await model.start() }
        guard await waitForLifecycleCondition({
            service.startObservingContinuation != nil
        }) else {
            Issue.record("Appointment observer did not reach the deterministic suspension point.")
            start.cancel()
            return
        }
        let stop = Task { await model.stop() }
        await Task.yield()
        service.resumeStartObserving()
        await start.value
        await stop.value
        scheduler.reconciledAppointments.removeAll()

        service.appointments = [staleIncoming]
        await service.sendStaleChange()

        #expect(model.appointments == [baseline])
        #expect(scheduler.reconciledAppointments.isEmpty)
        #expect(!service.isObserving)
    }

    @MainActor
    @Test func sharedAppointmentModelStopInvalidatesAnOlderDelayedRefresh() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let baseline = SharedAppointment(
            id: UUID(),
            creatorUserID: UUID(),
            title: "基線",
            startsAt: now.addingTimeInterval(7_200),
            location: nil,
            note: nil,
            reminderAt: now.addingTimeInterval(3_600),
            status: .scheduled,
            sourceMessageID: nil,
            createdAt: now,
            updatedAt: now
        )
        let staleIncoming = SharedAppointment(
            id: UUID(),
            creatorUserID: UUID(),
            title: "stop 後不得寫入",
            startsAt: now.addingTimeInterval(10_800),
            location: nil,
            note: nil,
            reminderAt: now.addingTimeInterval(7_200),
            status: .scheduled,
            sourceMessageID: nil,
            createdAt: now,
            updatedAt: now
        )
        let service = SharedAppointmentRemoteServiceFake()
        service.appointments = [baseline]
        let scheduler = SharedAppointmentReminderSchedulerFake()
        let model = SharedAppointmentModel(
            service: service,
            now: { now },
            reminderScheduler: scheduler
        )
        await model.start()
        scheduler.reconciledAppointments.removeAll()

        service.appointments = [staleIncoming]
        service.suspendFetchAppointments = true
        let refresh = Task { await model.refresh() }
        guard await waitForLifecycleCondition({
            service.fetchAppointmentsContinuation != nil
        }) else {
            Issue.record("Appointment refresh did not reach the deterministic suspension point.")
            refresh.cancel()
            return
        }
        let resume = Task { @MainActor in
            for _ in 0..<20 { await Task.yield() }
            service.resumeFetchAppointments()
        }
        await model.stop()
        service.cachedAppointments = nil
        await scheduler.removeAll()
        await resume.value
        await refresh.value

        #expect(model.appointments == [baseline])
        #expect(service.cachedAppointments == nil)
        #expect(scheduler.reconciledAppointments.isEmpty)
        #expect(scheduler.removeAllCount == 1)
        #expect(!service.isObserving)
    }

    @MainActor
    @Test func sharedAppointmentModelStopPreventsAnInFlightDrainFromReaddingReminders() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let service = SharedAppointmentRemoteServiceFake()
        service.suspendAppointmentDelivery = true
        let scheduler = SharedAppointmentReminderSchedulerFake()
        let model = SharedAppointmentModel(
            service: service,
            now: { now },
            reminderScheduler: scheduler
        )
        await model.start()
        scheduler.reconciledAppointments.removeAll()
        let draft = SharedAppointmentDraft(
            title: "仍應送達，但 stop 後不改 UI 或提醒",
            startsAt: now.addingTimeInterval(7_200),
            location: nil,
            note: nil,
            reminderAt: nil,
            sourceMessageID: nil
        )

        let create = Task { await model.create(draft) }
        guard await waitForLifecycleCondition({
            service.appointmentDeliveryContinuation != nil
        }) else {
            Issue.record("Appointment delivery did not reach the deterministic suspension point.")
            create.cancel()
            return
        }
        let appointmentsBeforeStop = model.appointments
        let resume = Task { @MainActor in
            for _ in 0..<20 { await Task.yield() }
            service.resumeAppointmentDelivery()
        }
        await model.stop()
        await scheduler.removeAll()
        await resume.value
        #expect(await create.value)

        #expect(model.appointments == appointmentsBeforeStop)
        #expect(service.pendingEntries.isEmpty)
        #expect(scheduler.reconciledAppointments.isEmpty)
        #expect(scheduler.removeAllCount == 1)
        #expect(!service.isObserving)
    }

    @MainActor
    @Test func sharedAppointmentModelStopJoinsAnInFlightReminderReconcileBeforeCleanup() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let appointment = SharedAppointment(
            id: UUID(),
            creatorUserID: UUID(),
            title: "提醒清理順序",
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
        await model.start()
        scheduler.reconciledAppointments.removeAll()

        scheduler.suspendReconcile = true
        let refresh = Task { await model.refresh() }
        guard await waitForLifecycleCondition({
            scheduler.reconcileContinuation != nil
        }) else {
            Issue.record("Reminder reconcile did not reach the deterministic suspension point.")
            refresh.cancel()
            return
        }
        let resume = Task { @MainActor in
            for _ in 0..<20 { await Task.yield() }
            scheduler.resumeReconcile()
        }
        await model.stop()
        await scheduler.removeAll()
        await resume.value
        await refresh.value

        #expect(scheduler.reconciledAppointments.isEmpty)
        #expect(scheduler.removeAllCount == 1)
        #expect(!service.isObserving)
    }

    @MainActor
    @Test func sharedAppointmentOldStopDoesNotStopDiscussionAfterLifecycleRestarts() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let appointment = SharedAppointment(
            id: UUID(),
            creatorUserID: UUID(),
            title: "重新顯示中的約定",
            startsAt: now.addingTimeInterval(7_200),
            location: nil,
            note: nil,
            reminderAt: nil,
            status: .scheduled,
            sourceMessageID: nil,
            createdAt: now,
            updatedAt: now
        )
        let service = SharedAppointmentRemoteServiceFake()
        service.appointments = [appointment]
        let discussionService = ConversationRemoteServiceFake(
            currentUserID: UUID(),
            messages: [],
            unreadCount: 0
        )
        let scheduler = SharedAppointmentReminderSchedulerFake()
        let model = SharedAppointmentModel(
            service: service,
            now: { now },
            reminderScheduler: scheduler,
            discussionModelFactory: { _ in ConversationModel(service: discussionService) }
        )
        await model.start()
        let discussionModel = try? #require(model.discussionModel(for: appointment.id))
        guard let discussionModel else { return }
        await discussionModel.start()
        #expect(discussionService.isObserving)

        service.suspendStopObserving = true
        let oldStop = Task { await model.stop() }
        guard await waitForLifecycleCondition({
            service.stopObservingContinuation != nil
        }) else {
            Issue.record("Appointment stop did not reach the deterministic suspension point.")
            oldStop.cancel()
            return
        }
        let restart = Task { await model.start() }
        guard await waitForLifecycleCondition({ scheduler.activateCount == 2 }) else {
            Issue.record("Appointment restart did not begin before the old stop resumed.")
            restart.cancel()
            oldStop.cancel()
            service.resumeStopObserving()
            return
        }
        await discussionModel.start()
        service.resumeStopObserving()
        await oldStop.value
        await restart.value

        #expect(service.isObserving)
        #expect(discussionService.isObserving)
    }
}

private enum AuthSessionSignOutTestError: Error {
    case failed
}

@MainActor
private final class AuthSessionSignOutServiceFake: AuthSessionSignOutServing {
    private(set) var currentSessionSignOutCount = 0
    var currentSessionSignOutError: Error?
    private var currentSessionSignOutContinuation: CheckedContinuation<Void, Never>?
    private let suspendsCurrentSessionSignOut: Bool

    init(
        currentSessionSignOutError: Error? = nil,
        suspendsCurrentSessionSignOut: Bool = false
    ) {
        self.currentSessionSignOutError = currentSessionSignOutError
        self.suspendsCurrentSessionSignOut = suspendsCurrentSessionSignOut
    }

    func signOutCurrentSession() async throws {
        currentSessionSignOutCount += 1
        if suspendsCurrentSessionSignOut {
            await withCheckedContinuation { currentSessionSignOutContinuation = $0 }
        }
        if let currentSessionSignOutError {
            throw currentSessionSignOutError
        }
    }

    func resumeCurrentSessionSignOut() {
        currentSessionSignOutContinuation?.resume()
        currentSessionSignOutContinuation = nil
    }
}

#if DEBUG
@MainActor
private final class SessionProtectedDataInspectorFake: SessionProtectedDataInspecting {
    private let snapshot: SessionProtectedDataSnapshot
    private(set) var inspectionCount = 0

    init(snapshot: SessionProtectedDataSnapshot) {
        self.snapshot = snapshot
    }

    func inspect() async -> SessionProtectedDataSnapshot {
        inspectionCount += 1
        return snapshot
    }
}
#endif

@MainActor
private final class AppLockAuthenticatorFake: AppLockAuthenticating {
    var result: AppLockAuthenticationResult
    private(set) var authenticationCount = 0

    init(result: AppLockAuthenticationResult) {
        self.result = result
    }

    func authenticate(reason _: String) async -> AppLockAuthenticationResult {
        authenticationCount += 1
        return result
    }
}

@MainActor
private final class SharedAppointmentRemoteServiceFake: SharedAppointmentRemoteServing {
    var appointments: [SharedAppointment] = []
    var cachedAppointments: [SharedAppointment]?
    var appointmentEvents: [SharedAppointmentEvent] = []
    var discussionSummaries: [SharedAppointmentDiscussionSummary] = []
    var markedInteractionAppointmentIDs: [UUID] = []
    var markedInteractionSourceIdentities: [UUID?] = []
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
    var suspendAppointmentDelivery = false
    var appointmentDeliveryContinuation: CheckedContinuation<Void, Never>?
    var suspendStartObserving = false
    var startObservingContinuation: CheckedContinuation<Void, Never>?
    var suspendStopObserving = false
    var stopObservingContinuation: CheckedContinuation<Void, Never>?
    var isObserving = false
    private var onChange: (@MainActor () async -> Void)?
    private var staleOnChange: (@MainActor () async -> Void)?

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

    func markAppointmentInteractionsRead(
        appointmentID: UUID,
        visibleSourceIdentity: UUID?
    ) async throws {
        guard appointments.contains(where: { $0.id == appointmentID }) else {
            throw CancellationError()
        }
        markedInteractionAppointmentIDs.append(appointmentID)
        markedInteractionSourceIdentities.append(visibleSourceIdentity)
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
        if suspendAppointmentDelivery {
            await withCheckedContinuation { continuation in
                appointmentDeliveryContinuation = continuation
            }
        }
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

    func resumeAppointmentDelivery() {
        suspendAppointmentDelivery = false
        appointmentDeliveryContinuation?.resume()
        appointmentDeliveryContinuation = nil
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
        staleOnChange = onChange
        if suspendStartObserving {
            await withCheckedContinuation { continuation in
                startObservingContinuation = continuation
            }
        }
        isObserving = true
        self.onChange = onChange
    }

    func resumeStartObserving() {
        suspendStartObserving = false
        startObservingContinuation?.resume()
        startObservingContinuation = nil
    }

    func stopObservingChanges() async {
        if suspendStopObserving {
            await withCheckedContinuation { continuation in
                stopObservingContinuation = continuation
            }
        }
        isObserving = false
        onChange = nil
    }

    func resumeStopObserving() {
        suspendStopObserving = false
        stopObservingContinuation?.resume()
        stopObservingContinuation = nil
    }

    func sendStaleChange() async {
        await staleOnChange?()
    }
}

@MainActor
private final class SharedAppointmentReminderSchedulerFake: SharedAppointmentReminderScheduling {
    var authorization: SharedAppointmentReminderAuthorization = .authorized
    var authorizationRequestCount = 0
    var activateCount = 0
    var reconciledAppointments: [[SharedAppointment]] = []
    var removeAllCount = 0
    var suspendReconcile = false
    var reconcileContinuation: CheckedContinuation<Void, Never>?

    func authorizationStatus() async -> SharedAppointmentReminderAuthorization {
        authorization
    }

    func requestAuthorization() async -> SharedAppointmentReminderAuthorization {
        authorizationRequestCount += 1
        return authorization
    }

    func activate() async {
        activateCount += 1
    }

    func reconcile(_ appointments: [SharedAppointment]) async throws {
        if suspendReconcile {
            await withCheckedContinuation { continuation in
                reconcileContinuation = continuation
            }
        }
        reconciledAppointments.append(appointments)
    }

    func resumeReconcile() {
        suspendReconcile = false
        reconcileContinuation?.resume()
        reconcileContinuation = nil
    }

    func removeAll() async {
        removeAllCount += 1
        reconciledAppointments.removeAll()
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
    var persistedSnapshots: [ConversationSnapshot] = []
    var sendFailuresRemaining = 0
    var fetchFailuresRemaining = 0
    var acknowledgementFailuresRemaining = 0
    var reactionFailuresRemaining = 0
    var removeReactionFailuresRemaining = 0
    var saveMomentFailuresRemaining = 0
    var sendDelay: Duration = .zero
    var fetchDelay: Duration = .zero
    var suspendFetchSnapshot = false
    var fetchSnapshotContinuation: CheckedContinuation<Void, Never>?
    var markReadDelay: Duration = .zero
    var startObservingDelay: Duration = .zero
    var reactionDelay: Duration = .zero
    var removeReactionDelay: Duration = .zero
    var deliveryResultOverride: ConversationDeliveryResult?
    var nextAcceptedAt = Date(timeIntervalSince1970: 200)
    var isObserving = false
    var startObservingCallCount = 0
    var returnsCachedSnapshot = true
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
        guard returnsCachedSnapshot else { return nil }
        return ConversationSnapshot(
            currentUserID: currentUserID,
            messages: messages,
            unreadCount: unreadCount,
            savedMomentMessageIDs: savedMomentMessageIDs
        )
    }

    func persistCachedSnapshot(_ snapshot: ConversationSnapshot) async {
        persistedSnapshots.append(snapshot)
    }

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
        if suspendFetchSnapshot {
            await withCheckedContinuation { continuation in
                fetchSnapshotContinuation = continuation
            }
        }
        try await Task.sleep(for: fetchDelay)
        return snapshot
    }

    func resumeFetchSnapshot() {
        suspendFetchSnapshot = false
        fetchSnapshotContinuation?.resume()
        fetchSnapshotContinuation = nil
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
        try await Task.sleep(for: markReadDelay)
        guard let target = messages.first(where: { $0.id == messageID }) else { return }
        unreadCount = messages.filter { message in
            guard message.senderUserID != currentUserID else { return false }
            if message.createdAt != target.createdAt {
                return message.createdAt > target.createdAt
            }
            return message.id.uuidString > target.id.uuidString
        }.count
    }

    func markAllRelationshipInteractionsRead() async throws {}

    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws {
        startObservingCallCount += 1
        try await Task.sleep(for: startObservingDelay)
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
    var sealedRelationshipIDs: [UUID] = []
    var begunUnpairingRelationshipIDs: [UUID] = []
    var personalArchiveValue: PersonalArchive?
    var personalArchiveByRelationshipID: [UUID: PersonalArchive] = [:]
    var unpairingReadinessValue: UnpairingReadiness = .ready

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

    func unpairingReadiness(relationshipID _: UUID) async throws -> UnpairingReadiness {
        unpairingReadinessValue
    }

    func beginUnpairing(relationshipID: UUID) async throws {
        begunUnpairingRelationshipIDs.append(relationshipID)
        if let relationship = currentRelationshipValue {
            currentRelationshipValue = PairingRelationship(
                id: relationship.id,
                memberCount: relationship.memberCount,
                status: "closing"
            )
        }
    }

    func sealPersonalArchive(relationshipID: UUID) async throws -> PersonalArchive {
        sealedRelationshipIDs.append(relationshipID)
        return personalArchiveByRelationshipID[relationshipID]
            ?? PersonalArchive(id: UUID(), relationshipID: relationshipID)
    }

    func ownPersonalArchive() async throws -> PersonalArchive? {
        personalArchiveValue
    }

    func personalArchive(relationshipID: UUID) async throws -> PersonalArchive? {
        personalArchiveByRelationshipID[relationshipID]
    }

    func preparePersonalArchiveExport(
        archive _: PersonalArchive
    ) async throws -> PersonalArchiveExportPreparation {
        throw NSError(domain: "PairingRemoteServiceFake", code: 1)
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

    func unpairingReadiness(relationshipID _: UUID) async throws -> UnpairingReadiness { .ready }

    func beginUnpairing(relationshipID _: UUID) async throws {}

    func sealPersonalArchive(relationshipID: UUID) async throws -> PersonalArchive {
        PersonalArchive(id: UUID(), relationshipID: relationshipID)
    }

    func preparePersonalArchiveExport(
        archive _: PersonalArchive
    ) async throws -> PersonalArchiveExportPreparation {
        throw NSError(domain: "SuspendedPairingRemoteServiceFake", code: 1)
    }
}

@MainActor
private final class TogetherNowRemoteServiceFake: TogetherNowRemoteServing {
    var snapshot: TogetherNowSnapshot
    var cachedSnapshotValue: TogetherNowSnapshot?
    var fetchDelay: Duration = .zero
    var suspendFetchSnapshot = false
    var fetchSnapshotContinuation: CheckedContinuation<Void, Never>?
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
        if suspendFetchSnapshot {
            await withCheckedContinuation { continuation in
                fetchSnapshotContinuation = continuation
            }
        }
        try await Task.sleep(for: fetchDelay)
        if fetchFailuresRemaining > 0 {
            fetchFailuresRemaining -= 1
            throw TestServiceError.expected
        }
        cachedSnapshotValue = snapshot
        return snapshot
    }

    func resumeFetchSnapshot() {
        suspendFetchSnapshot = false
        fetchSnapshotContinuation?.resume()
        fetchSnapshotContinuation = nil
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
    private let relationshipID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
    var moments: [Moment]
    var cachedMomentsValue: [Moment]?
    var cachedPhotoDataByMomentID: [UUID: Data] = [:]
    var fetchDelay: Duration = .zero
    var suspendFetchMoments = false
    var fetchMomentsContinuation: CheckedContinuation<Void, Never>?
    var returnCapturedMomentsAfterSuspension = false
    var failNextFetchAfterSuspendedSnapshot = false
    var failNextFetchAfterSuccessfulSnapshot = false
    var fetchFailuresRemaining = 0
    var createdDrafts: [MomentDraft] = []
    var suspendCreateAcknowledgement = false
    var createAcknowledgementContinuation: CheckedContinuation<Void, Never>?
    var responseClientIDs: [UUID] = []
    var answerClientIDs: [UUID] = []
    var questionAttemptIDs: [(UUID, UUID)] = []
    var photoDataRequestIDs: [UUID] = []
    var remotePhotoDataByMomentID: [UUID: Data] = [:]
    var suspendPhotoData = false
    var photoDataContinuation: CheckedContinuation<Void, Never>?
    var responseFailuresRemaining = 0
    var responseDelay: Duration = .zero
    var suspendCreateResponseAcknowledgement = false
    var createResponseAcknowledgementContinuation: CheckedContinuation<Void, Never>?
    var answerFailuresRemaining = 0
    var questionFailuresRemaining = 0
    var hiddenMomentIDs: Set<UUID> = []
    var syncHints: [MomentSyncHint] = []
    var syncHintFailuresRemaining = 0
    var syncHintPageRequests: [(after: UUID?, limit: Int)] = []
    var fetchMomentRequestIDs: [UUID] = []
    var fetchMomentFailureIDs: Set<UUID> = []
    var suspendedFetchMomentID: UUID?
    var fetchMomentContinuation: CheckedContinuation<Void, Never>?
    var returnCapturedMomentAfterSuspension = false
    var recentlyDeletedMoments: [RecentlyDeletedMoment] = []
    var suspendFetchRecentlyDeleted = false
    var fetchRecentlyDeletedContinuation: CheckedContinuation<Void, Never>?
    var deleteOperationIDs: [UUID] = []
    var restoreOperationIDs: [UUID] = []
    var removeResponseOperationIDs: [UUID] = []
    var removeAnswerOperationIDs: [UUID] = []
    var deleteApplyThenFailRemaining = 0
    var suspendDeleteAcknowledgement = false
    var deleteAcknowledgementContinuation: CheckedContinuation<Void, Never>?
    var restoreApplyThenFailRemaining = 0
    var removeResponseApplyThenFailRemaining = 0
    var removeAnswerApplyThenFailRemaining = 0
    var suspendRemoveResponseAcknowledgement = false
    var removeResponseAcknowledgementContinuation: CheckedContinuation<Void, Never>?
    var deleteSupersededRemaining = 0
    var restoreSupersededRemaining = 0
    var removeResponseReturnsEmpty = false
    var removeAnswerReturnsEmpty = false
    var deleteApplicationCount = 0
    var restoreApplicationCount = 0
    var removeResponseApplicationCount = 0
    var removeAnswerApplicationCount = 0
    var isObserving = false
    var firstFetchObservedState: Bool?
    var cacheEvictionMomentIDs: [UUID] = []
    var operationStore: TodaySnapshotStore?
    private var deleteReceiptMomentByOperationID: [UUID: UUID] = [:]
    private var restoreReceiptMomentByOperationID: [UUID: UUID] = [:]
    private var removeResponseReceiptByOperationID: [UUID: (UUID, UUID)] = [:]
    private var removeAnswerReceiptByOperationID: [UUID: (UUID, UUID)] = [:]
    private var volatileOperationIDs: [MomentOperationIdentity: UUID] = [:]
    private var onChange: (@MainActor (MomentRemoteChange) async -> Void)?

    init(moments: [Moment], operationStore: TodaySnapshotStore? = nil) {
        self.moments = moments
        self.operationStore = operationStore
    }

    func currentUserID() async throws -> UUID { userID }

    func cachedMoments() -> [Moment]? { cachedMomentsValue }

    func cachedPhotoData(for momentID: UUID) -> Data? {
        cachedPhotoDataByMomentID[momentID]
    }

    func commitAcceptedMoments(_ moments: [Moment]) {
        cachedMomentsValue = moments
    }

    func commitAcceptedPhotoData(_ data: Data, for momentID: UUID) {
        cachedPhotoDataByMomentID[momentID] = data
    }

    func removeCachedMomentData(for momentID: UUID) {
        cacheEvictionMomentIDs.append(momentID)
        cachedMomentsValue?.removeAll { $0.id == momentID }
        cachedPhotoDataByMomentID[momentID] = nil
    }

    func fetchMoments() async throws -> [Moment] {
        if firstFetchObservedState == nil {
            firstFetchObservedState = isObserving
        }
        let capturedMoments = moments
        let wasSuspended = suspendFetchMoments
        if wasSuspended {
            await withCheckedContinuation { continuation in
                fetchMomentsContinuation = continuation
            }
        }
        try await Task.sleep(for: fetchDelay)
        if fetchFailuresRemaining > 0 {
            fetchFailuresRemaining -= 1
            throw TestServiceError.expected
        }
        if failNextFetchAfterSuccessfulSnapshot
            || (wasSuspended && failNextFetchAfterSuspendedSnapshot)
        {
            failNextFetchAfterSuccessfulSnapshot = false
            failNextFetchAfterSuspendedSnapshot = false
            fetchFailuresRemaining += 1
        }
        let result = wasSuspended && returnCapturedMomentsAfterSuspension
            ? capturedMoments
            : moments
        return result
    }

    func fetchMoment(id: UUID) async throws -> Moment? {
        fetchMomentRequestIDs.append(id)
        if fetchMomentFailureIDs.contains(id) {
            throw TestServiceError.expected
        }
        let captured = moments.first { $0.id == id && !hiddenMomentIDs.contains($0.id) }
        let wasSuspended = suspendedFetchMomentID == id
        if wasSuspended {
            await withCheckedContinuation { continuation in
                fetchMomentContinuation = continuation
            }
        }
        return wasSuspended && returnCapturedMomentAfterSuspension
            ? captured
            : moments.first { $0.id == id && !hiddenMomentIDs.contains($0.id) }
    }

    func fetchHiddenMomentIDs() async throws -> Set<UUID> { hiddenMomentIDs }

    func fetchMomentSyncHints(after momentID: UUID?, limit: Int) async throws
        -> [MomentSyncHint]
    {
        syncHintPageRequests.append((momentID, limit))
        if syncHintFailuresRemaining > 0 {
            syncHintFailuresRemaining -= 1
            throw TestServiceError.expected
        }
        let allHints: [MomentSyncHint]
        if !syncHints.isEmpty {
            allHints = syncHints
        } else {
            allHints = hiddenMomentIDs.map { momentID in
                let sourceMessageID = moments.first(where: { $0.id == momentID })?.sourceMessageID
                    ?? cachedMomentsValue?.first(where: { $0.id == momentID })?.sourceMessageID
                    ?? recentlyDeletedMoments.first(where: { $0.id == momentID })?.moment.sourceMessageID
                return MomentSyncHint(
                    momentID: momentID,
                    isDeleted: true,
                    sourceMessageID: sourceMessageID,
                    revision: 1
                )
            }
        }
        let ordered = allHints.sorted { $0.momentID.uuidString < $1.momentID.uuidString }
        return Array(ordered.lazy.filter {
            guard let momentID else { return true }
            return $0.momentID.uuidString > momentID.uuidString
        }.prefix(limit))
    }

    func operationID(for identity: MomentOperationIdentity) throws -> UUID {
        if let operationStore {
            return try operationStore.loadOrCreateMomentOperationID(
                for: identity,
                userID: userID,
                relationshipID: relationshipID
            )
        }
        if let existing = volatileOperationIDs[identity] { return existing }
        let created = UUID()
        volatileOperationIDs[identity] = created
        return created
    }

    func clearOperationID(for identity: MomentOperationIdentity) {
        if let operationStore {
            operationStore.clearMomentOperationID(
                for: identity,
                userID: userID,
                relationshipID: relationshipID
            )
        } else {
            volatileOperationIDs[identity] = nil
        }
    }

    func fetchRecentlyDeletedMoments() async throws -> [RecentlyDeletedMoment] {
        let captured = recentlyDeletedMoments
        if suspendFetchRecentlyDeleted {
            await withCheckedContinuation { continuation in
                fetchRecentlyDeletedContinuation = continuation
            }
        }
        return captured
    }

    func resumeFetchMoments() {
        suspendFetchMoments = false
        fetchMomentsContinuation?.resume()
        fetchMomentsContinuation = nil
    }

    func resumeFetchRecentlyDeleted() {
        suspendFetchRecentlyDeleted = false
        fetchRecentlyDeletedContinuation?.resume()
        fetchRecentlyDeletedContinuation = nil
    }

    func resumeCreateAcknowledgement() {
        suspendCreateAcknowledgement = false
        createAcknowledgementContinuation?.resume()
        createAcknowledgementContinuation = nil
    }

    func resumeCreateResponseAcknowledgement() {
        suspendCreateResponseAcknowledgement = false
        createResponseAcknowledgementContinuation?.resume()
        createResponseAcknowledgementContinuation = nil
    }

    func resumeFetchMoment() {
        suspendedFetchMomentID = nil
        fetchMomentContinuation?.resume()
        fetchMomentContinuation = nil
    }

    func resumeDeleteAcknowledgement() {
        suspendDeleteAcknowledgement = false
        deleteAcknowledgementContinuation?.resume()
        deleteAcknowledgementContinuation = nil
    }

    func resumeRemoveResponseAcknowledgement() {
        suspendRemoveResponseAcknowledgement = false
        removeResponseAcknowledgementContinuation?.resume()
        removeResponseAcknowledgementContinuation = nil
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
        if suspendCreateAcknowledgement {
            await withCheckedContinuation { continuation in
                createAcknowledgementContinuation = continuation
            }
        }
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
        if suspendCreateResponseAcknowledgement {
            await withCheckedContinuation { continuation in
                createResponseAcknowledgementContinuation = continuation
            }
        }
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

    func deleteMoment(id: UUID, operationID: UUID) async throws -> RecentlyDeletedMoment {
        deleteOperationIDs.append(operationID)
        if deleteSupersededRemaining > 0 {
            deleteSupersededRemaining -= 1
            throw MomentServiceError.operationSuperseded
        }
        if let receiptMomentID = deleteReceiptMomentByOperationID[operationID] {
            guard receiptMomentID == id,
                  let deleted = recentlyDeletedMoments.first(where: { $0.id == id })
            else { throw TestServiceError.expected }
            return deleted
        }
        let index = try #require(moments.firstIndex { $0.id == id })
        let moment = moments.remove(at: index)
        let deleted = RecentlyDeletedMoment(
            moment: moment,
            deletedAt: Date(timeIntervalSince1970: 1_000),
            purgeAfter: Date(timeIntervalSince1970: 1_000 + 30 * 86_400)
        )
        recentlyDeletedMoments.append(deleted)
        hiddenMomentIDs.insert(id)
        setSyncHint(for: moment, isDeleted: true)
        deleteReceiptMomentByOperationID[operationID] = id
        deleteApplicationCount += 1
        if suspendDeleteAcknowledgement {
            await withCheckedContinuation { continuation in
                deleteAcknowledgementContinuation = continuation
            }
        }
        if deleteApplyThenFailRemaining > 0 {
            deleteApplyThenFailRemaining -= 1
            throw TestServiceError.expected
        }
        return deleted
    }

    func restoreMoment(id: UUID, operationID: UUID) async throws -> Moment {
        restoreOperationIDs.append(operationID)
        if restoreSupersededRemaining > 0 {
            restoreSupersededRemaining -= 1
            throw MomentServiceError.operationSuperseded
        }
        if let receiptMomentID = restoreReceiptMomentByOperationID[operationID] {
            guard receiptMomentID == id,
                  let moment = moments.first(where: { $0.id == id })
            else { throw TestServiceError.expected }
            return moment
        }
        let index = try #require(recentlyDeletedMoments.firstIndex { $0.id == id })
        let deleted = recentlyDeletedMoments.remove(at: index)
        moments.append(deleted.moment)
        hiddenMomentIDs.remove(id)
        setSyncHint(for: deleted.moment, isDeleted: false)
        restoreReceiptMomentByOperationID[operationID] = id
        restoreApplicationCount += 1
        if restoreApplyThenFailRemaining > 0 {
            restoreApplyThenFailRemaining -= 1
            throw TestServiceError.expected
        }
        return deleted.moment
    }

    func removeResponse(momentID: UUID, responseID: UUID, operationID: UUID) async throws
        -> Moment?
    {
        removeResponseOperationIDs.append(operationID)
        if let receipt = removeResponseReceiptByOperationID[operationID] {
            guard receipt == (momentID, responseID) else { throw TestServiceError.expected }
            return moments.first { $0.id == momentID && !hiddenMomentIDs.contains(momentID) }
        }
        if removeResponseReturnsEmpty {
            if let moment = moments.first(where: { $0.id == momentID }) {
                setSyncHint(for: moment, isDeleted: true)
            }
            moments.removeAll { $0.id == momentID }
            hiddenMomentIDs.insert(momentID)
            removeResponseReceiptByOperationID[operationID] = (momentID, responseID)
            return nil
        }
        let momentIndex = try #require(moments.firstIndex { $0.id == momentID })
        moments[momentIndex].responses.removeAll { $0.id == responseID }
        let updated = moments[momentIndex]
        removeResponseReceiptByOperationID[operationID] = (momentID, responseID)
        removeResponseApplicationCount += 1
        setSyncHint(for: updated, isDeleted: false)
        if suspendRemoveResponseAcknowledgement {
            await withCheckedContinuation { continuation in
                removeResponseAcknowledgementContinuation = continuation
            }
        }
        if removeResponseApplyThenFailRemaining > 0 {
            removeResponseApplyThenFailRemaining -= 1
            throw TestServiceError.expected
        }
        return updated
    }

    func removeAnswer(momentID: UUID, answerID: UUID, operationID: UUID) async throws -> Moment? {
        removeAnswerOperationIDs.append(operationID)
        if let receipt = removeAnswerReceiptByOperationID[operationID] {
            guard receipt == (momentID, answerID) else { throw TestServiceError.expected }
            return moments.first { $0.id == momentID && !hiddenMomentIDs.contains(momentID) }
        }
        if removeAnswerReturnsEmpty {
            if let moment = moments.first(where: { $0.id == momentID }) {
                setSyncHint(for: moment, isDeleted: true)
            }
            moments.removeAll { $0.id == momentID }
            hiddenMomentIDs.insert(momentID)
            removeAnswerReceiptByOperationID[operationID] = (momentID, answerID)
            return nil
        }
        let momentIndex = try #require(moments.firstIndex { $0.id == momentID })
        let answerIndex = try #require(
            moments[momentIndex].questionAnswers.firstIndex { $0.id == answerID }
        )
        let answer = moments[momentIndex].questionAnswers[answerIndex]
        moments[momentIndex].questionAnswers[answerIndex] = MomentQuestionAnswer(
            id: answer.id,
            answererUserID: answer.answererUserID,
            content: nil,
            createdAt: answer.createdAt,
            removedAt: Date(timeIntervalSince1970: 1_000)
        )
        let updated = moments[momentIndex]
        removeAnswerReceiptByOperationID[operationID] = (momentID, answerID)
        removeAnswerApplicationCount += 1
        setSyncHint(for: updated, isDeleted: false)
        if removeAnswerApplyThenFailRemaining > 0 {
            removeAnswerApplyThenFailRemaining -= 1
            throw TestServiceError.expected
        }
        return updated
    }

    func photoData(for moment: Moment) async throws -> Data {
        photoDataRequestIDs.append(moment.id)
        if suspendPhotoData {
            await withCheckedContinuation { continuation in
                photoDataContinuation = continuation
            }
        }
        let data = remotePhotoDataByMomentID[moment.id]
            ?? cachedPhotoDataByMomentID[moment.id]
            ?? Data()
        cachedPhotoDataByMomentID[moment.id] = data
        return data
    }

    func resumePhotoData() {
        suspendPhotoData = false
        photoDataContinuation?.resume()
        photoDataContinuation = nil
    }

    func startObservingChanges(
        _ onChange: @escaping @MainActor (MomentRemoteChange) async -> Void
    ) async throws {
        isObserving = true
        self.onChange = onChange
    }

    func stopObservingChanges() async {
        isObserving = false
        onChange = nil
    }

    func sendChange(_ change: MomentRemoteChange = .reloadFirstPage) async {
        await onChange?(change)
    }

    private func setSyncHint(for moment: Moment, isDeleted: Bool) {
        let revision = (syncHints.first { $0.momentID == moment.id }?.revision ?? 0) + 1
        syncHints.removeAll { $0.momentID == moment.id }
        syncHints.append(MomentSyncHint(
            momentID: moment.id,
            isDeleted: isDeleted,
            sourceMessageID: moment.sourceMessageID,
            revision: revision
        ))
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
