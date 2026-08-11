//
//  ContentView.swift
//  CoupleSpace
//
//  Created by titus on 2026/7/29.
//

import SwiftUI

struct ContentView: View {
#if os(iOS)
    @ObservedObject private var authModel: SupabaseAppleAuthenticationModel
    @State private var isShowingLaunchAnimation: Bool
    private let bypassesAuthentication: Bool

    init(
        authModel: SupabaseAppleAuthenticationModel,
        showsLaunchAnimation: Bool = true,
        bypassesAuthentication: Bool = false
    ) {
        self.authModel = authModel
        _isShowingLaunchAnimation = State(initialValue: showsLaunchAnimation)
        self.bypassesAuthentication = bypassesAuthentication
    }
#else
    init(
        authModel: SupabaseAppleAuthenticationModel,
        showsLaunchAnimation: Bool = true,
        bypassesAuthentication: Bool = false
    ) {}
#endif

    var body: some View {
#if os(iOS)
        ZStack {
            AuthenticationGateView(
                authModel: authModel,
                bypassesAuthentication: bypassesAuthentication
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
        showsLaunchAnimation: false
    )
}
