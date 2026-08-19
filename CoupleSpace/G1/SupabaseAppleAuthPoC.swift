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

enum AuthenticationPhase {
    case checking
    case signedOut
    case signingIn
    case signedIn
    case signingOut
}

struct AuthenticationStartPolicy {
    static func canStartSignIn(
        phase: AuthenticationPhase,
        networkState: NetworkReachabilityState
    ) -> Bool {
        guard networkState == .available else { return false }
        if case .signingIn = phase { return false }
        return true
    }
}

struct AuthenticationState {
    let phase: AuthenticationPhase
    let message: String
    let userID: UUID?
    let userToken: String?

    static let checking = AuthenticationState(
        phase: .checking,
        message: "正在確認登入狀態…",
        userID: nil,
        userToken: nil
    )

    static func signedOut(message: String = "使用 Apple 登入，進入只屬於你們的空間。") -> Self {
        AuthenticationState(phase: .signedOut, message: message, userID: nil, userToken: nil)
    }

    static let signingIn = AuthenticationState(
        phase: .signingIn,
        message: "正在登入…",
        userID: nil,
        userToken: nil
    )

    static func signedIn(userID: UUID, message: String = "已登入") -> Self {
        AuthenticationState(
            phase: .signedIn,
            message: message,
            userID: userID,
            userToken: String(userID.uuidString.lowercased().prefix(8))
        )
    }

    func signingOut() -> Self {
        AuthenticationState(
            phase: .signingOut,
            message: "正在登出…",
            userID: userID,
            userToken: userToken
        )
    }

    var isSignedIn: Bool {
        phase == .signedIn || phase == .signingOut
    }
}

@MainActor
final class SupabaseAppleAuthenticationModel: ObservableObject {
    @Published private(set) var state: AuthenticationState

    var status: String { state.message }
    var userToken: String { state.userToken ?? "尚未登入" }
    var isSignedIn: Bool { state.isSignedIn }

    private let client: SupabaseClient
    private let sessionSignOutService: AuthSessionSignOutServing
    private let currentSession: () -> Session?
    private var rawNonce: String?
    private var activeSignOutOperationID: UUID?
    private var currentSessionSignOutOperationID: UUID?

    init(
        client: SupabaseClient,
        sessionSignOutService: AuthSessionSignOutServing? = nil,
        initialState: AuthenticationState = .checking,
        currentSession: (() -> Session?)? = nil
    ) {
        self.client = client
        self.sessionSignOutService = sessionSignOutService
            ?? SupabaseAuthSessionSignOutService(client: client)
        self.currentSession = currentSession ?? { client.auth.currentSession }
        state = initialState
    }

    func observeAuthState() async {
        for await (_, session) in client.auth.authStateChanges {
            guard !Task.isCancelled else { return }
            reconcileObservedSession(session)
        }
    }

    func prepare(request: ASAuthorizationAppleIDRequest) {
        do {
            let nonce = try AppleSignInNonce.make()
            rawNonce = nonce
            request.nonce = AppleSignInNonce.hash(nonce)
            request.requestedScopes = []
            state = AuthenticationState(
                phase: .signingIn,
                message: "等待 Apple 驗證…",
                userID: nil,
                userToken: nil
            )
        } catch {
            rawNonce = nil
            state = .signedOut(message: "無法建立 Apple 登入請求，請再試一次。")
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
                state = .signedOut(message: "Apple 未提供可用的登入憑證，請再試一次。")
                return
            }

            rawNonce = nil
            state = .signingIn
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
                    state = .signedOut(message: "登入失敗，請確認網路後再試一次。")
                }
            }

        case let .failure(error):
            rawNonce = nil
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                state = .signedOut(message: "已取消登入，你可以隨時再試。")
            } else {
                state = .signedOut(message: "Apple 登入未完成，請再試一次。")
            }
        }
    }

    func signOut() async {
        guard activeSignOutOperationID == nil, state.isSignedIn else { return }
        let operationID = UUID()
        activeSignOutOperationID = operationID
        currentSessionSignOutOperationID = operationID
        defer {
            if activeSignOutOperationID == operationID {
                activeSignOutOperationID = nil
            }
            if currentSessionSignOutOperationID == operationID {
                currentSessionSignOutOperationID = nil
            }
        }

        let signedInUserID = state.userID
        state = state.signingOut()
        try? await sessionSignOutService.signOutCurrentSession()
        await clearLocalAuthenticatedState(userID: signedInUserID)

        guard currentSessionSignOutOperationID == operationID else { return }
        currentSessionSignOutOperationID = nil
        apply(session: nil)
    }

    func reconcileObservedSession(_ session: Session?) {
        guard currentSessionSignOutOperationID == nil else { return }

        // Auth events are asynchronous and can be queued behind a completed
        // logout. Only accept an event that still matches SDK storage so a
        // late tokenRefreshed/signedOut event cannot resurrect or erase a
        // newer local truth.
        switch (session, currentSession()) {
        case (nil, nil):
            apply(session: nil)
        case let (observedSession?, currentSession?)
            where observedSession.accessToken == currentSession.accessToken:
            apply(session: observedSession)
        default:
            break
        }
    }

    private func clearLocalAuthenticatedState(userID: UUID?) async {
        if let userID {
            if let relationship = try? RelationshipSnapshotStore().load(userID: userID) {
                await LocalSharedAppointmentReminderScheduler(
                    relationshipID: relationship.relationshipID
                ).removeAll()
            }
            ConversationSnapshotStore().clearAll(userID: userID)
            ConversationPhotoCacheStore().clearAll(userID: userID)
            TodaySnapshotStore().clearAll(userID: userID)
            SharedAppointmentSnapshotStore().clearAll(userID: userID)
            // Keep the user-scoped relationship identity and mixed outbox so a
            // partially uploaded chat photo can be retried or reconciled on sign-in.
        }
    }

    private func apply(session: Session?) {
        let decision = SupabaseSessionPolicy.decision(
            hasSession: session != nil,
            isExpired: session?.isExpired ?? false
        )

        switch decision {
        case .signedOut:
            state = .signedOut()

        case .refreshingExpiredSession:
            state = AuthenticationState(
                phase: .checking,
                message: "正在更新登入狀態…",
                userID: nil,
                userToken: nil
            )

        case .signedIn:
            guard let session else { return }
            state = .signedIn(userID: session.user.id)
        }
    }
}
