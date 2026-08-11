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

    @Test func momentDraftNormalizesShortTextAndRejectsInvalidContent() {
        #expect(MomentDraftPolicy.normalizedText("  想到你  ") == "想到你")
        #expect(MomentDraftPolicy.normalizedText(" \n\t ") == nil)
        #expect(MomentDraftPolicy.normalizedText(
            String(repeating: "a", count: MomentDraftPolicy.maximumTextLength + 1)
        ) == nil)
        #expect(MomentMood.allCases.map(\.rawValue) == [
            "calm", "happy", "tired", "thinking_of_you", "need_hug",
        ])
    }

    @MainActor
    @Test func momentModelLoadsCreatesAndRefreshesFromRemoteChanges() async throws {
        let first = Moment(
            id: UUID(uuidString: "B1000000-0000-0000-0000-000000000001")!,
            creatorUserID: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
            content: .mood(.calm),
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let service = MomentRemoteServiceFake(moments: [first])
        let model = MomentModel(service: service)

        #expect(model.authorLabel(for: first) == "留下者未確認")
        await model.start()
        #expect(model.moments == [first])
        #expect(model.authorLabel(for: first) == "你留下的")
        #expect(service.isObserving)

        #expect(await model.create(.text("  今天看到漂亮的天空  ")))
        #expect(model.moments.first?.content == .text("今天看到漂亮的天空"))
        #expect(service.createdDrafts == [.text("  今天看到漂亮的天空  ")])

        let partnerMoment = Moment(
            id: UUID(uuidString: "B1000000-0000-0000-0000-000000000003")!,
            creatorUserID: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
            content: .mood(.happy),
            createdAt: Date(timeIntervalSince1970: 300)
        )
        service.moments.insert(partnerMoment, at: 0)
        await service.sendChange()
        #expect(model.moments.first == partnerMoment)
        #expect(model.authorLabel(for: partnerMoment) == "對方留下的")

        await model.stop()
        #expect(!service.isObserving)
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

@MainActor
private final class MomentRemoteServiceFake: MomentRemoteServing {
    private let userID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
    var moments: [Moment]
    var createdDrafts: [MomentDraft] = []
    var isObserving = false
    private var onChange: (@MainActor () async -> Void)?

    init(moments: [Moment]) {
        self.moments = moments
    }

    func currentUserID() async throws -> UUID { userID }

    func fetchMoments() async throws -> [Moment] { moments }

    func createMoment(_ draft: MomentDraft, clientID: UUID) async throws -> Moment {
        createdDrafts.append(draft)
        let content: MomentContent
        switch draft {
        case let .mood(mood): content = .mood(mood)
        case let .text(value):
            content = .text(try #require(MomentDraftPolicy.normalizedText(value)))
        case .photo: content = .photo
        }
        let moment = Moment(
            id: clientID,
            creatorUserID: userID,
            content: content,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        moments.insert(moment, at: 0)
        return moment
    }

    func photoData(for momentID: UUID) async throws -> Data { Data() }

    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws {
        isObserving = true
        self.onChange = onChange
    }

    func stopObservingChanges() async {
        isObserving = false
        onChange = nil
    }

    func sendChange() async {
        await onChange?()
    }
}
