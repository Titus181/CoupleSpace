import Foundation
import Supabase

private struct PairingInvitationResponse: Decodable {
    let relationshipID: UUID
    let inviteToken: UUID
    let shortCode: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case relationshipID = "relationship_id"
        case inviteToken = "invite_token"
        case shortCode = "short_code"
        case expiresAt = "expires_at"
    }
}

private struct PairingInvitationParameters: Encodable {
    let providedIdentifier: String

    enum CodingKeys: String, CodingKey {
        case providedIdentifier = "provided_identifier"
    }
}

private struct PairingAcceptanceResponse: Decodable {
    let relationshipID: UUID?
    let result: String

    enum CodingKeys: String, CodingKey {
        case relationshipID = "relationship_id"
        case result
    }
}

private struct PairingRelationshipRow: Decodable {
    let id: UUID
    let status: String
}

private struct PairingRelationshipLifecycleParameters: Encodable {
    let targetRelationshipID: UUID

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
    }
}

private struct PairingMembershipRow: Decodable {
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
    }
}

private struct PairingSharedItemIdentityRow: Decodable {
    let creatorUserID: UUID?
    let itemKind: String?

    enum CodingKeys: String, CodingKey {
        case creatorUserID = "creator_user_id"
        case itemKind = "item_kind"
    }
}

private struct PairingArchivedItemIdentityRow: Decodable {
    let itemKind: String

    enum CodingKeys: String, CodingKey {
        case itemKind = "item_kind"
    }
}

private struct PairingPersonalArchiveRow: Decodable {
    let id: UUID
    let relationshipID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case relationshipID = "relationship_id"
    }
}

private struct PairingPersonalArchiveItemRow: Decodable {
    let clientID: UUID
    let itemKind: String
    let createdAt: Date
    let textContent: String?
    let mediaByteSize: Int64?

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case itemKind = "item_kind"
        case createdAt = "created_at"
        case textContent = "text_content"
        case mediaByteSize = "media_byte_size"
    }
}

protocol PairingRemoteServing {
    func cachedRelationship(userID: UUID) async -> PairingRelationship?
    func currentRelationship() async throws -> PairingRelationship?
    func createInvitation() async throws -> PairingInvitation
    func acceptInvitation(identifier: String) async throws -> UUID
    func declineInvitation(identifier: String) async throws
    func cancelInvitation() async throws
    func unpairingReadiness(relationshipID: UUID) async throws -> UnpairingReadiness
    func beginUnpairing(relationshipID: UUID) async throws
    func sealPersonalArchive(relationshipID: UUID) async throws -> PersonalArchive
    func ownPersonalArchive() async throws -> PersonalArchive?
    func personalArchive(relationshipID: UUID) async throws -> PersonalArchive?
    func preparePersonalArchiveExport(
        archive: PersonalArchive
    ) async throws -> PersonalArchiveExportPreparation
}

extension PairingRemoteServing {
    func cachedRelationship(userID: UUID) async -> PairingRelationship? { nil }

    func ownPersonalArchive() async throws -> PersonalArchive? { nil }

    func personalArchive(relationshipID _: UUID) async throws -> PersonalArchive? { nil }
}

struct PersonalArchiveExportPreparation {
    let document: PersonalArchiveExportDocument
    let fileName: String
    let stagingURL: URL
}

final class SupabasePairingService: PairingRemoteServing {
    private let client: SupabaseClient
    private let relationshipSnapshotStore: RelationshipSnapshotStore

    init(
        client: SupabaseClient,
        relationshipSnapshotStore: RelationshipSnapshotStore = RelationshipSnapshotStore()
    ) {
        self.client = client
        self.relationshipSnapshotStore = relationshipSnapshotStore
    }

    func cachedRelationship(userID: UUID) async -> PairingRelationship? {
        guard let snapshot = try? relationshipSnapshotStore.load(userID: userID),
              snapshot.status == "active"
        else { return nil }
        return PairingRelationship(
            id: snapshot.relationshipID,
            memberCount: snapshot.memberCount
        )
    }

