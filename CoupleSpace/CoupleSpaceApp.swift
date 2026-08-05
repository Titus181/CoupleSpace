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

    init() {
        do {
            let configuration = try SupabaseConfiguration.load()
            supabaseClient = CoupleSpaceSupabaseClient.make(configuration: configuration)
        } catch {
            fatalError("Supabase client configuration is missing or invalid")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(supabaseClient: supabaseClient)
        }
    }
}
