//
//  CoupleSpaceApp.swift
//  CoupleSpace
//
//  Created by titus on 2026/7/29.
//

import SwiftUI
import Supabase

@main
struct CoupleSpaceApp: App {
#if os(iOS)
    @UIApplicationDelegateAdaptor(CloudKitShareAppDelegate.self) private var appDelegate
#endif
    private let supabaseClient: SupabaseClient
    private let launchOptions: AppLaunchOptions

    init() {
        launchOptions = .current

        do {
            let configuration = try AppConfiguration.load()
            supabaseClient = CoupleSpaceSupabaseClient.make(configuration: configuration.supabase)
        } catch {
            fatalError("App configuration is missing or invalid")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(showsLaunchAnimation: !launchOptions.isUITesting)
        }
    }
}
