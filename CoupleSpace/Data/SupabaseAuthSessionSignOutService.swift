import Supabase

@MainActor
protocol AuthSessionSignOutServing: AnyObject {
    func signOutCurrentSession() async throws
}

@MainActor
final class SupabaseAuthSessionSignOutService: AuthSessionSignOutServing {
    typealias CurrentRefreshToken = @MainActor () -> String?
    typealias SignOut = @MainActor (SignOutScope) async throws -> Void
    typealias RefreshSession = @MainActor (String) async throws -> Void

    private let currentRefreshToken: CurrentRefreshToken
    private let signOut: SignOut
    private let refreshSession: RefreshSession

    init(client: SupabaseClient) {
        currentRefreshToken = { client.auth.currentSession?.refreshToken }
        signOut = { try await client.auth.signOut(scope: $0) }
        refreshSession = { _ = try await client.auth.refreshSession(refreshToken: $0) }
    }

    init(
        currentRefreshToken: @escaping CurrentRefreshToken,
        signOut: @escaping SignOut,
        refreshSession: @escaping RefreshSession
    ) {
        self.currentRefreshToken = currentRefreshToken
        self.signOut = signOut
        self.refreshSession = refreshSession
    }

    func signOutCurrentSession() async throws {
        let priorRefreshToken = currentRefreshToken()
        var operationError: Error?

        do {
            try await signOut(.local)
        } catch {
            operationError = error
        }

        // supabase-swift can already have a refresh request in flight when
        // `.local` removes storage. Joining it prevents a late response from
        // restoring the session after logout; a final local sign-out removes
        // either that response or nothing when revocation already rejected it.
        if let priorRefreshToken {
            try? await refreshSession(priorRefreshToken)
        }

        do {
            try await signOut(.local)
        } catch {
            operationError = operationError ?? error
        }

        if let operationError {
            throw operationError
        }
    }

}