    func currentRelationship() async throws -> PairingRelationship? {
        let session = try await client.auth.session
        do {
            let relationships: [PairingRelationshipRow] = try await client
                .from("relationships")
                .select("id,status")
                .limit(1)
                .execute()
                .value

            guard let relationship = relationships.first else {
                if let previous = try? relationshipSnapshotStore.load(userID: session.user.id) {
                    let didReconcileClosedRelationship: Bool
                    do {
                        try await reconcileConversationOutboxAfterRelationshipClosed(
                            userID: session.user.id,
                            relationshipID: previous.relationshipID
                        )
                        didReconcileClosedRelationship = true
                    } catch {
                        didReconcileClosedRelationship = false
                    }
                    await LocalSharedAppointmentReminderScheduler(
                        relationshipID: previous.relationshipID
                    ).removeAll()
                    if didReconcileClosedRelationship {
                        relationshipSnapshotStore.clear(userID: session.user.id)
                    }
                } else {
                    relationshipSnapshotStore.clear(userID: session.user.id)
                }
                ConversationSnapshotStore().clearAll(userID: session.user.id)
                ConversationPhotoCacheStore().clearAll(userID: session.user.id)
                TodaySnapshotStore().clearAll(userID: session.user.id)
                SharedAppointmentSnapshotStore().clearAll(userID: session.user.id)
                return nil
            }

            let members: [PairingMembershipRow] = try await client
                .from("relationship_members")
                .select("user_id")
                .eq("relationship_id", value: relationship.id)
                .eq("membership_status", value: "active")
                .execute()
                .value
            let result = PairingRelationship(
                id: relationship.id,
                memberCount: members.count,
                status: relationship.status
            )
            if let previous = try? relationshipSnapshotStore.load(userID: session.user.id),
               previous.relationshipID != result.id {
                try await reconcileConversationOutboxAfterRelationshipClosed(
                    userID: session.user.id,
                    relationshipID: previous.relationshipID
                )
                await LocalSharedAppointmentReminderScheduler(
                    relationshipID: previous.relationshipID
                ).removeAll()
                ConversationSnapshotStore().clearAll(userID: session.user.id)
                ConversationPhotoCacheStore().clearAll(userID: session.user.id)
                TodaySnapshotStore().clearAll(userID: session.user.id)
                SharedAppointmentSnapshotStore().clearAll(userID: session.user.id)
            }
            try? relationshipSnapshotStore.save(
                RelationshipSnapshot(
                    relationshipID: result.id,
                    status: result.status,
                    memberCount: result.memberCount
                ),
                userID: session.user.id
            )
            return result
        } catch {
            if let snapshot = try? relationshipSnapshotStore.load(userID: session.user.id),
               snapshot.status == "active" {
                return PairingRelationship(
                    id: snapshot.relationshipID,
                    memberCount: snapshot.memberCount
                )
            }
            throw error
        }
    }

    func unpairingReadiness(relationshipID: UUID) async throws -> UnpairingReadiness {
        let session = try await client.auth.session
        let userID = session.user.id
        let conversationStore = ConversationOutboxStore()
        var pendingCount = try conversationStore.load(
            userID: userID,
            relationshipID: relationshipID
        ).entries.count
        for appointmentID in conversationStore.appointmentDiscussionScopeIDs(
            userID: userID,
            relationshipID: relationshipID
        ) {
            pendingCount += try ConversationOutboxStore(appointmentScopeID: appointmentID)
                .load(userID: userID, relationshipID: relationshipID)
                .entries.count
        }
        pendingCount += try SharedAppointmentOutboxStore()
            .load(userID: userID, relationshipID: relationshipID)
            .entries.count
        pendingCount += try SharedAppointmentOperationOutboxStore()
            .load(userID: userID, relationshipID: relationshipID)
            .entries.count
        return pendingCount == 0 ? .ready : .pendingContent(count: pendingCount)
    }

    func beginUnpairing(relationshipID: UUID) async throws {
        try await client
            .rpc(
                "begin_unpairing",
                params: PairingRelationshipLifecycleParameters(
                    targetRelationshipID: relationshipID
                )
            )
            .execute()
        await LocalSharedAppointmentReminderScheduler(relationshipID: relationshipID).removeAll()
    }

    func sealPersonalArchive(relationshipID: UUID) async throws -> PersonalArchive {
        let archiveID: UUID = try await client
            .rpc(
                "seal_personal_archive",
                params: PairingRelationshipLifecycleParameters(
                    targetRelationshipID: relationshipID
                )
            )
            .execute()
            .value
        return PersonalArchive(id: archiveID, relationshipID: relationshipID)
    }

