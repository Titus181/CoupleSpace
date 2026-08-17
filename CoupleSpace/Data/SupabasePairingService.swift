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
}

protocol PairingRemoteServing {
    func cachedRelationship(userID: UUID) async -> PairingRelationship?
    func currentRelationship() async throws -> PairingRelationship?
    func createInvitation() async throws -> PairingInvitation
    func acceptInvitation(identifier: String) async throws -> UUID
    func declineInvitation(identifier: String) async throws
    func cancelInvitation() async throws
}

extension PairingRemoteServing {
    func cachedRelationship(userID: UUID) async -> PairingRelationship? { nil }
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
                .select("id")
                .eq("status", value: "active")
                .limit(1)
                .execute()
                .value

            guard let relationship = relationships.first else {
                if let previous = try? relationshipSnapshotStore.load(userID: session.user.id) {
                    try await reconcileConversationOutboxAfterRelationshipClosed(
                        userID: session.user.id,
                        relationshipID: previous.relationshipID
                    )
                    await LocalSharedAppointmentReminderScheduler(
                        relationshipID: previous.relationshipID
                    ).removeAll()
                }
                relationshipSnapshotStore.clear(userID: session.user.id)
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
            let result = PairingRelationship(id: relationship.id, memberCount: members.count)
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
                    status: "active",
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
