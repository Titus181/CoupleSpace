//
//  CoupleSpaceTests.swift
//  CoupleSpaceTests
//
//  Created by titus on 2026/7/29.
//

import Foundation
import ImageIO
import Testing
import UIKit
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

    @Test func relationshipSnapshotPersistsPerSupabaseUserAndCanBeCleared() throws {
        let suiteName = "RelationshipSnapshotStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstUserID = UUID(uuidString: "00000000-0000-0000-0000-000000000091")!
        let secondUserID = UUID(uuidString: "00000000-0000-0000-0000-000000000092")!
        let snapshot = RelationshipSnapshot(
            relationshipID: UUID(uuidString: "90000000-0000-0000-0000-000000000001")!,
            status: "active",
            memberCount: 2
        )
        let store = RelationshipSnapshotStore(defaults: defaults)

        try store.save(snapshot, userID: firstUserID)

        #expect(try RelationshipSnapshotStore(defaults: defaults).load(userID: firstUserID) == snapshot)
        #expect(try store.load(userID: secondUserID) == nil)

        store.clear(userID: firstUserID)
        #expect(try store.load(userID: firstUserID) == nil)
    }

    @Test func foregroundRecoveryPlansOnlyCurrentActiveRelationshipQueues() {
        let currentRelationshipID = UUID()
        let otherRelationshipID = UUID()

        #expect(ForegroundOutboxRecoveryPolicy.plan(
            relationshipStatus: "active",
            currentRelationshipID: currentRelationshipID,
            markerRelationshipIDs: [currentRelationshipID],
            messageRelationshipIDs: [currentRelationshipID, currentRelationshipID],
            photoRelationshipIDs: [otherRelationshipID]
        ) == [.marker, .message])

        #expect(ForegroundOutboxRecoveryPolicy.plan(
            relationshipStatus: "closing",
            currentRelationshipID: currentRelationshipID,
            markerRelationshipIDs: [currentRelationshipID],
            messageRelationshipIDs: [currentRelationshipID],
            photoRelationshipIDs: [currentRelationshipID]
        ).isEmpty)

        #expect(ForegroundOutboxRecoveryPolicy.plan(
            relationshipStatus: "active",
            currentRelationshipID: nil,
            markerRelationshipIDs: [currentRelationshipID],
            messageRelationshipIDs: [],
            photoRelationshipIDs: []
        ).isEmpty)
    }

    @Test func foregroundRecoveryRetryIsBoundedWithShortBackoff() {
        #expect(ForegroundRecoveryRetryPolicy.maximumAttempts == 3)
        #expect(ForegroundRecoveryRetryPolicy.delayNanoseconds(afterAttempt: 0) == nil)
        #expect(ForegroundRecoveryRetryPolicy.delayNanoseconds(afterAttempt: 1) == 1_000_000_000)
        #expect(ForegroundRecoveryRetryPolicy.delayNanoseconds(afterAttempt: 2) == 4_000_000_000)
        #expect(ForegroundRecoveryRetryPolicy.delayNanoseconds(afterAttempt: 3) == nil)
        #expect(ForegroundRecoveryRetryPolicy.delayNanoseconds(afterAttempt: 4) == nil)
    }

    @Test func networkRecoveryTriggersOnlyAfterObservedOfflineToOnlineTransition() {
        #expect(!NetworkRecoveryTriggerPolicy.shouldRecover(
            previous: .unknown,
            current: .available
        ))
        #expect(NetworkRecoveryTriggerPolicy.shouldRecover(
            previous: .unavailable,
            current: .available
        ))
        #expect(!NetworkRecoveryTriggerPolicy.shouldRecover(
            previous: .available,
            current: .available
        ))
        #expect(!NetworkRecoveryTriggerPolicy.shouldRecover(
            previous: .available,
            current: .unavailable
        ))
        #expect(!NetworkRecoveryTriggerPolicy.shouldRecover(
            previous: .unavailable,
            current: .unavailable
        ))
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

    @Test func textMessagePolicyRejectsBlankAndOversizedContent() {
        #expect(TextMessagePolicy.normalized("  W1 test message  ") == "W1 test message")
        #expect(TextMessagePolicy.normalized(" \n ") == nil)
        #expect(TextMessagePolicy.normalized(
            String(repeating: "a", count: TextMessagePolicy.maximumLength + 1)
        ) == nil)
    }

    @Test func messageOutboxPersistsFIFOAndAcknowledgesOnlyHead() throws {
        let suiteName = "MessageOutboxStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000081")!
        let relationshipID = UUID(uuidString: "90000000-0000-0000-0000-000000000001")!
        let first = MessageOutboxEntry(
            relationshipID: relationshipID,
            clientID: UUID(uuidString: "93000000-0000-0000-0000-000000000001")!,
            body: "W1 test message 1",
            attemptCount: 0
        )
        let second = MessageOutboxEntry(
            relationshipID: relationshipID,
            clientID: UUID(uuidString: "93000000-0000-0000-0000-000000000002")!,
            body: "W1 test message 2",
            attemptCount: 0
        )
        let store = MessageOutboxStore(defaults: defaults)
        var queue = MessageOutboxQueue()
        queue.enqueue(first)
        queue.enqueue(second)
        try store.save(queue, userID: userID)

        var restored = try store.load(userID: userID)
        #expect(restored.entries == [first, second])
        #expect(restored.beginFirstAttempt()?.attemptCount == 1)
        #expect(restored.entries[1].attemptCount == 0)
        let didAcknowledgeTail = restored.acknowledgeFirst(clientID: second.clientID)
        #expect(!didAcknowledgeTail)
        let didAcknowledgeHead = restored.acknowledgeFirst(clientID: first.clientID)
        #expect(didAcknowledgeHead)
        try store.save(restored, userID: userID)
        #expect(try store.load(userID: userID).entries == [second])
    }

    @Test func messageOutboxPreservesLongFIFOAcrossPersistenceAndDrain() throws {
        let suiteName = "MessageOutboxLongFIFOTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let userID = UUID()
        let relationshipID = UUID()
        let entries = (0..<100).map { index in
            MessageOutboxEntry(
                relationshipID: relationshipID,
                clientID: UUID(),
                body: "W1 FIFO sample \(index)",
                attemptCount: 0
            )
        }
        let store = MessageOutboxStore(defaults: defaults)
        var queue = MessageOutboxQueue()
        entries.forEach { queue.enqueue($0) }
        try store.save(queue, userID: userID)

        var restored = try store.load(userID: userID)
        #expect(restored.entries == entries)
        for expected in entries {
            let attemptedEntry = restored.beginFirstAttempt()
            let attempted = try #require(attemptedEntry)
            #expect(attempted.clientID == expected.clientID)
            #expect(attempted.attemptCount == 1)
            let didAcknowledge = restored.acknowledgeFirst(clientID: expected.clientID)
            #expect(didAcknowledge)
        }
        try store.save(restored, userID: userID)
        #expect(try store.load(userID: userID).isEmpty)
    }

    @Test func markerOutboxPersistsFIFOAndRemovesOnlyAcknowledgedHead() throws {
        let suiteName = "MarkerOutboxStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000061")!
        let first = MarkerOutboxEntry(
            relationshipID: UUID(uuidString: "90000000-0000-0000-0000-000000000001")!,
            clientID: UUID(uuidString: "91000000-0000-0000-0000-000000000001")!,
            attemptCount: 0
        )
        let second = MarkerOutboxEntry(
            relationshipID: first.relationshipID,
            clientID: UUID(uuidString: "91000000-0000-0000-0000-000000000002")!,
            attemptCount: 0
        )
        let store = MarkerOutboxStore(defaults: defaults)
        var queue = MarkerOutboxQueue()
        queue.enqueue(first)
        queue.enqueue(second)

        try store.save(queue, userID: userID)
        #expect(try store.load(userID: userID).entries == [first, second])

        #expect(queue.beginFirstAttempt()?.clientID == first.clientID)
        #expect(queue.first?.attemptCount == 1)
        #expect(queue.entries[1].attemptCount == 0)
        let didAcknowledgeTail = queue.acknowledgeFirst(clientID: second.clientID)
        #expect(!didAcknowledgeTail)
        #expect(queue.entries.map(\.clientID) == [first.clientID, second.clientID])

        let didAcknowledgeHead = queue.acknowledgeFirst(clientID: first.clientID)
        #expect(didAcknowledgeHead)
        try store.save(queue, userID: userID)
        #expect(try store.load(userID: userID).entries == [second])

        let didAcknowledgeLastEntry = queue.acknowledgeFirst(clientID: second.clientID)
        #expect(didAcknowledgeLastEntry)
        try store.save(queue, userID: userID)
        #expect(try store.load(userID: userID).isEmpty)
    }

    @Test func markerOutboxPreservesLongFIFOAcrossPersistenceAndDrain() throws {
        let suiteName = "MarkerOutboxLongFIFOTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let userID = UUID()
        let relationshipID = UUID()
        let entries = (0..<100).map { _ in
            MarkerOutboxEntry(
                relationshipID: relationshipID,
                clientID: UUID(),
                attemptCount: 0
            )
        }
        let store = MarkerOutboxStore(defaults: defaults)
        var queue = MarkerOutboxQueue()
        entries.forEach { queue.enqueue($0) }
        try store.save(queue, userID: userID)

        var restored = try store.load(userID: userID)
        #expect(restored.entries == entries)
        for expected in entries {
            let attemptedEntry = restored.beginFirstAttempt()
            let attempted = try #require(attemptedEntry)
            #expect(attempted.clientID == expected.clientID)
            #expect(attempted.attemptCount == 1)
            let didAcknowledge = restored.acknowledgeFirst(clientID: expected.clientID)
            #expect(didAcknowledge)
        }
        try store.save(restored, userID: userID)
        #expect(try store.load(userID: userID).isEmpty)
    }

    @Test func markerOutboxLoadsLegacySingleEntryWithoutDataLoss() throws {
        let suiteName = "MarkerOutboxLegacyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000063")!
        let legacyEntry = MarkerOutboxEntry(
            relationshipID: UUID(uuidString: "90000000-0000-0000-0000-000000000001")!,
            clientID: UUID(uuidString: "91000000-0000-0000-0000-000000000003")!,
            attemptCount: 2
        )
        defaults.set(
            try JSONEncoder().encode(legacyEntry),
            forKey: "couplespace.w1.marker-outbox.\(userID.uuidString.lowercased())"
        )

        #expect(try MarkerOutboxStore(defaults: defaults).load(userID: userID).entries == [legacyEntry])
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
            _ = try MarkerOutboxStore(defaults: defaults).load(userID: userID)
        }
    }

    @Test func markerOutboxExplicitlyDiscardsOnlyOtherRelationships() throws {
        let suiteName = "MarkerOutboxRelationshipDiscardTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let userID = UUID()
        let currentRelationshipID = UUID()
        let otherRelationshipID = UUID()
        let store = MarkerOutboxStore(defaults: defaults)
        var queue = MarkerOutboxQueue()
        queue.enqueue(MarkerOutboxEntry(
            relationshipID: otherRelationshipID,
            clientID: UUID(),
            attemptCount: 1
        ))
        try store.save(queue, userID: userID)

        #expect(try store.discardIfOnlyFromOtherRelationships(
            userID: userID,
            currentRelationshipID: currentRelationshipID
        ))
        #expect(try store.load(userID: userID).isEmpty)

        queue.enqueue(MarkerOutboxEntry(
            relationshipID: currentRelationshipID,
            clientID: UUID(),
            attemptCount: 1
        ))
        try store.save(queue, userID: userID)
        #expect(try !store.discardIfOnlyFromOtherRelationships(
            userID: userID,
            currentRelationshipID: currentRelationshipID
        ))
        #expect(try store.load(userID: userID) == queue)
    }

    @Test func photoOutboxPersistsDataAndAttemptAcrossStoreInstances() throws {
        let suiteName = "PhotoOutboxStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000071")!
        let relationshipID = UUID(uuidString: "90000000-0000-0000-0000-000000000001")!
        let clientID = UUID(uuidString: "92000000-0000-0000-0000-000000000001")!
        let jpegData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let firstStore = PhotoOutboxStore(defaults: defaults, directoryURL: directoryURL)

        let created = try firstStore.create(
            jpegData: jpegData,
            relationshipID: relationshipID,
            clientID: clientID,
            userID: userID
        )
        #expect(created.attemptCount == 0)

        let restoredStore = PhotoOutboxStore(defaults: defaults, directoryURL: directoryURL)
        let attemptedEntry = try restoredStore.beginAttempt(userID: userID)
        let sending = try #require(attemptedEntry)
        #expect(sending.attemptCount == 1)
        #expect(try restoredStore.data(for: sending) == jpegData)

        #expect(try restoredStore.acknowledgeFirst(clientID: sending.clientID, userID: userID))
        #expect(try restoredStore.load(userID: userID).isEmpty)
    }

    @Test func photoOutboxChecksCapacityBeforeWritingOrEnqueuing() throws {
        let suiteName = "PhotoOutboxCapacityTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let userID = UUID()
        let clientID = UUID()
        let store = PhotoOutboxStore(
            defaults: defaults,
            directoryURL: directoryURL,
            availableCapacity: { _ in 3 }
        )

        #expect(throws: PhotoOutboxStoreError.insufficientCapacity) {
            try store.create(
                jpegData: Data(repeating: 0xff, count: 4),
                relationshipID: UUID(),
                clientID: clientID,
                userID: userID
            )
        }
        #expect(try store.load(userID: userID).isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent(
                clientID.uuidString.lowercased() + ".jpg"
            ).path
        ))
    }

    @Test func photoOutboxCapacityPolicyAllowsExactAndUnknownCapacity() {
        #expect(PhotoOutboxCapacityPolicy.permitsWrite(
            jpegByteCount: 4,
            availableBytes: 4
        ))
        #expect(!PhotoOutboxCapacityPolicy.permitsWrite(
            jpegByteCount: 4,
            availableBytes: 3
        ))
        #expect(PhotoOutboxCapacityPolicy.permitsWrite(
            jpegByteCount: 4,
            availableBytes: nil
        ))
        #expect(!PhotoOutboxCapacityPolicy.permitsWrite(
            jpegByteCount: -1,
            availableBytes: 4
        ))
    }

    @Test func photoOutboxPreservesFIFOAndRejectsOutOfOrderAcknowledgement() throws {
        let suiteName = "PhotoOutboxFIFOTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000072")!
        let relationshipID = UUID(uuidString: "90000000-0000-0000-0000-000000000001")!
        let store = PhotoOutboxStore(defaults: defaults, directoryURL: directoryURL)
        let firstClientID = UUID(uuidString: "92000000-0000-0000-0000-000000000002")!
        let secondClientID = UUID(uuidString: "92000000-0000-0000-0000-000000000003")!
        _ = try store.create(
            jpegData: Data([1]),
            relationshipID: relationshipID,
            clientID: firstClientID,
            userID: userID
        )
        _ = try store.create(
            jpegData: Data([2]),
            relationshipID: relationshipID,
            clientID: secondClientID,
            userID: userID
        )

        #expect(try store.load(userID: userID).entries.map(\.clientID) == [firstClientID, secondClientID])
        #expect(try store.beginAttempt(userID: userID)?.clientID == firstClientID)
        #expect(!(try store.acknowledgeFirst(clientID: secondClientID, userID: userID)))
        #expect(try store.load(userID: userID).entries.map(\.clientID) == [firstClientID, secondClientID])
        #expect(try store.acknowledgeFirst(clientID: firstClientID, userID: userID))
        let remaining = try store.load(userID: userID)
        #expect(remaining.entries.map(\.clientID) == [secondClientID])
        #expect(remaining.first?.attemptCount == 0)
        #expect(try store.data(for: try #require(remaining.first)) == Data([2]))
    }

    @Test func photoOutboxPreservesLongFIFOFilesAcrossPersistenceAndDrain() throws {
        let suiteName = "PhotoOutboxLongFIFOTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let userID = UUID()
        let relationshipID = UUID()
        let store = PhotoOutboxStore(defaults: defaults, directoryURL: directoryURL)
        var expected: [(clientID: UUID, data: Data)] = []
        for index in 0..<32 {
            let clientID = UUID()
            let data = Data(repeating: UInt8(index), count: 1_024)
            _ = try store.create(
                jpegData: data,
                relationshipID: relationshipID,
                clientID: clientID,
                userID: userID
            )
            expected.append((clientID, data))
        }

        #expect(try store.load(userID: userID).entries.map(\.clientID) == expected.map(\.clientID))
        for item in expected {
            let attemptedEntry = try store.beginAttempt(userID: userID)
            let attempted = try #require(attemptedEntry)
            #expect(attempted.clientID == item.clientID)
            #expect(attempted.attemptCount == 1)
            #expect(try store.data(for: attempted) == item.data)
            #expect(try store.acknowledgeFirst(clientID: item.clientID, userID: userID))
        }
        #expect(try store.load(userID: userID).isEmpty)
        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: directoryURL.path)
        #expect(remainingFiles.isEmpty)
    }

    @Test func photoOutboxReportsMissingLocalDataWithoutDiscardingMetadata() throws {
        let suiteName = "PhotoOutboxMissingFileTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000073")!
        let clientID = UUID(uuidString: "92000000-0000-0000-0000-000000000004")!
        let store = PhotoOutboxStore(defaults: defaults, directoryURL: directoryURL)
        let entry = try store.create(
            jpegData: Data([1]),
            relationshipID: UUID(uuidString: "90000000-0000-0000-0000-000000000001")!,
            clientID: clientID,
            userID: userID
        )
        let secondEntry = try store.create(
            jpegData: Data([2]),
            relationshipID: entry.relationshipID,
            clientID: UUID(uuidString: "92000000-0000-0000-0000-000000000006")!,
            userID: userID
        )
        try FileManager.default.removeItem(
            at: directoryURL.appendingPathComponent(entry.localFileName)
        )

        #expect(throws: PhotoOutboxStoreError.missingLocalFile) {
            try store.data(for: entry)
        }
        #expect(try store.load(userID: userID).entries == [entry, secondEntry])
        #expect(try store.data(for: secondEntry) == Data([2]))
    }

    @Test func photoOutboxLoadsLegacySingleEntryWithoutLosingItsFile() throws {
        let suiteName = "PhotoOutboxLegacyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000074")!
        let clientID = UUID(uuidString: "92000000-0000-0000-0000-000000000005")!
        let legacyEntry = PhotoOutboxEntry(
            relationshipID: UUID(uuidString: "90000000-0000-0000-0000-000000000001")!,
            clientID: clientID,
            attemptCount: 2,
            localFileName: "\(clientID.uuidString.lowercased()).jpg"
        )
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let jpegData = Data([1, 2, 3])
        try jpegData.write(to: directoryURL.appendingPathComponent(legacyEntry.localFileName))
        defaults.set(
            try JSONEncoder().encode(legacyEntry),
            forKey: "couplespace.w1.photo-outbox.\(userID.uuidString.lowercased())"
        )

        let store = PhotoOutboxStore(defaults: defaults, directoryURL: directoryURL)
        #expect(try store.load(userID: userID).entries == [legacyEntry])
        #expect(try store.data(for: legacyEntry) == jpegData)
    }

    @Test func pendingOrSendingPhotoBlocksUnpairing() {
        #expect(PhotoOutboxLifecyclePolicy.canBeginUnpairing(
            hasPendingPhoto: false,
            isSendingPhoto: false
        ))
        #expect(!PhotoOutboxLifecyclePolicy.canBeginUnpairing(
            hasPendingPhoto: true,
            isSendingPhoto: false
        ))
        #expect(!PhotoOutboxLifecyclePolicy.canBeginUnpairing(
            hasPendingPhoto: false,
            isSendingPhoto: true
        ))
    }

    @Test func closingPhotoReconciliationAcknowledgesMatchingMetadata() throws {
        let userID = UUID()
        #expect(try PhotoOutboxLifecyclePolicy.actionForClosingRelationship(
            remoteCreatorID: userID,
            remoteItemKind: "photo",
            currentUserID: userID
        ) == .acknowledgeDelivered)
    }

    @Test func closingPhotoReconciliationDeletesOnlyMissingMetadata() throws {
        #expect(try PhotoOutboxLifecyclePolicy.actionForClosingRelationship(
            remoteCreatorID: nil,
            remoteItemKind: nil,
            currentUserID: UUID()
        ) == .deleteOrphan)
    }

    @Test func closingPhotoReconciliationRejectsIdentityCollision() {
        #expect(throws: PhotoOutboxLifecyclePolicy.ReconciliationError.remoteIdentityMismatch) {
            try PhotoOutboxLifecyclePolicy.actionForClosingRelationship(
                remoteCreatorID: UUID(),
                remoteItemKind: "photo",
                currentUserID: UUID()
            )
        }
    }

    @Test func archivedPhotoReconciliationUsesSealedMetadata() throws {
        #expect(try PhotoOutboxLifecyclePolicy.actionForArchivedRelationship(
            archivedItemKind: "photo"
        ) == .acknowledgeDelivered)
        #expect(try PhotoOutboxLifecyclePolicy.actionForArchivedRelationship(
            archivedItemKind: nil
        ) == .deleteOrphan)
    }

    @Test func archivedPhotoReconciliationRejectsWrongItemKind() {
        #expect(throws: PhotoOutboxLifecyclePolicy.ReconciliationError.remoteIdentityMismatch) {
            try PhotoOutboxLifecyclePolicy.actionForArchivedRelationship(
                archivedItemKind: "message"
            )
        }
    }

    @Test func acceptedPhotoFinalizationAcknowledgesDelivery() throws {
        #expect(try PhotoFinalizationPolicy.action(
            accepted: true,
            reason: nil
        ) == .acknowledgeDelivered)
    }

    @Test func knownPhotoQuotaRejectionsDeleteBeforeAcknowledgement() throws {
        #expect(try PhotoFinalizationPolicy.action(
            accepted: false,
            reason: "monthly_photo_limit"
        ) == .deleteQuotaRejectedObject(
            message: "本月照片新增已達 W1 暫定上限（30 張／關係）"
        ))
        #expect(try PhotoFinalizationPolicy.action(
            accepted: false,
            reason: "total_storage_limit"
        ) == .deleteQuotaRejectedObject(
            message: "照片總容量已達 W1 暫定上限（1 GB／關係）"
        ))
    }

    @Test func unknownPhotoFinalizationRejectionRemainsRetryable() {
        #expect(throws: PhotoFinalizationPolicy.DecisionError.unknownRejection) {
            try PhotoFinalizationPolicy.action(
                accepted: false,
                reason: "unexpected_reason"
            )
        }
    }

    @Test func quotaRejectionStatusIncludesActualMessageWhenOutboxIsEmpty() {
        #expect(PhotoFinalizationPolicy.rejectedOutboxStatus(
            message: "本月照片新增已達 W1 暫定上限（30 張／關係）",
            remainingCount: 0
        ) == "本月照片新增已達 W1 暫定上限（30 張／關係）；未建立共享照片")
    }

    @Test func quotaRejectionStatusReportsRemainingOutboxCount() {
        #expect(PhotoFinalizationPolicy.rejectedOutboxStatus(
            message: "照片總容量已達 W1 暫定上限（1 GB／關係）",
            remainingCount: 2
        ) == "照片總容量已達 W1 暫定上限（1 GB／關係）；已移除本張，尚有 2 張待送")
    }

    @Test func quotaCleanupDeletesRemoteObjectBeforeAcknowledgingOutbox() async throws {
        var events: [String] = []

        let didAcknowledge = try await PhotoQuotaCleanupCoordinator.deleteThenAcknowledge(
            deleteRemoteObject: {
                events.append("delete")
            },
            acknowledgeLocalEntry: {
                events.append("acknowledge")
                return true
            }
        )

        #expect(didAcknowledge)
        #expect(events == ["delete", "acknowledge"])
    }

    @Test func quotaCleanupFailureDoesNotAcknowledgeOutbox() async {
        var didAcknowledge = false

        do {
            _ = try await PhotoQuotaCleanupCoordinator.deleteThenAcknowledge(
                deleteRemoteObject: {
                    throw PhotoQuotaCleanupProbeError.expected
                },
                acknowledgeLocalEntry: {
                    didAcknowledge = true
                    return true
                }
            )
            Issue.record("Expected remote cleanup to fail")
        } catch PhotoQuotaCleanupProbeError.expected {
            // Expected: the local queue must remain untouched.
        } catch {
            Issue.record("Unexpected cleanup error: \(error)")
        }

        #expect(!didAcknowledge)
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

    @Test func photoAssetProcessorNormalizesLargeRotatedPhotoAndRemovesGPS() throws {
        let sourceData = try makeJPEGFixture(
            width: 2_400,
            height: 1_200,
            orientation: 6,
            includesGPS: true
        )

        let prepared = try PhotoAssetProcessor.prepare(sourceData)
        let fullProperties = try imageProperties(prepared.fullData)
        let thumbnailProperties = try imageProperties(prepared.thumbnailData)

        #expect(fullProperties.width == 800)
        #expect(fullProperties.height == 1_600)
        #expect(fullProperties.orientation == nil || fullProperties.orientation == 1)
        #expect(!fullProperties.hasGPS)
        #expect(thumbnailProperties.width == 160)
        #expect(thumbnailProperties.height == 320)
        #expect(thumbnailProperties.orientation == nil || thumbnailProperties.orientation == 1)
        #expect(!thumbnailProperties.hasGPS)
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

    private func makeJPEGFixture(
        width: Int,
        height: Int,
        orientation: Int,
        includesGPS: Bool
    ) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.systemYellow.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width / 3, height: height))
        }
        let cgImage = try #require(image.cgImage)
        let mutableData = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            mutableData,
            "public.jpeg" as CFString,
            1,
            nil
        ))
        var properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImageDestinationLossyCompressionQuality: 0.9,
        ]
        if includesGPS {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 25.0,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 121.0,
                kCGImagePropertyGPSLongitudeRef: "E",
            ]
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return mutableData as Data
    }

    private enum PhotoQuotaCleanupProbeError: Error {
        case expected
    }

    private func imageProperties(_ data: Data) throws -> (
        width: Int,
        height: Int,
        orientation: Int?,
        hasGPS: Bool
    ) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        return (
            width: try #require(properties[kCGImagePropertyPixelWidth] as? Int),
            height: try #require(properties[kCGImagePropertyPixelHeight] as? Int),
            orientation: properties[kCGImagePropertyOrientation] as? Int,
            hasGPS: properties[kCGImagePropertyGPSDictionary] != nil
        )
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

    @Test func personalArchiveAppointmentAuditDetectsCompleteAndBrokenLinks() {
        let sourceID = UUID()
        let discussionID = UUID()
        let appointmentID = UUID()
        let creatorID = UUID()

        let complete = PersonalArchiveAppointmentAudit.inspect(
            items: [
                PersonalArchiveItemReference(
                    clientID: sourceID,
                    sourceCreatorUserID: creatorID,
                    appointmentClientID: nil
                ),
                PersonalArchiveItemReference(
                    clientID: discussionID,
                    sourceCreatorUserID: creatorID,
                    appointmentClientID: appointmentID
                ),
            ],
            appointments: [PersonalArchiveAppointmentReference(
                clientID: appointmentID,
                sourceSharedItemClientID: sourceID
            )],
            events: [PersonalArchiveAppointmentEventReference(
                appointmentClientID: appointmentID
            )]
        )

        #expect(complete.appointmentCount == 1)
        #expect(complete.discussionItemCount == 1)
        #expect(complete.eventCount == 1)
        #expect(complete.brokenReferenceCount == 0)
        #expect(complete.status == "約定封存關聯完整")

        let missingID = UUID()
        let broken = PersonalArchiveAppointmentAudit.inspect(
            items: [PersonalArchiveItemReference(
                clientID: discussionID,
                sourceCreatorUserID: nil,
                appointmentClientID: missingID
            )],
            appointments: [PersonalArchiveAppointmentReference(
                clientID: appointmentID,
                sourceSharedItemClientID: sourceID
            )],
            events: [PersonalArchiveAppointmentEventReference(
                appointmentClientID: missingID
            )]
        )

        #expect(broken.brokenReferenceCount == 4)
        #expect(broken.status == "約定封存關聯異常：4 處")
    }

    @Test func personalArchiveExportBuildsDeterministicFolder() throws {
        let relationshipID = UUID(uuidString: "a0000000-0000-4000-8000-000000000001")!
        let messageID = UUID(uuidString: "a0000000-0000-4000-8000-000000000002")!
        let photoID = UUID(uuidString: "a0000000-0000-4000-8000-000000000003")!
        let baseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let package = try PersonalArchiveExportPackage(
            relationshipID: relationshipID,
            exportedAt: Date(timeIntervalSince1970: 300),
            items: [
                PersonalArchiveExportItem(
                    clientID: photoID,
                    kind: "photo",
                    createdAt: Date(timeIntervalSince1970: 200),
                    text: nil,
                    photoFile: PersonalArchiveExportPackage.photoFileName(clientID: photoID)
                ),
                PersonalArchiveExportItem(
                    clientID: messageID,
                    kind: "message",
                    createdAt: Date(timeIntervalSince1970: 100),
                    text: "W1 test export",
                    photoFile: nil
                ),
            ]
        )
        var staging = try PersonalArchiveExportStaging(
            package: package,
            baseDirectory: baseDirectory
        )
        try staging.writePhoto(
            clientID: photoID,
            jpegData: Data([0xff, 0xd8, 0xff, 0xd9])
        )

        let exportedURL = baseDirectory.appendingPathComponent("exported", isDirectory: true)
        try staging.fileWrapper().write(
            to: exportedURL,
            options: .atomic,
            originalContentsURL: nil
        )

        let manifestData = try Data(
            contentsOf: exportedURL.appendingPathComponent("manifest.json")
        )
        let photoFileName = "a0000000-0000-4000-8000-000000000003.jpg"

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            PersonalArchiveExportManifest.self,
            from: manifestData
        )

        #expect(manifest.schemaVersion == 1)
        #expect(manifest.relationshipID == relationshipID)
        #expect(manifest.items.map(\.clientID) == [messageID, photoID])
        #expect(manifest.items[0].text == "W1 test export")
        #expect(manifest.items[1].photoFile == photoFileName)
        #expect(try Data(
            contentsOf: exportedURL
                .appendingPathComponent("photos", isDirectory: true)
                .appendingPathComponent(photoFileName)
        ) == Data([0xff, 0xd8, 0xff, 0xd9]))
    }

    @Test func personalArchiveExportRejectsMissingPhoto() throws {
        let photoID = UUID()
        let baseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let package = try PersonalArchiveExportPackage(
            relationshipID: UUID(),
            exportedAt: .now,
            items: [PersonalArchiveExportItem(
                clientID: photoID,
                kind: "photo",
                createdAt: .now,
                text: nil,
                photoFile: PersonalArchiveExportPackage.photoFileName(clientID: photoID)
            )]
        )
        let staging = try PersonalArchiveExportStaging(
            package: package,
            baseDirectory: baseDirectory
        )
        #expect(throws: PersonalArchiveExportError.photoSetMismatch) {
            try staging.fileWrapper()
        }
    }

    @Test func personalArchiveExportChecksKnownStagingCapacityBeforeDownload() {
        let requiredBytes = PersonalArchiveExportCapacityPolicy.requiredBytes(
            manifestByteCount: 512,
            photoByteSizes: [1_024, 2_048]
        )

        #expect(requiredBytes == 3_584)
        #expect(PersonalArchiveExportCapacityPolicy.permitsStaging(
            requiredBytes: requiredBytes,
            availableBytes: 3_584
        ))
        #expect(!PersonalArchiveExportCapacityPolicy.permitsStaging(
            requiredBytes: requiredBytes,
            availableBytes: 3_583
        ))
    }

    @Test func personalArchiveExportPreservesLegacyUnknownSizeCompatibility() {
        let requiredBytes = PersonalArchiveExportCapacityPolicy.requiredBytes(
            manifestByteCount: 512,
            photoByteSizes: [1_024, nil]
        )

        #expect(requiredBytes == nil)
        #expect(PersonalArchiveExportCapacityPolicy.permitsStaging(
            requiredBytes: requiredBytes,
            availableBytes: 0
        ))
    }

    @Test func personalArchiveExportStagesManyPhotosWithoutChangingTheirBytes() throws {
        let baseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let photoIDs = (0..<64).map { _ in UUID() }
        let items = photoIDs.enumerated().map { index, photoID in
            PersonalArchiveExportItem(
                clientID: photoID,
                kind: "photo",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                text: nil,
                photoFile: PersonalArchiveExportPackage.photoFileName(clientID: photoID)
            )
        }
        let package = try PersonalArchiveExportPackage(
            relationshipID: UUID(),
            exportedAt: Date(timeIntervalSince1970: 1_000),
            items: items
        )
        var staging = try PersonalArchiveExportStaging(
            package: package,
            baseDirectory: baseDirectory
        )
        for (index, photoID) in photoIDs.enumerated() {
            try staging.writePhoto(
                clientID: photoID,
                jpegData: Data(repeating: UInt8(index), count: 64 * 1_024)
            )
        }

        let exportedURL = baseDirectory.appendingPathComponent("many-photos", isDirectory: true)
        try staging.fileWrapper().write(
            to: exportedURL,
            options: .atomic,
            originalContentsURL: nil
        )

        let photoDirectory = exportedURL.appendingPathComponent("photos", isDirectory: true)
        let exportedNames = try FileManager.default.contentsOfDirectory(atPath: photoDirectory.path)
        #expect(exportedNames.count == photoIDs.count)
        for (index, photoID) in photoIDs.enumerated() {
            let data = try Data(contentsOf: photoDirectory.appendingPathComponent(
                PersonalArchiveExportPackage.photoFileName(clientID: photoID)
            ))
            #expect(data.count == 64 * 1_024)
            #expect(data.first == UInt8(index))
            #expect(data.last == UInt8(index))
        }
    }

    @Test func personalArchiveExportDocumentSeparatesDeliveryAndStagingNames() throws {
        let baseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let package = try PersonalArchiveExportPackage(
            relationshipID: UUID(),
            exportedAt: .now,
            items: []
        )
        let staging = try PersonalArchiveExportStaging(
            package: package,
            baseDirectory: baseDirectory
        )
        let exportFileName = "CoupleSpace-personal-archive-test"
        let wrapper = try staging.fileWrapper(exportFileName: exportFileName)

        #expect(wrapper.filename == nil)
        #expect(wrapper.preferredFilename == exportFileName)
        #expect(wrapper.preferredFilename != staging.directoryURL.lastPathComponent)
        let deliveredURL = baseDirectory.appendingPathComponent(
            exportFileName,
            isDirectory: true
        )
        try wrapper.write(
            to: deliveredURL,
            options: FileWrapper.WritingOptions.atomic,
            originalContentsURL: nil
        )
        #expect(FileManager.default.fileExists(
            atPath: deliveredURL.appendingPathComponent("manifest.json").path
        ))
    }

    @Test func personalArchiveExportRejectsPrivateContentInPhotoEntry() {
        let photoID = UUID()
        #expect(throws: PersonalArchiveExportError.invalidItemContent) {
            try PersonalArchiveExportPackage(
                relationshipID: UUID(),
                exportedAt: .now,
                items: [PersonalArchiveExportItem(
                    clientID: photoID,
                    kind: "photo",
                    createdAt: .now,
                    text: "must not be present",
                    photoFile: PersonalArchiveExportPackage.photoFileName(clientID: photoID)
                )]
            )
        }
    }

    @Test func personalArchiveExportRejectsDuplicatePhotoWrite() throws {
        let photoID = UUID()
        let baseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let package = try PersonalArchiveExportPackage(
            relationshipID: UUID(),
            exportedAt: .now,
            items: [PersonalArchiveExportItem(
                clientID: photoID,
                kind: "photo",
                createdAt: .now,
                text: nil,
                photoFile: PersonalArchiveExportPackage.photoFileName(clientID: photoID)
            )]
        )
        var staging = try PersonalArchiveExportStaging(
            package: package,
            baseDirectory: baseDirectory
        )
        try staging.writePhoto(clientID: photoID, jpegData: Data([1]))
        #expect(throws: PersonalArchiveExportError.duplicatePhoto) {
            try staging.writePhoto(clientID: photoID, jpegData: Data([2]))
        }
    }

    @Test func personalArchiveExportCleansOnlyAbandonedStagingDirectories() throws {
        let baseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let abandonedURL = baseDirectory.appendingPathComponent(
            PersonalArchiveExportStaging.directoryPrefix + UUID().uuidString,
            isDirectory: true
        )
        let unrelatedURL = baseDirectory.appendingPathComponent("keep", isDirectory: true)
        let similarlyNamedFileURL = baseDirectory.appendingPathComponent(
            PersonalArchiveExportStaging.directoryPrefix + "file"
        )
        try FileManager.default.createDirectory(
            at: abandonedURL,
            withIntermediateDirectories: false
        )
        let partialPhotosURL = abandonedURL.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(
            at: partialPhotosURL,
            withIntermediateDirectories: false
        )
        try Data(repeating: 7, count: 1_024).write(
            to: partialPhotosURL.appendingPathComponent("partial.jpg")
        )
        try FileManager.default.createDirectory(
            at: unrelatedURL,
            withIntermediateDirectories: false
        )
        try Data([1]).write(to: similarlyNamedFileURL)

        try PersonalArchiveExportStaging.cleanupAbandoned(in: baseDirectory)

        #expect(!FileManager.default.fileExists(atPath: abandonedURL.path))
        #expect(FileManager.default.fileExists(atPath: unrelatedURL.path))
        #expect(FileManager.default.fileExists(atPath: similarlyNamedFileURL.path))
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

    @Test func notificationPayloadOmitsRelationshipAndPrivateContent() throws {
        let relationshipID = UUID()
        let eventID = UUID()
        let envelope = PrivateNotificationEnvelope(
            relationshipID: relationshipID,
            eventID: eventID,
            kind: "w1_generic"
        )

        let payload = PrivateNotificationPayload(envelope: envelope)
        let data = try JSONEncoder().encode(payload)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(payload.aps.alert.title == "CoupleSpace 有新動態")
        #expect(payload.aps.alert.body == "打開 App 查看")
        #expect(payload.eventID == eventID)
        #expect(!json.lowercased().contains(relationshipID.uuidString.lowercased()))
        #expect(!json.contains("message"))
        #expect(!json.contains("photo"))
    }

#if os(iOS)
    @Test func apnsTokenValueUsesHexWithoutPresentationMetadata() {
        let token = APNsDeviceTokenValue(Data([0x00, 0xab, 0xff, 0x10]))

        #expect(token.hex == "00abff10")
    }

    @Test func partnerObservedClosingRelationshipClearsLocalReminders() async {
        let relationshipID = UUID()
        let activeRelationship = PairingRelationship(
            id: relationshipID,
            memberCount: 2
        )
        let closingRelationship = PairingRelationship(
            id: relationshipID,
            memberCount: 2,
            status: "closing"
        )
        let service = ReminderLifecyclePairingServiceFake(
            currentRelationship: closingRelationship
        )
        var cleanedRelationshipIDs: [UUID] = []
        let model = PairingModel(
            service: service,
            initialState: .paired(activeRelationship),
            removeRelationshipReminders: { cleanedRelationshipIDs.append($0) }
        )

        await model.refresh()

        #expect(model.state == .closing(closingRelationship))
        #expect(cleanedRelationshipIDs == [relationshipID])
    }

    @Test func nilRelationshipClearsRemindersFromWaitingAndClosingStates() async {
        let relationshipID = UUID()
        let relationship = PairingRelationship(
            id: relationshipID,
            memberCount: 1
        )
        let archive = PersonalArchive(id: UUID(), relationshipID: relationshipID)
        let cases: [(PairingState, PersonalArchive?, PairingState)] = [
            (.waiting(relationship, invitation: nil), archive, .archived(archive)),
            (
                .closing(PairingRelationship(
                    id: relationshipID,
                    memberCount: 2,
                    status: "closing"
                )),
                nil,
                .unpaired
            ),
        ]

        for (initialState, ownArchive, expectedState) in cases {
            let service = ReminderLifecyclePairingServiceFake(
                currentRelationship: nil,
                ownPersonalArchive: ownArchive
            )
            var cleanedRelationshipIDs: [UUID] = []
            let model = PairingModel(
                service: service,
                initialState: initialState,
                removeRelationshipReminders: { cleanedRelationshipIDs.append($0) }
            )

            await model.refresh()

            #expect(model.state == expectedState)
            #expect(cleanedRelationshipIDs == [relationshipID])
        }
    }

    @Test func archiveDiscoveredWithoutPriorRelationshipClearsItsReminders() async {
        let relationshipID = UUID()
        let archive = PersonalArchive(id: UUID(), relationshipID: relationshipID)
        let service = ReminderLifecyclePairingServiceFake(
            currentRelationship: nil,
            ownPersonalArchive: archive
        )
        var cleanedRelationshipIDs: [UUID] = []
        let model = PairingModel(
            service: service,
            removeRelationshipReminders: { cleanedRelationshipIDs.append($0) }
        )

        await model.refresh()

        #expect(model.state == .archived(archive))
        #expect(cleanedRelationshipIDs == [relationshipID])
    }

    @Test func explicitlyArchivedRelationshipClearsRemindersAndRestoresArchive() async {
        let relationshipID = UUID()
        let activeRelationship = PairingRelationship(
            id: relationshipID,
            memberCount: 2
        )
        let archivedRelationship = PairingRelationship(
            id: relationshipID,
            memberCount: 0,
            status: "archived"
        )
        let archive = PersonalArchive(id: UUID(), relationshipID: relationshipID)
        let service = ReminderLifecyclePairingServiceFake(
            currentRelationship: archivedRelationship,
            ownPersonalArchive: archive
        )
        var cleanedRelationshipIDs: [UUID] = []
        let model = PairingModel(
            service: service,
            initialState: .paired(activeRelationship),
            removeRelationshipReminders: { cleanedRelationshipIDs.append($0) }
        )

        await model.refresh()

        #expect(model.state == .archived(archive))
        #expect(cleanedRelationshipIDs == [relationshipID])
    }

    @Test func terminalRefreshCannotOverwriteANewerAuthenticatedSessionDuringCleanup() async {
        let relationshipID = UUID()
        let archive = PersonalArchive(id: UUID(), relationshipID: relationshipID)
        let service = ReminderLifecyclePairingServiceFake(
            currentRelationship: nil,
            ownPersonalArchive: archive
        )
        let suspendedCleanup = SuspendedRelationshipReminderCleanup()
        let model = PairingModel(
            service: service,
            initialState: .paired(PairingRelationship(
                id: relationshipID,
                memberCount: 2
            )),
            removeRelationshipReminders: { relationshipID in
                await suspendedCleanup.run(relationshipID: relationshipID)
            }
        )
        let staleRefresh = Task { await model.refresh() }
        while suspendedCleanup.relationshipIDs.isEmpty {
            await Task.yield()
        }

        model.resetForAuthenticatedSession()
        suspendedCleanup.resume()
        await staleRefresh.value

        #expect(suspendedCleanup.relationshipIDs == [relationshipID])
        #expect(model.state == .checking)
        #expect(model.closingPersonalArchive == nil)
        #expect(model.statusMessage == nil)
    }

    @Test func backgroundAppointmentRefreshSkipsReconcileAfterAccountSwitch() async throws {
        let relationshipID = UUID()
        let initialContext = BackgroundAppointmentReminderContext(
            userID: UUID(),
            relationshipID: relationshipID,
            relationshipStatus: "active"
        )
        let switchedContext = BackgroundAppointmentReminderContext(
            userID: UUID(),
            relationshipID: relationshipID,
            relationshipStatus: "active"
        )
        var fetchCallCount = 0
        var reconcileCallCount = 0
        let orchestrator = BackgroundAppointmentReminderReconcileOrchestrator(
            initialContext: initialContext,
            fetchAppointments: { _ in
                fetchCallCount += 1
                return []
            },
            revalidatedContext: { switchedContext },
            reconcile: { _, _ in reconcileCallCount += 1 }
        )

        let didReconcile = try await orchestrator.run()

        #expect(fetchCallCount == 1)
        #expect(!didReconcile)
        #expect(reconcileCallCount == 0)
    }

    @Test func backgroundAppointmentRefreshSkipsReconcileAfterLogout() async throws {
        let initialContext = BackgroundAppointmentReminderContext(
            userID: UUID(),
            relationshipID: UUID(),
            relationshipStatus: "active"
        )
        var reconcileCallCount = 0
        let orchestrator = BackgroundAppointmentReminderReconcileOrchestrator(
            initialContext: initialContext,
            fetchAppointments: { _ in [] },
            revalidatedContext: { nil },
            reconcile: { _, _ in reconcileCallCount += 1 }
        )

        let didReconcile = try await orchestrator.run()

        #expect(!didReconcile)
        #expect(reconcileCallCount == 0)
    }

    @Test func backgroundAppointmentRefreshSkipsReconcileAfterRelationshipClosing() async throws {
        let userID = UUID()
        let relationshipID = UUID()
        let initialContext = BackgroundAppointmentReminderContext(
            userID: userID,
            relationshipID: relationshipID,
            relationshipStatus: "active"
        )
        let closingContext = BackgroundAppointmentReminderContext(
            userID: userID,
            relationshipID: relationshipID,
            relationshipStatus: "closing"
        )
        var reconcileCallCount = 0
        let orchestrator = BackgroundAppointmentReminderReconcileOrchestrator(
            initialContext: initialContext,
            fetchAppointments: { _ in [] },
            revalidatedContext: { closingContext },
            reconcile: { _, _ in reconcileCallCount += 1 }
        )

        let didReconcile = try await orchestrator.run()

        #expect(!didReconcile)
        #expect(reconcileCallCount == 0)
    }

    @Test func backgroundAppointmentRefreshSkipsReconcileAfterRelationshipSwitch() async throws {
        let userID = UUID()
        let initialContext = BackgroundAppointmentReminderContext(
            userID: userID,
            relationshipID: UUID(),
            relationshipStatus: "active"
        )
        let switchedContext = BackgroundAppointmentReminderContext(
            userID: userID,
            relationshipID: UUID(),
            relationshipStatus: "active"
        )
        var reconcileCallCount = 0
        let orchestrator = BackgroundAppointmentReminderReconcileOrchestrator(
            initialContext: initialContext,
            fetchAppointments: { _ in [] },
            revalidatedContext: { switchedContext },
            reconcile: { _, _ in reconcileCallCount += 1 }
        )

        let didReconcile = try await orchestrator.run()

        #expect(!didReconcile)
        #expect(reconcileCallCount == 0)
    }

    @Test func backgroundAppointmentRefreshReconcilesUnchangedActiveContext() async throws {
        let context = BackgroundAppointmentReminderContext(
            userID: UUID(),
            relationshipID: UUID(),
            relationshipStatus: "active"
        )
        var reconcileCallCount = 0
        var events: [String] = []
        let orchestrator = BackgroundAppointmentReminderReconcileOrchestrator(
            initialContext: context,
            fetchAppointments: { _ in
                events.append("fetch")
                return []
            },
            revalidatedContext: {
                events.append("revalidate")
                return context
            },
            reconcile: { receivedContext, appointments in
                events.append("reconcile")
                #expect(receivedContext == context)
                #expect(appointments.isEmpty)
                reconcileCallCount += 1
            }
        )

        let didReconcile = try await orchestrator.run()

        #expect(didReconcile)
        #expect(reconcileCallCount == 1)
        #expect(events == ["fetch", "revalidate", "reconcile"])
    }

    @Test func backgroundAppointmentRefreshSkipsReconcileWhenTerminalCleanupWins() async throws {
        let context = BackgroundAppointmentReminderContext(
            userID: UUID(),
            relationshipID: UUID(),
            relationshipStatus: "active"
        )
        var events: [String] = []
        let orchestrator = BackgroundAppointmentReminderReconcileOrchestrator(
            initialContext: context,
            fetchAppointments: { _ in
                events.append("fetch")
                return []
            },
            revalidatedContext: {
                events.append("revalidate")
                return context
            },
            reconcile: { _, _ in
                events.append("reconcile")
            },
            activateIfContextUnchanged: {
                events.append("activate")
                return false
            }
        )

        let didReconcile = try await orchestrator.run()

        #expect(!didReconcile)
        #expect(events == ["fetch", "revalidate", "activate"])
    }

    @Test func reminderLifecycleConditionalActivationRejectsAStaleGeneration() {
        let gate = SharedAppointmentReminderLifecycleGate()
        let coldGeneration = gate.generation

        #expect(gate.activate(ifGenerationMatches: coldGeneration))
        #expect(gate.isActive)

        let activeGeneration = gate.generation
        gate.deactivate()

        #expect(!gate.activate(ifGenerationMatches: activeGeneration))
        #expect(!gate.isActive)
    }

    @Test func localSignOutWaitsForAuthenticatedContentTeardown() async {
        var events: [String] = []
        var stopContinuation: CheckedContinuation<Void, Never>?
        let teardown = Task {
            await AuthenticatedContentTeardown.run(
                stopActions: [{
                    events.append("stop-began")
                    await withCheckedContinuation { continuation in
                        stopContinuation = continuation
                    }
                    events.append("stop-finished")
                }],
                completion: { events.append("sign-out") }
            )
        }

        while stopContinuation == nil {
            await Task.yield()
        }
        #expect(events == ["stop-began"])

        stopContinuation?.resume()
        stopContinuation = nil
        await teardown.value

        #expect(events == ["stop-began", "stop-finished", "sign-out"])
    }
#endif

    @Test func meaningfulInteractionRequiresBothExpectedParticipantsOnOneObject() {
        let relationshipID = UUID()
        let interactionID = UUID()
        let first = UUID()
        let second = UUID()
        let expected = Set([first, second])
        let firstContribution = InteractionContribution(
            relationshipID: relationshipID,
            interactionID: interactionID,
            contentReferenceID: UUID(),
            participantID: first,
            surface: .moment,
            kind: .photo,
            occurredAt: Date(timeIntervalSince1970: 100)
        )
        let secondContribution = InteractionContribution(
            relationshipID: relationshipID,
            interactionID: interactionID,
            contentReferenceID: UUID(),
            participantID: second,
            surface: .moment,
            kind: .emoji,
            occurredAt: Date(timeIntervalSince1970: 200)
        )

        #expect(!MeaningfulInteractionRule.isSatisfied(
            by: [firstContribution, firstContribution],
            expectedParticipants: expected
        ))
        #expect(MeaningfulInteractionRule.isSatisfied(
            by: [firstContribution, secondContribution],
            expectedParticipants: expected
        ))
        #expect(MeaningfulInteractionRule.completionDate(
            for: [secondContribution, firstContribution],
            expectedParticipants: expected
        ) == Date(timeIntervalSince1970: 200))
    }

    @Test func meaningfulInteractionRejectsMixedObjectsAndDuplicateContentReferences() {
        let relationshipID = UUID()
        let first = UUID()
        let second = UUID()
        let sharedContentReferenceID = UUID()
        let firstContribution = InteractionContribution(
            relationshipID: relationshipID,
            interactionID: UUID(),
            contentReferenceID: sharedContentReferenceID,
            participantID: first,
            surface: .question,
            kind: .answer,
            occurredAt: Date(timeIntervalSince1970: 100)
        )
        let mixedObjectContribution = InteractionContribution(
            relationshipID: relationshipID,
            interactionID: UUID(),
            contentReferenceID: UUID(),
            participantID: second,
            surface: .question,
            kind: .answer,
            occurredAt: Date(timeIntervalSince1970: 200)
        )
        let duplicateReferenceContribution = InteractionContribution(
            relationshipID: relationshipID,
            interactionID: firstContribution.interactionID,
            contentReferenceID: sharedContentReferenceID,
            participantID: second,
            surface: .question,
            kind: .answer,
            occurredAt: Date(timeIntervalSince1970: 200)
        )

        #expect(!MeaningfulInteractionRule.isSatisfied(
            by: [firstContribution, mixedObjectContribution],
            expectedParticipants: [first, second]
        ))
        #expect(!MeaningfulInteractionRule.isSatisfied(
            by: [firstContribution, duplicateReferenceContribution],
            expectedParticipants: [first, second]
        ))
    }

    @Test func interactionContributionEncodingContainsReferencesButNoPrivateContent() throws {
        let contribution = InteractionContribution(
            relationshipID: UUID(),
            interactionID: UUID(),
            contentReferenceID: UUID(),
            participantID: UUID(),
            surface: .appointment,
            kind: .text,
            occurredAt: Date(timeIntervalSince1970: 100)
        )

        let encoded = try JSONEncoder().encode(contribution)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(json.contains("contentReferenceID"))
        #expect(json.contains("\"kind\":\"text\""))
        #expect(!json.contains("textContent"))
        #expect(!json.contains("photoURL"))
        #expect(!json.contains("emojiValue"))
        #expect(!json.contains("answerContent"))
    }

    @Test func bidirectionalChatActivityCountsOnePairWithinHalfOpenWeek() {
        let relationshipID = UUID()
        let otherRelationshipID = UUID()
        let first = UUID()
        let second = UUID()
        let week = DateInterval(
            start: Date(timeIntervalSince1970: 1_000),
            end: Date(timeIntervalSince1970: 2_000)
        )
        let messages = [
            ChatMessageActivity(
                relationshipID: relationshipID,
                contentReferenceID: UUID(),
                participantID: first,
                occurredAt: Date(timeIntervalSince1970: 1_100)
            ),
            ChatMessageActivity(
                relationshipID: relationshipID,
                contentReferenceID: UUID(),
                participantID: first,
                occurredAt: Date(timeIntervalSince1970: 1_200)
            ),
            ChatMessageActivity(
                relationshipID: otherRelationshipID,
                contentReferenceID: UUID(),
                participantID: second,
                occurredAt: Date(timeIntervalSince1970: 1_300)
            ),
            ChatMessageActivity(
                relationshipID: relationshipID,
                contentReferenceID: UUID(),
                participantID: second,
                occurredAt: week.end
            ),
        ]

        #expect(!BidirectionalChatActivityRule.isSatisfied(
            by: messages,
            relationshipID: relationshipID,
            expectedParticipants: [first, second],
            during: week
        ))

        let completedMessages = messages + [ChatMessageActivity(
            relationshipID: relationshipID,
            contentReferenceID: UUID(),
            participantID: second,
            occurredAt: Date(timeIntervalSince1970: 1_900)
        )]
        #expect(BidirectionalChatActivityRule.isSatisfied(
            by: completedMessages,
            relationshipID: relationshipID,
            expectedParticipants: [first, second],
            during: week
        ))
    }

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }

}