    func ownPersonalArchive() async throws -> PersonalArchive? {
        let archives: [PairingPersonalArchiveRow] = try await client
            .from("personal_archives")
            .select("id,relationship_id")
            .order("sealed_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return archives.first.map {
            PersonalArchive(id: $0.id, relationshipID: $0.relationshipID)
        }
    }

    func personalArchive(relationshipID: UUID) async throws -> PersonalArchive? {
        let archives: [PairingPersonalArchiveRow] = try await client
            .from("personal_archives")
            .select("id,relationship_id")
            .eq("relationship_id", value: relationshipID)
            .order("sealed_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return archives.first.map {
            PersonalArchive(id: $0.id, relationshipID: $0.relationshipID)
        }
    }

    func preparePersonalArchiveExport(
        archive: PersonalArchive
    ) async throws -> PersonalArchiveExportPreparation {
        try PersonalArchiveExportStaging.cleanupAbandoned()
        _ = try await client.auth.session
        let rows: [PairingPersonalArchiveItemRow] = try await client
            .from("personal_archive_items")
            .select("client_id,item_kind,created_at,text_content,media_byte_size")
            .eq("archive_id", value: archive.id)
            .order("created_at", ascending: true)
            .order("client_id", ascending: true)
            .execute()
            .value
        let items = rows.map { row in
            PersonalArchiveExportItem(
                clientID: row.clientID,
                kind: row.itemKind,
                createdAt: row.createdAt,
                text: row.textContent,
                photoFile: row.itemKind == "photo"
                    ? PersonalArchiveExportPackage.photoFileName(clientID: row.clientID)
                    : nil
            )
        }
        let package = try PersonalArchiveExportPackage(
            relationshipID: archive.relationshipID,
            exportedAt: .now,
            items: items
        )
        let requiredBytes = PersonalArchiveExportCapacityPolicy.requiredBytes(
            manifestByteCount: try package.manifestData().count,
            photoByteSizes: rows
                .filter { $0.itemKind == "photo" }
                .map(\.mediaByteSize)
        )
        guard PersonalArchiveExportCapacityPolicy.permitsStaging(
            requiredBytes: requiredBytes,
            availableBytes: PersonalArchiveExportCapacityPolicy.availableBytes(
                at: FileManager.default.temporaryDirectory
            )
        ) else {
            throw PersonalArchiveExportError.insufficientStagingCapacity
        }

        var staging = try PersonalArchiveExportStaging(package: package)
        do {
            for row in rows where row.itemKind == "photo" {
                let data = try await client.storage
                    .from("couplespace-w1-photos")
                    .download(path: "\(archive.relationshipID.uuidString.lowercased())/\(row.clientID.uuidString.lowercased()).jpg")
                try staging.writePhoto(clientID: row.clientID, jpegData: data)
            }
            let fileName = "CoupleSpace-personal-archive-\(archive.relationshipID.uuidString.lowercased().prefix(8))"
            return try PersonalArchiveExportPreparation(
                document: PersonalArchiveExportDocument(
                    staging: staging,
                    exportFileName: fileName
                ),
                fileName: fileName,
                stagingURL: staging.directoryURL
            )
        } catch {
            try? staging.remove()
            throw error
        }
    }

    private func reconcileConversationOutboxAfterRelationshipClosed(
        userID: UUID,
        relationshipID: UUID
    ) async throws {
        let outboxStore = ConversationOutboxStore()
        let archives: [PairingPersonalArchiveRow] = try await client
            .from("personal_archives")
            .select("id")
            .eq("relationship_id", value: relationshipID)
            .eq("owner_user_id", value: userID)
            .limit(1)
            .execute()
            .value
        let archiveID = archives.first?.id

        try await reconcileConversationOutbox(
            outboxStore,
            userID: userID,
            relationshipID: relationshipID,
            archiveID: archiveID
        )
        for appointmentID in outboxStore.appointmentDiscussionScopeIDs(
            userID: userID,
            relationshipID: relationshipID
        ) {
            try await reconcileConversationOutbox(
                ConversationOutboxStore(appointmentScopeID: appointmentID),
                userID: userID,
                relationshipID: relationshipID,
                archiveID: archiveID
            )
        }
        outboxStore.clearAppointmentDiscussions(
            userID: userID,
            relationshipID: relationshipID
        )
    }

