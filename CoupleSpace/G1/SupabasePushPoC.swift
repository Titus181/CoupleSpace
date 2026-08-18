import Combine
import CryptoKit
import Foundation
import Supabase

#if os(iOS)
import UIKit
import UserNotifications

extension Notification.Name {
    static let coupleSpaceDidRegisterForRemoteNotifications = Notification.Name(
        "CoupleSpace.didRegisterForRemoteNotifications"
    )
    static let coupleSpaceDidFailToRegisterForRemoteNotifications = Notification.Name(
        "CoupleSpace.didFailToRegisterForRemoteNotifications"
    )
}

struct APNsDeviceTokenValue: Equatable {
    let hex: String
    let fingerprint: String

    init(_ data: Data) {
        hex = data.map { String(format: "%02x", $0) }.joined()
        fingerprint = SHA256.hash(data: data)
            .prefix(4)
            .map { String(format: "%02x", $0) }
            .joined()
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
final class SupabasePushPoC: ObservableObject {
    @Published private(set) var status = "尚未要求推播權限"
    @Published private(set) var tokenFingerprint = "尚無 token"
    @Published private(set) var isWorking = false

    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func requestAuthorizationAndRegister() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                status = "使用者未允許推播通知"
                return
            }

            status = "已允許通知；等待 APNs device token"
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            status = "推播權限要求失敗：\(error.localizedDescription)"
        }
    }

    func register(deviceToken data: Data) async {
        guard !data.isEmpty else {
            status = "APNs 回傳空白 device token"
            return
        }

        let token = APNsDeviceTokenValue(data)
        tokenFingerprint = token.fingerprint
        status = "正在向 Supabase 登記 token…"

        do {
            _ = try await client.auth.session
            let _: UUID = try await client
                .rpc(
                    "register_push_device",
                    params: RegisterPushDeviceParameters(
                        targetToken: token.hex,
                        targetEnvironment: pushEnvironment
                    )
                )
                .execute()
                .value
            status = "APNs token 已登記（\(pushEnvironment)）"
        } catch {
            status = "APNs token 登記失敗：\(error.localizedDescription)"
        }
    }

    func reportRegistrationFailure(_ error: Error) {
        status = "APNs token 取得失敗：\(error.localizedDescription)"
    }

    func clearSession() {
        status = "尚未要求推播權限"
        tokenFingerprint = "尚無 token"
        isWorking = false
    }

    private var pushEnvironment: String {
#if DEBUG
        "sandbox"
#else
        "production"
#endif
    }
}
#endif
