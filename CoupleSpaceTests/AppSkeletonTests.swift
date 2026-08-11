import Foundation
import Testing
#if os(iOS)
import UIKit
#endif
@testable import CoupleSpace

struct AppSkeletonTests {
    @Test func uiTestingLaunchOptionIsExplicitAndOrderIndependent() {
        #expect(AppLaunchOptions(arguments: []).isUITesting == false)
        #expect(AppLaunchOptions(arguments: ["--other", "--ui-testing"]).isUITesting)
    }

#if os(iOS)
    @Test func systemAndInAppLaunchBackgroundShareTheNamedAsset() {
        let launchScreen = Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen") as? [String: Any]

        #expect(launchScreen?["UIColorName"] as? String == "LaunchBackground")
        #expect(UIColor(named: "LaunchBackground", in: .main, compatibleWith: nil) != nil)
    }
#endif

    @Test func appConfigurationLoadsExplicitRuntimeAndSupabaseSettings() throws {
        let configuration = try AppConfiguration(values: [
            "AppEnvironment": "test",
            "SupabaseURL": "https://example.supabase.co",
            "SupabasePublishableKey": "sb_publishable_test",
        ])

        #expect(configuration.runtimeEnvironment == .test)
        #expect(configuration.supabase.url == URL(string: "https://example.supabase.co"))
    }

    @Test func appConfigurationRejectsUnknownRuntimeEnvironment() {
        #expect(throws: AppConfigurationError.invalidRuntimeEnvironment) {
            try AppConfiguration(values: [
                "AppEnvironment": "unknown",
                "SupabaseURL": "https://example.supabase.co",
                "SupabasePublishableKey": "sb_publishable_test",
            ])
        }
    }

    @Test func primarySectionsStayInAcceptedOrderAndOpenOnToday() {
        #expect(PrimarySection.allCases == [.today, .conversation, .us])
        #expect(PrimarySection.defaultSelection == .today)
    }

    @Test func authenticationStateDistinguishesRestoreCancelFailureAndSignOut() {
        if case .checking = AuthenticationState.checking.phase {} else {
            Issue.record("The initial authentication state should restore the session first.")
        }

        let cancelled = AuthenticationState.signedOut(message: "已取消登入")
        if case .signedOut = cancelled.phase {} else {
            Issue.record("Cancellation should return to the signed-out state.")
        }
        #expect(cancelled.isSignedIn == false)
        #expect(cancelled.message == "已取消登入")

        let userID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let signedIn = AuthenticationState.signedIn(userID: userID)
        if case .signedIn = signedIn.phase {} else {
            Issue.record("A valid session should enter the signed-in state.")
        }
        #expect(signedIn.isSignedIn)
        #expect(signedIn.userToken == "aaaaaaaa")

        let signingOut = signedIn.signingOut()
        if case .signingOut = signingOut.phase {} else {
            Issue.record("Sign-out should have an explicit in-progress state.")
        }
        #expect(signingOut.isSignedIn)

        let restored = signedIn.restoringAfterSignOutFailure()
        if case .signedIn = restored.phase {} else {
            Issue.record("A failed sign-out must preserve the valid signed-in session.")
        }
        #expect(restored.isSignedIn)
        #expect(restored.message == "登出失敗，請稍後再試。")
    }

    @Test func appleSignInStartsOnlyWhenNetworkIsAvailableAndNoRequestIsPending() {
        #expect(AuthenticationStartPolicy.canStartSignIn(
            phase: .signedOut,
            networkState: .available
        ))
        #expect(AuthenticationStartPolicy.canStartSignIn(
            phase: .signedOut,
            networkState: .unknown
        ) == false)
        #expect(AuthenticationStartPolicy.canStartSignIn(
            phase: .signedOut,
            networkState: .unavailable
        ) == false)
        #expect(AuthenticationStartPolicy.canStartSignIn(
            phase: .signingIn,
            networkState: .available
        ) == false)
    }
}
