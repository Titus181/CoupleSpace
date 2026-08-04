//
//  CoupleSpaceApp.swift
//  CoupleSpace
//
//  Created by titus on 2026/7/29.
//

import SwiftUI

@main
struct CoupleSpaceApp: App {
#if os(iOS)
    @UIApplicationDelegateAdaptor(CloudKitShareAppDelegate.self) private var appDelegate
#endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
