import Foundation
import Supabase

#if os(iOS)
import UIKit
import UserNotifications

struct APNsDeviceTokenValue: Equatable, Sendable {
    let hex: String

    init(_ data: Data) {
        hex = data.map { String(format: "%02x", $0) }.joined()
    }
}

private struct RegisterPushDeviceParameters: Encodable {
    let targetToken: String
    let targetEnvironment: String

    enum CodingKeys: String, CodingKey {
        case targetToken = "target_token"
        case targetEnvironment = "target_environment"
    }
}

enum BackgroundAppointmentReminderRefreshPolicy {
    static func requiresRefresh(userInfo: [AnyHashable: Any]) -> Bool {
        guard let eventKind = userInfo["event_kind"] as? String else { return false }
        return [
            "appointment_created",
            "appointment_updated",
            "appointment_cancelled",
        ].contains(eventKind)
    }
}

struct BackgroundAppointmentReminderContext: Equatable, Sendable {
    let userID: UUID
    let relationshipID: UUID
    let relationshipStatus: String

    var isActive: Bool {
        relationshipStatus == "active"
    }
}

@MainActor
struct BackgroundAppointmentReminderReconcileOrchestrator {
    private let initialContext: BackgroundAppointmentReminderContext
    private let fetchAppointments: @MainActor (
        BackgroundAppointmentReminderContext
    ) async throws -> [SharedAppointment]
    private let revalidatedContext: @MainActor () async throws
        -> BackgroundAppointmentReminderContext?
    private let reconcile: @MainActor (
        BackgroundAppointmentReminderContext,
        [SharedAppointment]
    ) async throws -> Void
    private let activateIfContextUnchanged: @MainActor () async -> Bool

    init(
        initialContext: BackgroundAppointmentReminderContext,
        fetchAppointments: @escaping @MainActor (
            BackgroundAppointmentReminderContext
        ) async throws -> [SharedAppointment],
        revalidatedContext: @escaping @MainActor () async throws
            -> BackgroundAppointmentReminderContext?,
        reconcile: @escaping @MainActor (
            BackgroundAppointmentReminderContext,
            [SharedAppointment]
        ) async throws -> Void,
        activateIfContextUnchanged: @escaping @MainActor () async -> Bool = { true }
    ) {
        self.initialContext = initialContext
        self.fetchAppointments = fetchAppointments
        self.revalidatedContext = revalidatedContext
        self.reconcile = reconcile
        self.activateIfContextUnchanged = activateIfContextUnchanged
    }

    func run() async throws -> Bool {
        guard initialContext.isActive else { return false }
        let appointments = try await fetchAppointments(initialContext)
        guard let currentContext = try await revalidatedContext(),
              currentContext.isActive,
              currentContext.userID == initialContext.userID,
              currentContext.relationshipID == initialContext.relationshipID
        else { return false }

        guard await activateIfContextUnchanged() else { return false }

        try await reconcile(currentContext, appointments)
        return true
    }
}

private struct BackgroundAppointmentRelationshipRow: Decodable {
    let id: UUID
    let status: String
}

@MainActor
final class PushNotificationPlatformAdapter {
    static let shared = PushNotificationPlatformAdapter()

    private var client: SupabaseClient?
    private var pendingDeviceToken: Data?

    private init() {}

    static func configure(client: SupabaseClient) {
        shared.client = client
    }

    func requestAuthorizationAndRegister() async {
        do {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            let isAuthorized: Bool
            if settings.authorizationStatus == .notDetermined {
                isAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } else {
                isAuthorized = settings.authorizationStatus == .authorized
            }
            guard isAuthorized else { return }
            UIApplication.shared.registerForRemoteNotifications()
        } catch {}
    }

    func receive(deviceToken: Data) async {
        guard !deviceToken.isEmpty else { return }
        pendingDeviceToken = deviceToken
        await registerPendingDeviceToken()
    }

    func refreshAfterNotificationInteraction() {
        NotificationCenter.default.post(name: .coupleSpaceDidRequestSecureRefresh, object: nil)
    }

    func reconcileAppointmentRemindersAfterBackgroundPush(
        userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard BackgroundAppointmentReminderRefreshPolicy.requiresRefresh(userInfo: userInfo),
              let client else { return .noData }
        do {
            let session = try await client.auth.session
            guard let relationship = try RelationshipSnapshotStore().load(userID: session.user.id),
                  relationship.status == "active"
            else {
                return .noData
            }
            let initialContext = BackgroundAppointmentReminderContext(
                userID: session.user.id,
                relationshipID: relationship.relationshipID,
                relationshipStatus: relationship.status
            )
            let reminderScheduler = LocalSharedAppointmentReminderScheduler(
                relationshipID: relationship.relationshipID
            )
            let reminderLifecycleGeneration = await reminderScheduler.lifecycleGeneration()
            let orchestrator = BackgroundAppointmentReminderReconcileOrchestrator(
                initialContext: initialContext,
                fetchAppointments: { context in
                    try await SupabaseSharedAppointmentService(
                        client: client,
                        currentUserID: context.userID,
                        relationshipID: context.relationshipID
                    ).fetchAppointmentsWithoutUpdatingSnapshot()
                },
                revalidatedContext: {
                    try await self.revalidatedAppointmentReminderContext(
                        client: client,
                        expectedContext: initialContext
                    )
                },
                reconcile: { context, appointments in
                    guard context.relationshipID == relationship.relationshipID else { return }
                    try await reminderScheduler.reconcile(appointments)
                },
                activateIfContextUnchanged: {
                    await reminderScheduler.activate(
                        ifLifecycleGenerationMatches: reminderLifecycleGeneration
                    )
                }
            )
            let didReconcile = try await orchestrator.run()
            return didReconcile ? .newData : .noData
        } catch {
            return .failed
        }
    }

    private func revalidatedAppointmentReminderContext(
        client: SupabaseClient,
        expectedContext: BackgroundAppointmentReminderContext
    ) async throws -> BackgroundAppointmentReminderContext? {
        guard self.client === client else { return nil }
        let sessionBeforeQuery = try await client.auth.session
        guard sessionBeforeQuery.user.id == expectedContext.userID else { return nil }

        let relationships: [BackgroundAppointmentRelationshipRow] = try await client
            .from("relationships")
            .select("id,status")
            .eq("id", value: expectedContext.relationshipID)
            .eq("status", value: "active")
            .limit(1)
            .execute()
            .value

        let sessionAfterQuery = try await client.auth.session
        guard self.client === client,
              sessionAfterQuery.user.id == expectedContext.userID,
              let relationship = relationships.first
        else { return nil }
        return BackgroundAppointmentReminderContext(
            userID: sessionAfterQuery.user.id,
            relationshipID: relationship.id,
            relationshipStatus: relationship.status
        )
    }

    private func registerPendingDeviceToken() async {
        guard let client, let pendingDeviceToken else { return }
        do {
            _ = try await client.auth.session
            let _: UUID = try await client.rpc(
                "register_push_device",
                params: RegisterPushDeviceParameters(
                    targetToken: APNsDeviceTokenValue(pendingDeviceToken).hex,
                    targetEnvironment: pushEnvironment
                )
            ).execute().value
            self.pendingDeviceToken = nil
        } catch {
            // Keep the token in memory for the next authenticated activation.
        }
    }

    private var pushEnvironment: String {
#if DEBUG
        "sandbox"
#else
        "production"
#endif
    }
}

extension Notification.Name {
    static let coupleSpaceDidRequestSecureRefresh = Notification.Name(
        "CoupleSpace.didRequestSecureRefresh"
    )
}
#endif
