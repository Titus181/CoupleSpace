import Foundation
import Supabase

private struct PairingInvitationResponse: Decodable {
    let relationshipID: UUID
    let inviteToken: UUID
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case relationshipID = "relationship_id"
        case inviteToken = "invite_token"
        case expiresAt = "expires_at"
    }
}

private struct PairingInvitationParameters: Encodable {
    let providedInviteToken: UUID

    enum CodingKeys: String, CodingKey {
        case providedInviteToken = "provided_invite_token"
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

protocol PairingRemoteServing {
    func cachedRelationship(userID: UUID) async -> PairingRelationship?
    func currentRelationship() async throws -> PairingRelationship?
    func createInvitation() async throws -> PairingInvitation
    func acceptInvitation(token: UUID) async throws -> UUID
    func declineInvitation(token: UUID) async throws
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
                relationshipSnapshotStore.clear(userID: session.user.id)
                ConversationOutboxStore().clearAll(userID: session.user.id)
                ConversationSnapshotStore().clearAll(userID: session.user.id)
                TodaySnapshotStore().clearAll(userID: session.user.id)
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
                ConversationOutboxStore().clearAll(userID: session.user.id)
                ConversationSnapshotStore().clearAll(userID: session.user.id)
                TodaySnapshotStore().clearAll(userID: session.user.id)
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

    func createInvitation() async throws -> PairingInvitation {
        let session = try await client.auth.session
        let responses: [PairingInvitationResponse] = try await client
            .rpc("create_relationship_invitation")
            .execute()
            .value

        guard let response = responses.first else {
            throw PairingServiceError.missingInvitation
        }

        let invitation = PairingInvitation(
            relationshipID: response.relationshipID,
            token: response.inviteToken,
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

    func acceptInvitation(token: UUID) async throws -> UUID {
        let session = try await client.auth.session
        let relationshipID: UUID = try await client
            .rpc(
                "accept_relationship_invitation",
                params: PairingInvitationParameters(providedInviteToken: token)
            )
            .execute()
            .value
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

    func declineInvitation(token: UUID) async throws {
        _ = try await client.auth.session
        try await client
            .rpc(
                "decline_relationship_invitation",
                params: PairingInvitationParameters(providedInviteToken: token)
            )
            .execute()
    }

    func cancelInvitation() async throws {
        let session = try await client.auth.session
        try await client
            .rpc("cancel_relationship_invitation")
            .execute()
        relationshipSnapshotStore.clear(userID: session.user.id)
    }
}

private enum PairingServiceError: Error {
    case missingInvitation
}
