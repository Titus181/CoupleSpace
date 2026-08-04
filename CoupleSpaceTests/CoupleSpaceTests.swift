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
