import AuthenticationServices
import Supabase
import SwiftUI

struct AuthenticationGateView: View {
    @ObservedObject var authModel: SupabaseAppleAuthenticationModel
    @ObservedObject var pairingModel: PairingModel
    let supabaseClient: SupabaseClient
    let bypassesAuthentication: Bool
    let bypassesPairing: Bool

    var body: some View {
        Group {
            if bypassesAuthentication {
                if bypassesPairing {
                    RootTabView(technicalValidationClient: supabaseClient)
                } else {
                    PairingGateView(
                        model: pairingModel,
                        supabaseClient: supabaseClient,
                        accountUserID: nil,
                        accountUserToken: nil,
                        accountStatusMessage: nil,
                        onSignOut: {}
                    )
                }
            } else {
                switch authModel.state.phase {
                case .checking:
                    ProgressView(authModel.state.message)
                        .accessibilityIdentifier("authentication-checking")

                case .signedOut, .signingIn:
                    SignInView(authModel: authModel)

                case .signedIn, .signingOut:
                    PairingGateView(
                        model: pairingModel,
                        supabaseClient: supabaseClient,
                        accountUserID: authModel.state.userID,
                        accountUserToken: authModel.state.userToken,
                        accountStatusMessage: authModel.state.message == "已登入"
                            ? nil
                            : authModel.state.message
                    ) {
                        Task { await authModel.signOut() }
                    }
                }
            }
        }
        .task {
            guard !bypassesAuthentication else { return }
            await authModel.observeAuthState()
        }
        .task(id: authModel.state.userID) {
            guard !bypassesAuthentication,
                  authModel.state.isSignedIn,
                  let userID = authModel.state.userID
            else { return }
            pairingModel.resetForAuthenticatedSession()
            await pairingModel.refreshForAuthenticatedSession(userID: userID)
        }
    }
}

private struct SignInView: View {
    @ObservedObject var authModel: SupabaseAppleAuthenticationModel
    @StateObject private var networkMonitor = NetworkRecoveryMonitor()

    private var canStartSignIn: Bool {
        AuthenticationStartPolicy.canStartSignIn(
            phase: authModel.state.phase,
            networkState: networkMonitor.state
        )
    }

    private var statusMessage: String {
        switch networkMonitor.state {
        case .unknown:
            return "正在確認網路連線…"
        case .unavailable:
            return "目前沒有網路連線，連線後再試。"
        case .available:
            return authModel.state.message
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "rectangle.inset.filled.and.person.filled")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("歡迎來到 CoupleSpace")
                    .font(.title2.weight(.semibold))
                Text("再忙，也能每天留一點位置給彼此。")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            SignInWithAppleButton(
                .signIn,
                onRequest: authModel.prepare,
                onCompletion: authModel.complete
            )
            .signInWithAppleButtonStyle(.black)
            .frame(maxWidth: 320)
            .frame(height: 50)
            .disabled(!canStartSignIn)
            .accessibilityIdentifier("sign-in-with-apple")

            Text(statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("authentication-status")

            Spacer()
        }
        .padding(32)
        .accessibilityIdentifier("sign-in-screen")
        .task {
            networkMonitor.start()
        }
    }
}
