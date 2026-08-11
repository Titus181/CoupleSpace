//
//  ContentView.swift
//  CoupleSpace
//
//  Created by titus on 2026/7/29.
//

import SwiftUI

struct ContentView: View {
#if os(iOS)
    @State private var isShowingLaunchAnimation = true
#endif

    var body: some View {
#if os(iOS)
        ZStack {
            RootTabView()
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
    ContentView()
}