private final class ReminderLifecyclePairingServiceFake: PairingRemoteServing {
    var currentRelationshipValue: PairingRelationship?
    var ownPersonalArchiveValue: PersonalArchive?

    init(
        currentRelationship: PairingRelationship?,
        ownPersonalArchive: PersonalArchive? = nil
    ) {
        currentRelationshipValue = currentRelationship
        ownPersonalArchiveValue = ownPersonalArchive
    }

    func currentRelationship() async throws -> PairingRelationship? {
        currentRelationshipValue
    }

    func createInvitation() async throws -> PairingInvitation {
        throw ReminderLifecyclePairingServiceFakeError.unusedMethod
    }

    func acceptInvitation(identifier _: String) async throws -> UUID {
        throw ReminderLifecyclePairingServiceFakeError.unusedMethod
    }

    func declineInvitation(identifier _: String) async throws {
        throw ReminderLifecyclePairingServiceFakeError.unusedMethod
    }

    func cancelInvitation() async throws {
        throw ReminderLifecyclePairingServiceFakeError.unusedMethod
    }

    func unpairingReadiness(relationshipID _: UUID) async throws -> UnpairingReadiness {
        throw ReminderLifecyclePairingServiceFakeError.unusedMethod
    }

    func beginUnpairing(relationshipID _: UUID) async throws {
        throw ReminderLifecyclePairingServiceFakeError.unusedMethod
    }

    func sealPersonalArchive(relationshipID _: UUID) async throws -> PersonalArchive {
        throw ReminderLifecyclePairingServiceFakeError.unusedMethod
    }

    func ownPersonalArchive() async throws -> PersonalArchive? {
        ownPersonalArchiveValue
    }

    func personalArchive(relationshipID _: UUID) async throws -> PersonalArchive? {
        nil
    }

    func preparePersonalArchiveExport(
        archive _: PersonalArchive
    ) async throws -> PersonalArchiveExportPreparation {
        throw ReminderLifecyclePairingServiceFakeError.unusedMethod
    }
}

private enum ReminderLifecyclePairingServiceFakeError: Error {
    case unusedMethod
}

@MainActor
private final class SuspendedRelationshipReminderCleanup {
    private(set) var relationshipIDs: [UUID] = []
    private var continuation: CheckedContinuation<Void, Never>?

    func run(relationshipID: UUID) async {
        relationshipIDs.append(relationshipID)
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
