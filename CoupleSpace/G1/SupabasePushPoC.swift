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