    private func reconcileConversationOutbox(
        _ outboxStore: ConversationOutboxStore,
        userID: UUID,
        relationshipID: UUID,
        archiveID: UUID?
    ) async throws {
        while let entry = try outboxStore.load(
            userID: userID,
            relationshipID: relationshipID
        ).entries.first {
            let action: ConversationOutboxLifecyclePolicy.ClosedRelationshipAction
            if let archiveID {
                let archivedItems: [PairingArchivedItemIdentityRow] = try await client
                    .from("personal_archive_items")
                    .select("item_kind")
                    .eq("archive_id", value: archiveID)
                    .eq("client_id", value: entry.clientID)
                    .limit(1)
                    .execute()
                    .value
                action = try ConversationOutboxLifecyclePolicy.actionForArchivedRelationship(
                    content: entry.content,
                    archivedItemKind: archivedItems.first?.itemKind
                )
            } else {
                let sharedItems: [PairingSharedItemIdentityRow] = try await client
                    .from("shared_items")
                    .select("creator_user_id,item_kind")
                    .eq("relationship_id", value: relationshipID)
                    .eq("client_id", value: entry.clientID)
                    .limit(1)
                    .execute()
                    .value
                action = try ConversationOutboxLifecyclePolicy.actionForClosingRelationship(
                    content: entry.content,
                    remoteCreatorID: sharedItems.first?.creatorUserID,
                    remoteItemKind: sharedItems.first?.itemKind,
                    currentUserID: userID
                )
            }

            if action == .deleteOrphanPhoto {
                try await client.storage
                    .from("couplespace-w1-photos")
                    .remove(paths: [
                        relationshipID.uuidString.lowercased()
                            + "/" + entry.clientID.uuidString.lowercased() + ".jpg"
                    ])
            }
            try outboxStore.acknowledgeFirst(
                clientID: entry.clientID,
                userID: userID,
                relationshipID: relationshipID
            )
        }
    }

    func createInvitation() async throws -> PairingInvitation {
        let session = try await client.auth.session
        let responses: [PairingInvitationResponse] = try await client
            .rpc("create_relationship_invitation_v2")
            .execute()
            .value

        guard let response = responses.first else {
            throw PairingServiceError.missingInvitation
        }

        let invitation = PairingInvitation(
            relationshipID: response.relationshipID,
            token: response.inviteToken,
            shortCode: response.shortCode,
            expiresAt: response.expiresAt
        )
        try? relationshipSnapshotStore.save(
            RelationshipSnapshot(
                relationshipID: invitation.relationshipID,
                status: "active",
                memberCount: 1
            ),
            userID: session.user.id
        )
        return invitation
    }

    func acceptInvitation(identifier: String) async throws -> UUID {
        let session = try await client.auth.session
        let responses: [PairingAcceptanceResponse] = try await client
            .rpc(
                "accept_relationship_invitation_v2",
                params: PairingInvitationParameters(providedIdentifier: identifier)
            )
            .execute()
            .value
        guard let response = responses.first,
              response.result == "accepted",
              let relationshipID = response.relationshipID
        else { throw PairingServiceError.invitationNotAvailable }
        try? relationshipSnapshotStore.save(
            RelationshipSnapshot(
                relationshipID: relationshipID,
                status: "active",
                memberCount: 2
            ),
            userID: session.user.id
        )
        return relationshipID
    }

    func declineInvitation(identifier: String) async throws {
        _ = try await client.auth.session
        let result: String = try await client
            .rpc(
                "decline_relationship_invitation_v2",
                params: PairingInvitationParameters(providedIdentifier: identifier)
            )
            .execute()
            .value
        guard result == "declined" else {
            throw PairingServiceError.invitationNotAvailable
        }
    }

    func cancelInvitation() async throws {
        let session = try await client.auth.session
        try await client
            .rpc("cancel_relationship_invitation")
            .execute()
        relationshipSnapshotStore.clear(userID: session.user.id)
    }
}

private enum PairingServiceError: LocalizedError {
    case missingInvitation
    case invitationNotAvailable

    var errorDescription: String? {
        switch self {
        case .missingInvitation: "missing_invitation"
        case .invitationNotAvailable: "invitation_not_available"
        }
    }
}
