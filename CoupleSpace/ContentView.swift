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
    @ObservedObject private var authModel: SupabaseAppleAuthenticationModel
    @ObservedObject private var pairingModel: PairingModel
    private let supabaseClient: SupabaseClient
    @State private var isShowingLaunchAnimation: Bool
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
#else
        RootTabView()
#endif
    }
}

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
