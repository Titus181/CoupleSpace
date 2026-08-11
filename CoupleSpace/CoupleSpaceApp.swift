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
    @StateObject private var authModel: SupabaseAppleAuthenticationModel
    @StateObject private var pairingModel: PairingModel

    init() {
        let options = AppLaunchOptions.current
        launchOptions = options

        do {
            let configuration = try AppConfiguration.load()
            let client = CoupleSpaceSupabaseClient.make(configuration: configuration.supabase)
            supabaseClient = client
            _authModel = StateObject(
                wrappedValue: SupabaseAppleAuthenticationModel(client: client)
            )
            _pairingModel = StateObject(
                wrappedValue: PairingModel(
                    client: client,
                    initialState: options.isPairingUITesting ? .unpaired : .checking
                )
            )
        } catch {
            fatalError("App configuration is missing or invalid")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                authModel: authModel,
                pairingModel: pairingModel,
                supabaseClient: supabaseClient,
                showsLaunchAnimation: !launchOptions.isUITesting,
                bypassesAuthentication: launchOptions.isUITesting,
                bypassesPairing: launchOptions.isUITesting && !launchOptions.isPairingUITesting
            )
        }
    }
}
