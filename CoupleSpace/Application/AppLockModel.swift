import Combine
import Foundation
import LocalAuthentication

enum AppLockLifecyclePhase: Equatable {
    case active
    case inactive
    case background
}

enum AppLockAuthenticationResult: Equatable {
    case authenticated
    case unavailable
    case failed
}

@MainActor
protocol AppLockAuthenticating {
    func authenticate(reason: String) async -> AppLockAuthenticationResult
}

@MainActor
final class LocalDeviceAppLockAuthenticator: AppLockAuthenticating {
    func authenticate(reason: String) async -> AppLockAuthenticationResult {
        let context = LAContext()
        var evaluationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
            return .unavailable
        }

        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return .authenticated
        } catch {
            return .failed
        }
    }
}

@MainActor
final class AppLockModel: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isLocked: Bool
    @Published private(set) var isAuthenticating = false
    @Published private(set) var statusMessage: String?

    private let preferences: UserDefaults
    private let preferenceKey: String
    private let authenticator: AppLockAuthenticating

    init(
        preferences: UserDefaults = .standard,
        preferenceKey: String = "couplespace.app-lock-enabled",
        authenticator: AppLockAuthenticating? = nil,
        initiallyEnabled: Bool? = nil
    ) {
        self.preferences = preferences
        self.preferenceKey = preferenceKey
        self.authenticator = authenticator ?? LocalDeviceAppLockAuthenticator()
        let enabled = initiallyEnabled ?? preferences.bool(forKey: preferenceKey)
        isEnabled = enabled
        isLocked = enabled
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        preferences.set(enabled, forKey: preferenceKey)
        statusMessage = nil
        isLocked = enabled
    }

    func handleLifecyclePhase(_ phase: AppLockLifecyclePhase) async {
        guard isEnabled else { return }

        switch phase {
        case .inactive, .background:
            isLocked = true
            statusMessage = nil

        case .active:
            await unlockIfNeeded()
        }
    }

    func unlockIfNeeded() async {
        guard isEnabled, isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        statusMessage = nil
        let result = await authenticator.authenticate(reason: "解鎖 CoupleSpace 的私密內容")
        isAuthenticating = false

        switch result {
        case .authenticated:
            isLocked = false
        case .unavailable:
            statusMessage = "此裝置無法使用 Face ID 或裝置密碼解鎖。"
        case .failed:
            statusMessage = "尚未驗證，內容仍受保護。"
        }
    }
}
