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
    let targetContentPreviewEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case targetToken = "target_token"
        case targetEnvironment = "target_environment"
        case targetContentPreviewEnabled = "target_content_preview_enabled"
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

@MainActor
final class PushNotificationPlatformAdapter {
    static let shared = PushNotificationPlatformAdapter()

    private var client: SupabaseClient?
    private var pendingDeviceToken: Data?
    private var registeredDeviceToken: Data?
    private let contentPreviewDefaultsKey = "push-content-preview-enabled"

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
        registeredDeviceToken = deviceToken
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
            guard let relationship = try RelationshipSnapshotStore().load(userID: session.user.id) else {
                return .noData
            }
            let service = SupabaseSharedAppointmentService(
                client: client,
                currentUserID: session.user.id,
                relationshipID: relationship.relationshipID
            )
            let appointments = try await service.fetchAppointments()
            try await LocalSharedAppointmentReminderScheduler(
                relationshipID: relationship.relationshipID
            ).reconcile(appointments)
            return .newData
        } catch {
            return .failed
        }
    }

    func setContentPreviewEnabled(_ isEnabled: Bool) async {
        UserDefaults.standard.set(isEnabled, forKey: contentPreviewDefaultsKey)
        if pendingDeviceToken == nil { pendingDeviceToken = registeredDeviceToken }
        await registerPendingDeviceToken()
    }

    private func registerPendingDeviceToken() async {
        guard let client, let pendingDeviceToken else { return }
        do {
            _ = try await client.auth.session
            let _: UUID = try await client.rpc(
                "register_push_device",
                params: RegisterPushDeviceParameters(
                    targetToken: APNsDeviceTokenValue(pendingDeviceToken).hex,
                    targetEnvironment: pushEnvironment,
                    targetContentPreviewEnabled: UserDefaults.standard.bool(forKey: contentPreviewDefaultsKey)
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
