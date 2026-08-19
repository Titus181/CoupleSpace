import Combine
import Foundation

@MainActor
final class OtherSessionsSignOutModel: ObservableObject {
    static let successMessage =
        "已送出登出其他登入。其他裝置在下次驗證時需要重新登入；已簽發的存取權杖可能在到期前短暫有效。"
    static let failureMessage = "無法登出其他登入，請確認網路後再試。"

    @Published private(set) var isWorking = false
    @Published private(set) var statusMessage: String?

    func signOutOtherSessions(
        operation: () async throws -> Void
    ) async {
        guard !isWorking else { return }

        isWorking = true
        statusMessage = nil
        defer { isWorking = false }

        do {
            try await operation()
            statusMessage = Self.successMessage
        } catch {
            statusMessage = Self.failureMessage
        }
    }
}
