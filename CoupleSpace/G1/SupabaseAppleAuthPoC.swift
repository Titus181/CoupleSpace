import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security
import Supabase

enum AppleSignInNonceError: Error {
    case randomGenerationFailed
}

enum AppleSignInNonce {
    private static let characters = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
    )

    static func make(length: Int = 32) throws -> String {
        var result = ""
        result.reserveCapacity(length)

        while result.count < length {
            var random: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &random) == errSecSuccess else {
                throw AppleSignInNonceError.randomGenerationFailed
            }

            let unbiasedLimit = 256 - (256 % characters.count)
            guard Int(random) < unbiasedLimit else { continue }
            result.append(characters[Int(random) % characters.count])
        }

        return result
    }

    static func hash(_ nonce: String) -> String {
        SHA256.hash(data: Data(nonce.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

@MainActor
final class SupabaseAppleAuthPoC: ObservableObject {
    @Published private(set) var status = "正在檢查 Supabase 登入狀態…"
    @Published private(set) var userToken = "尚未登入"
    @Published private(set) var isSignedIn = false

    private let client: SupabaseClient
    private var rawNonce: String?

    init(client: SupabaseClient) {
        self.client = client
    }

    func observeAuthState() async {
        for await (_, session) in client.auth.authStateChanges {
            guard !Task.isCancelled else { return }
            apply(session: session)
        }
    }

    func prepare(request: ASAuthorizationAppleIDRequest) {
        do {
            let nonce = try AppleSignInNonce.make()
            rawNonce = nonce
            request.nonce = AppleSignInNonce.hash(nonce)
            request.requestedScopes = []
            status = "等待 Apple 驗證…"
        } catch {
            rawNonce = nil
            status = "無法建立 Apple 登入請求"
        }
    }

    func complete(result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = rawNonce
            else {
                rawNonce = nil
                status = "Apple 未提供可用的登入憑證"
                return
            }

            rawNonce = nil
            status = "正在建立 Supabase session…"
            Task {
                do {
                    let session = try await client.auth.signInWithIdToken(
                        credentials: OpenIDConnectCredentials(
                            provider: .apple,
                            idToken: idToken,
                            nonce: nonce
                        )
                    )
                    apply(session: session)
                } catch {
                    status = "Supabase Apple 登入失敗，請檢查 Provider 設定"
                }
            }

        case let .failure(error):
            rawNonce = nil
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                status = "已取消 Apple 登入"
            } else {
                status = "Apple 登入未完成"
            }
        }
    }

    func signOut() async {
        do {
            try await client.auth.signOut()
            apply(session: nil)
        } catch {
            status = "登出失敗，請稍後再試"
        }
    }

    private func apply(session: Session?) {
        let decision = SupabaseSessionPolicy.decision(
            hasSession: session != nil,
            isExpired: session?.isExpired ?? false
        )

        switch decision {
        case .signedOut:
            status = "尚未登入 Supabase"
            userToken = "尚未登入"
            isSignedIn = false

        case .refreshingExpiredSession:
            status = "已載入過期 session，正在等待更新…"
            userToken = "尚未登入"
            isSignedIn = false

        case .signedIn:
            guard let session else { return }
            status = "Supabase Apple 登入可用"
            userToken = String(session.user.id.uuidString.lowercased().prefix(8))
            isSignedIn = true
        }
    }
}
