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

    @Test func personalArchiveExportBuildsDeterministicFolder() throws {
        let relationshipID = UUID(uuidString: "a0000000-0000-4000-8000-000000000001")!
        let messageID = UUID(uuidString: "a0000000-0000-4000-8000-000000000002")!
        let photoID = UUID(uuidString: "a0000000-0000-4000-8000-000000000003")!
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
            ],
            photos: [PersonalArchiveExportPhoto(
                clientID: photoID,
                jpegData: Data([0xff, 0xd8, 0xff, 0xd9])
            )]
        )

        let root = try package.fileWrapper()
        let rootFiles = try #require(root.fileWrappers)
        let manifestData = try #require(rootFiles["manifest.json"]?.regularFileContents)
        let photos = try #require(rootFiles["photos"]?.fileWrappers)
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
        #expect(photos[photoFileName]?.regularFileContents == Data([0xff, 0xd8, 0xff, 0xd9]))
    }

    @Test func personalArchiveExportRejectsMissingPhoto() {
        let photoID = UUID()
        #expect(throws: PersonalArchiveExportError.photoSetMismatch) {
            try PersonalArchiveExportPackage(
                relationshipID: UUID(),
                exportedAt: .now,
                items: [PersonalArchiveExportItem(
                    clientID: photoID,
                    kind: "photo",
                    createdAt: .now,
                    text: nil,
                    photoFile: PersonalArchiveExportPackage.photoFileName(clientID: photoID)
                )],
                photos: []
            )
        }
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
                )],
                photos: [PersonalArchiveExportPhoto(
                    clientID: photoID,
                    jpegData: Data([1])
                )]
            )
        }
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
    @Test func apnsTokenPresentationUsesHexAndOnlyExposesFingerprint() {
        let token = APNsDeviceTokenValue(Data([0x00, 0xab, 0xff, 0x10]))

        #expect(token.hex == "00abff10")
        #expect(token.fingerprint.count == 8)
        #expect(token.fingerprint != token.hex)
    }
#endif

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
