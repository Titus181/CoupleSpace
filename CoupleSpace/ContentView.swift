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

    var body: some View {
        G1TechnicalSpikeView(supabaseClient: supabaseClient)
    }
}

#Preview {
    ContentView(supabaseClient: CoupleSpaceSupabaseClient.preview)
}
