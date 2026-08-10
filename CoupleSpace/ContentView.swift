//
//  ContentView.swift
//  CoupleSpace
//
//  Created by titus on 2026/7/29.
//

import SwiftUI
import Supabase

struct ContentView: View {
    let supabaseClient: SupabaseClient

#if os(iOS)
    @State private var isShowingLaunchAnimation = true
#endif

    var body: some View {
#if os(iOS)
        ZStack {
            G1TechnicalSpikeView(supabaseClient: supabaseClient)
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
        G1TechnicalSpikeView(supabaseClient: supabaseClient)
#endif
    }
}

#Preview {
    ContentView(supabaseClient: CoupleSpaceSupabaseClient.preview)
}
