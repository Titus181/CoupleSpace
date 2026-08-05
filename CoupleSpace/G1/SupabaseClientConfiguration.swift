import Foundation
import Supabase

enum SupabaseConfigurationError: Error, Equatable {
    case missingURL
    case invalidURL
    case missingPublishableKey
    case invalidPublishableKey
}

struct SupabaseConfiguration: Equatable {
    let url: URL
    let publishableKey: String

    init(values: [String: Any]) throws {
        guard let rawURL = values["SupabaseURL"] as? String, !rawURL.isEmpty else {
            throw SupabaseConfigurationError.missingURL
        }
        guard let url = URL(string: rawURL),
              url.scheme == "https",
              url.host?.hasSuffix(".supabase.co") == true else {
            throw SupabaseConfigurationError.invalidURL
        }
        guard let publishableKey = values["SupabasePublishableKey"] as? String,
              !publishableKey.isEmpty else {
            throw SupabaseConfigurationError.missingPublishableKey
        }
        guard publishableKey.hasPrefix("sb_publishable_") else {
            throw SupabaseConfigurationError.invalidPublishableKey
        }

        self.url = url
        self.publishableKey = publishableKey
    }

    static func load(from bundle: Bundle = .main) throws -> SupabaseConfiguration {
        try SupabaseConfiguration(values: bundle.infoDictionary ?? [:])
    }
}

enum CoupleSpaceSupabaseClient {
    static func make(configuration: SupabaseConfiguration) -> SupabaseClient {
        SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
    }

    static var preview: SupabaseClient {
        SupabaseClient(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            supabaseKey: "sb_publishable_preview",
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
    }
}
