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
        #expect(AppLaunchOptions(arguments: ["--ui-testing-pairing"]).isPairingUITesting)
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

    @Test func pairingInputAcceptsOnlyACompleteUUIDAndMapsExpectedServerOutcomes() {
        let token = "11111111-2222-4333-8444-555555555555"
        #expect(PairingInputPolicy.invitationToken(from: "  \(token)\n")?.uuidString.lowercased() == token)
        #expect(PairingInputPolicy.invitationToken(from: "11111111") == nil)
        #expect(PairingErrorMessage.message(serverMessage: "invitation_not_available").contains("已失效"))
        #expect(PairingErrorMessage.message(serverMessage: "participant_already_paired").contains("已有"))
    }

    @MainActor
    @Test func pairingModelCreatesAcceptsAndDeclinesWithoutInventingClientRelationships() async {
        let relationshipID = UUID(uuidString: "90000000-0000-4000-8000-000000000004")!
        let invitationToken = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let invitation = PairingInvitation(
            relationshipID: relationshipID,
            token: invitationToken,
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
        let service = PairingRemoteServiceFake(
            currentRelationship: nil,
            invitation: invitation,
            acceptedRelationshipID: relationshipID
        )
        let model = PairingModel(service: service)

        await model.refresh()
        #expect(model.state == .unpaired)

        await model.createOrRetryInvitation()
        #expect(model.state == .waiting(
            PairingRelationship(id: relationshipID, memberCount: 1),
            invitation: invitation
        ))

        await model.createOrRetryInvitation()
        #expect(model.statusMessage == "目前的邀請仍然有效。")

        await model.cancelInvitation()
        #expect(model.state == .unpaired)
        #expect(service.cancelInvitationCallCount == 1)

        await model.createOrRetryInvitation()

        await model.acceptInvitation(rawToken: invitation.code)
        #expect(model.state == .paired(PairingRelationship(id: relationshipID, memberCount: 2)))
        #expect(service.acceptedTokens == [invitationToken])

        model.resetForAuthenticatedSession()
        #expect(model.state == .checking)

        await model.declineInvitation(rawToken: invitation.code)
        #expect(model.state == .unpaired)
        #expect(service.declinedTokens == [invitationToken])
    }

    @MainActor
    @Test func pairingModelIgnoresAResponseFromThePreviousAuthenticatedSession() async {
        let service = SuspendedPairingRemoteServiceFake()
        let model = PairingModel(service: service)
        let oldSessionRefresh = Task { await model.refresh() }

        while service.currentRelationshipContinuation == nil {
            await Task.yield()
        }

        model.resetForAuthenticatedSession()
        service.resumeCurrentRelationship(
            PairingRelationship(id: UUID(), memberCount: 2)
        )
        await oldSessionRefresh.value

        #expect(model.state == .checking)
        #expect(model.isWorking == false)
    }
}

private final class PairingRemoteServiceFake: PairingRemoteServing {
    var currentRelationshipValue: PairingRelationship?
    let invitation: PairingInvitation
    let acceptedRelationshipID: UUID
    var acceptedTokens: [UUID] = []
    var declinedTokens: [UUID] = []
    var cancelInvitationCallCount = 0

    init(
        currentRelationship: PairingRelationship?,
        invitation: PairingInvitation,
        acceptedRelationshipID: UUID
    ) {
        currentRelationshipValue = currentRelationship
        self.invitation = invitation
        self.acceptedRelationshipID = acceptedRelationshipID
    }

    func currentRelationship() async throws -> PairingRelationship? {
        currentRelationshipValue
    }

    func createInvitation() async throws -> PairingInvitation {
        invitation
    }

    func acceptInvitation(token: UUID) async throws -> UUID {
        acceptedTokens.append(token)
        return acceptedRelationshipID
    }

    func declineInvitation(token: UUID) async throws {
        declinedTokens.append(token)
    }

    func cancelInvitation() async throws {
        cancelInvitationCallCount += 1
    }
}

private final class SuspendedPairingRemoteServiceFake: PairingRemoteServing {
    var currentRelationshipContinuation: CheckedContinuation<PairingRelationship?, Never>?

    func currentRelationship() async throws -> PairingRelationship? {
        await withCheckedContinuation { continuation in
            currentRelationshipContinuation = continuation
        }
    }

    func resumeCurrentRelationship(_ relationship: PairingRelationship?) {
        currentRelationshipContinuation?.resume(returning: relationship)
        currentRelationshipContinuation = nil
    }

    func createInvitation() async throws -> PairingInvitation {
        PairingInvitation(relationshipID: UUID(), token: UUID(), expiresAt: .now)
    }

    func acceptInvitation(token: UUID) async throws -> UUID {
        UUID()
    }

    func declineInvitation(token: UUID) async throws {}

    func cancelInvitation() async throws {}
}
