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
    func currentRelationship() async throws -> PairingRelationship?
    func createInvitation() async throws -> PairingInvitation
    func acceptInvitation(token: UUID) async throws -> UUID
    func declineInvitation(token: UUID) async throws
    func cancelInvitation() async throws
}

final class SupabasePairingService: PairingRemoteServing {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func currentRelationship() async throws -> PairingRelationship? {
        _ = try await client.auth.session
        let relationships: [PairingRelationshipRow] = try await client
            .from("relationships")
            .select("id")
            .eq("status", value: "active")
            .limit(1)
            .execute()
            .value

        guard let relationship = relationships.first else { return nil }

        let members: [PairingMembershipRow] = try await client
            .from("relationship_members")
            .select("user_id")
            .eq("relationship_id", value: relationship.id)
            .eq("membership_status", value: "active")
            .execute()
            .value

        return PairingRelationship(id: relationship.id, memberCount: members.count)
    }

    func createInvitation() async throws -> PairingInvitation {
        _ = try await client.auth.session
        let responses: [PairingInvitationResponse] = try await client
            .rpc("create_relationship_invitation")
            .execute()
            .value

        guard let response = responses.first else {
            throw PairingServiceError.missingInvitation
        }

        return PairingInvitation(
            relationshipID: response.relationshipID,
            token: response.inviteToken,
            expiresAt: response.expiresAt
        )
    }

    func acceptInvitation(token: UUID) async throws -> UUID {
        _ = try await client.auth.session
        return try await client
            .rpc(
                "accept_relationship_invitation",
                params: PairingInvitationParameters(providedInviteToken: token)
            )
            .execute()
            .value
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
        _ = try await client.auth.session
        try await client
            .rpc("cancel_relationship_invitation")
            .execute()
    }
}

private enum PairingServiceError: Error {
    case missingInvitation
}
