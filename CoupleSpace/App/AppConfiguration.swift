import Foundation

enum AppRuntimeEnvironment: String, Equatable {
    case development
    case test
    case production
}

enum AppConfigurationError: Error, Equatable {
    case missingRuntimeEnvironment
    case invalidRuntimeEnvironment
}

struct AppConfiguration {
    let runtimeEnvironment: AppRuntimeEnvironment
    let supabase: SupabaseConfiguration

    init(values: [String: Any]) throws {
        guard let rawEnvironment = values["AppEnvironment"] as? String,
              !rawEnvironment.isEmpty else {
            throw AppConfigurationError.missingRuntimeEnvironment
        }
        guard let runtimeEnvironment = AppRuntimeEnvironment(rawValue: rawEnvironment) else {
            throw AppConfigurationError.invalidRuntimeEnvironment
        }

        self.runtimeEnvironment = runtimeEnvironment
        supabase = try SupabaseConfiguration(values: values)
    }

    static func load(from bundle: Bundle = .main) throws -> AppConfiguration {
        try AppConfiguration(values: bundle.infoDictionary ?? [:])
    }
}
