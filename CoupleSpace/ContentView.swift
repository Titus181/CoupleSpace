//
//  ContentView.swift
//  CoupleSpace
//
//  Created by titus on 2026/7/29.
//

import SwiftUI
import Supabase

struct ContentView: View {
#if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var authModel: SupabaseAppleAuthenticationModel
    @ObservedObject private var pairingModel: PairingModel
    private let supabaseClient: SupabaseClient
    @State private var isShowingLaunchAnimation: Bool
    @StateObject private var appLockModel = AppLockModel()
    private let bypassesAuthentication: Bool
    private let bypassesPairing: Bool

    init(
        authModel: SupabaseAppleAuthenticationModel,
        pairingModel: PairingModel,
        supabaseClient: SupabaseClient,
        showsLaunchAnimation: Bool = true,
        bypassesAuthentication: Bool = false,
        bypassesPairing: Bool = false
    ) {
        self.authModel = authModel
        self.pairingModel = pairingModel
        self.supabaseClient = supabaseClient
        _isShowingLaunchAnimation = State(initialValue: showsLaunchAnimation)
        self.bypassesAuthentication = bypassesAuthentication
        self.bypassesPairing = bypassesPairing
    }
#else
    init(
        authModel: SupabaseAppleAuthenticationModel,
        pairingModel: PairingModel,
        supabaseClient: SupabaseClient,
        showsLaunchAnimation: Bool = true,
        bypassesAuthentication: Bool = false,
        bypassesPairing: Bool = false
    ) {}
#endif

    var body: some View {
#if os(iOS)
        ZStack {
            AuthenticationGateView(
                authModel: authModel,
                pairingModel: pairingModel,
                supabaseClient: supabaseClient,
                bypassesAuthentication: bypassesAuthentication,
                bypassesPairing: bypassesPairing
            )
                .accessibilityIdentifier("main-content")
                .accessibilityHidden(isShowingLaunchAnimation)

            if appLockModel.isLocked {
                AppLockView(model: appLockModel)
                    .transition(.opacity)
                    .zIndex(2)
            }

            if isShowingLaunchAnimation {
                LaunchAnimationView {
                    withAnimation(.easeOut(duration: 0.15)) {
                        isShowingLaunchAnimation = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .environmentObject(appLockModel)
        .onChange(of: scenePhase) { _, phase in
            let lifecyclePhase: AppLockLifecyclePhase
            switch phase {
            case .active:
                lifecyclePhase = .active
            case .inactive:
                lifecyclePhase = .inactive
            case .background:
                lifecyclePhase = .background
            @unknown default:
                lifecyclePhase = .inactive
            }
            Task { await appLockModel.handleLifecyclePhase(lifecyclePhase) }
        }
#else
        RootTabView()
#endif
    }
}

#if os(iOS)
private struct AppLockView: View {
    @ObservedObject var model: AppLockModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34))
            Text("CoupleSpace 已鎖定")
                .font(.title3.weight(.semibold))
            Text("使用 Face ID 或裝置密碼繼續")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("解鎖") {
                Task { await model.unlockIfNeeded() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isAuthenticating)
            if let statusMessage = model.statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .accessibilityIdentifier("app-lock-screen")
    }
}
#endif

#Preview {
    ContentView(
        authModel: SupabaseAppleAuthenticationModel(client: CoupleSpaceSupabaseClient.preview),
        pairingModel: PairingModel(
            client: CoupleSpaceSupabaseClient.preview,
            initialState: .unpaired
        ),
        supabaseClient: CoupleSpaceSupabaseClient.preview,
        showsLaunchAnimation: false
    )
}
