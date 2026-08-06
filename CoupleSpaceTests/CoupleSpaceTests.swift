//
//  CoupleSpaceTests.swift
//  CoupleSpaceTests
//
//  Created by titus on 2026/7/29.
//

import Foundation
import Testing
@testable import CoupleSpace

@MainActor
struct CoupleSpaceTests {

    @Test func supabaseConfigurationAcceptsProjectURLAndPublishableKey() throws {
        let configuration = try SupabaseConfiguration(values: [
            "SupabaseURL": "https://example.supabase.co",
            "SupabasePublishableKey": "sb_publishable_test",
        ])

        #expect(configuration.url == URL(string: "https://example.supabase.co"))
        #expect(configuration.publishableKey == "sb_publishable_test")
    }

    @Test func supabaseConfigurationRejectsUnresolvedBuildSetting() {
        #expect(throws: SupabaseConfigurationError.invalidPublishableKey) {
            try SupabaseConfiguration(values: [
                "SupabaseURL": "https://example.supabase.co",
                "SupabasePublishableKey": "$(SUPABASE_PUBLISHABLE_KEY)",
            ])
        }
    }

    @Test func expiredSupabaseSessionIsNotAcceptedAsSignedIn() {
        #expect(SupabaseSessionPolicy.decision(
            hasSession: false,
            isExpired: false
        ) == .signedOut)
        #expect(SupabaseSessionPolicy.decision(
            hasSession: true,
            isExpired: true
        ) == .refreshingExpiredSession)
        #expect(SupabaseSessionPolicy.decision(
            hasSession: true,
            isExpired: false
        ) == .signedIn)
    }

    @Test func appleSignInNonceHashIsDeterministic() {
        #expect(AppleSignInNonce.hash("CoupleSpace-W1") ==
                "3639d0045c9968cfb5182d7a7591aa078f00a411a40ca34943d9b3339358bf15")
    }

    @Test func retryKeepsOneStableMessageIdentity() {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        #expect(MessageIdentity.recordName(for: id) == "message_aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")

        var state: MessageDeliveryState = .queued
        state = MessageDeliveryReducer.reduce(state, event: .beginAttempt)
        #expect(state == .sending(attempt: 1))
        state = MessageDeliveryReducer.reduce(state, event: .recoverableFailure)
        #expect(state == .failed(attempt: 1))
        state = MessageDeliveryReducer.reduce(state, event: .beginAttempt)
        #expect(state == .sending(attempt: 2))
    }

    @Test func markerOutboxPersistsStableIdentityAndAttemptCount() throws {
        let suiteName = "MarkerOutboxStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000061")!
        let entry = MarkerOutboxEntry(
            relationshipID: UUID(uuidString: "90000000-0000-0000-0000-000000000001")!,
            clientID: UUID(uuidString: "91000000-0000-0000-0000-000000000001")!,
            attemptCount: 2
        )

        try MarkerOutboxStore(defaults: defaults).save(entry, userID: userID)
        #expect(try MarkerOutboxStore(defaults: defaults).load(userID: userID) == entry)

        MarkerOutboxStore(defaults: defaults).clear(userID: userID)
        #expect(try MarkerOutboxStore(defaults: defaults).load(userID: userID) == nil)
    }

    @Test func corruptedMarkerOutboxIsNotSilentlyDiscarded() throws {
        let suiteName = "MarkerOutboxCorruptionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000062")!
        defaults.set(
            Data("not-json".utf8),
            forKey: "couplespace.w1.marker-outbox.\(userID.uuidString.lowercased())"
        )

        #expect(throws: DecodingError.self) {
            try MarkerOutboxStore(defaults: defaults).load(userID: userID)
        }
    }

    @Test func serverTimestampAndIDProduceDeterministicOrder() {
        let sameServerDate = Date(timeIntervalSince1970: 100)
        let earlierID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let laterID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let values = [
            MessageOrderingValue(id: laterID, clientCreatedAt: .distantPast, serverCreatedAt: sameServerDate),
            MessageOrderingValue(id: earlierID, clientCreatedAt: .distantFuture, serverCreatedAt: sameServerDate),
        ]

        #expect(MessageOrderingValue.ordered(values).map(\.id) == [earlierID, laterID])
    }

    @Test func photoAssetPolicyUsesStablePrivateRecordName() {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        #expect(PhotoAssetPolicy.recordName(for: id) == "photo_aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
    }

    @Test func photoAssetPolicyCapsDimensionsWithoutUpscaling() {
        #expect(PhotoAssetPolicy.scaledDimensions(
            width: 4_032,
            height: 3_024,
            maxDimension: PhotoAssetPolicy.fullMaxDimension
        ) == PhotoDimensions(width: 1_600, height: 1_200))
        #expect(PhotoAssetPolicy.scaledDimensions(
            width: 300,
            height: 200,
            maxDimension: PhotoAssetPolicy.thumbnailMaxDimension
        ) == PhotoDimensions(width: 300, height: 200))
    }

    @Test func unpairingRequiresBothIndependentArchives() {
        let first = UUID()
        let second = UUID()
        let expected = Set([first, second])

        #expect(!RelationshipArchivePolicy.canFinalizeUnpairing(
            expectedParticipants: expected,
            archivedParticipants: [first]
        ))
        #expect(RelationshipArchivePolicy.canFinalizeUnpairing(
            expectedParticipants: expected,
            archivedParticipants: expected
        ))
    }

    @Test func closingRelationshipBlocksNewSharedContent() {
        #expect(RelationshipArchivePolicy.canWriteSharedContent(in: .active))
        #expect(!RelationshipArchivePolicy.canWriteSharedContent(in: .closing))
        #expect(!RelationshipArchivePolicy.canWriteSharedContent(in: .archived))
    }

    @Test func eachParticipantControlsOnlyTheirPersonalArchive() {
        let first = UUID()
        let second = UUID()

        #expect(RelationshipArchivePolicy.canManagePersonalArchive(
            actorID: first,
            archiveOwnerID: first
        ))
        #expect(!RelationshipArchivePolicy.canManagePersonalArchive(
            actorID: first,
            archiveOwnerID: second
        ))
        #expect(RelationshipArchivePolicy.personalArchiveDeletionTargets(
            requestedBy: first
        ) == [first])
    }

    @Test func notificationEnvelopeDoesNotExposePrivateContent() {
        let envelope = PrivateNotificationEnvelope(
            relationshipID: UUID(),
            eventID: UUID(),
            kind: "message_created"
        )

        #expect(envelope.userVisibleTitle == "CoupleSpace 有新動態")
        #expect(envelope.userVisibleBody == "打開 App 查看")
    }

    @Test func meaningfulInteractionRequiresBothExpectedParticipants() {
        let relationshipID = UUID()
        let interactionID = UUID()
        let first = UUID()
        let second = UUID()
        let expected = Set([first, second])
        let firstContribution = InteractionContribution(
            relationshipID: relationshipID,
            interactionID: interactionID,
            participantID: first,
            occurredAt: .now
        )
        let secondContribution = InteractionContribution(
            relationshipID: relationshipID,
            interactionID: interactionID,
            participantID: second,
            occurredAt: .now
        )

        #expect(!MeaningfulInteractionRule.isSatisfied(
            by: [firstContribution, firstContribution],
            expectedParticipants: expected
        ))
        #expect(MeaningfulInteractionRule.isSatisfied(
            by: [firstContribution, secondContribution],
            expectedParticipants: expected
        ))
    }

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }

}
