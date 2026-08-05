import Combine
import Foundation
import Supabase

private struct PairingInvitationResponse: Decodable {
    let relationshipID: UUID
    let inviteToken: UUID

    enum CodingKeys: String, CodingKey {
        case relationshipID = "relationship_id"
        case inviteToken = "invite_token"
    }
}

private struct AcceptPairingInvitationParameters: Encodable {
    let providedInviteToken: UUID

    enum CodingKeys: String, CodingKey {
        case providedInviteToken = "provided_invite_token"
    }
}

private struct RelationshipRow: Decodable {
    let id: UUID
    let status: String
}

private struct RelationshipMembershipRow: Decodable {
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
    }
}

private struct SharedMarkerRow: Decodable {
    let clientID: UUID

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
    }
}

private struct SharedMarkerInsert: Encodable {
    let relationshipID: UUID
    let clientID: UUID
    let creatorUserID: UUID
    let itemKind = "marker"

    enum CodingKeys: String, CodingKey {
        case relationshipID = "relationship_id"
        case clientID = "client_id"
        case creatorUserID = "creator_user_id"
        case itemKind = "item_kind"
    }
}

@MainActor
final class SupabasePairingPoC: ObservableObject {
    @Published private(set) var status = "登入後可開始雙身分 RLS 驗證"
    @Published private(set) var relationshipToken = "尚無關係"
    @Published private(set) var memberCount = 0
    @Published private(set) var latestMarkerToken = "尚無標記"
    @Published private(set) var invitationToken: String?

    private let client: SupabaseClient
    private var relationshipID: UUID?

    init(client: SupabaseClient) {
        self.client = client
    }

    func createInvitation() async {
        do {
            _ = try await client.auth.session
            let invitations: [PairingInvitationResponse] = try await client
                .rpc("create_relationship_invitation")
                .execute()
                .value
            guard let invitation = invitations.first else {
                status = "伺服器未回傳 pairing invitation"
                return
            }

            relationshipID = invitation.relationshipID
            relationshipToken = shortToken(invitation.relationshipID)
            invitationToken = invitation.inviteToken.uuidString.lowercased()
            status = "邀請已建立；請由另一個 Apple ID 接受"
            await refresh()
        } catch {
            reportFailure("建立邀請", error: error)
        }
    }

    func acceptInvitation(_ rawToken: String) async {
        guard let inviteToken = UUID(uuidString: rawToken.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            status = "邀請 token 格式不正確"
            return
        }

        do {
            _ = try await client.auth.session
            let acceptedRelationshipID: UUID = try await client
                .rpc(
                    "accept_relationship_invitation",
                    params: AcceptPairingInvitationParameters(
                        providedInviteToken: inviteToken
                    )
                )
                .execute()
                .value
            relationshipID = acceptedRelationshipID
            relationshipToken = shortToken(acceptedRelationshipID)
            invitationToken = nil
            status = "已接受邀請"
            await refresh()
        } catch {
            reportFailure("接受邀請", error: error)
        }
    }

    func writeMarker() async {
        guard let relationshipID else {
            status = "請先建立或加入測試關係"
            return
        }

        do {
            let session = try await client.auth.session
            let markerID = UUID()
            try await client
                .from("shared_items")
                .insert(SharedMarkerInsert(
                    relationshipID: relationshipID,
                    clientID: markerID,
                    creatorUserID: session.user.id
                ))
                .execute()
            status = "已寫入 RLS 驗證標記"
            await refresh()
        } catch {
            reportFailure("寫入標記", error: error)
        }
    }

    func refresh() async {
        do {
            _ = try await client.auth.session
            let relationships: [RelationshipRow] = try await client
                .from("relationships")
                .select("id,status")
                .limit(1)
                .execute()
                .value

            guard let relationship = relationships.first else {
                reset(message: "尚未建立 Supabase 測試關係")
                return
            }

            relationshipID = relationship.id
            relationshipToken = shortToken(relationship.id)

            let memberships: [RelationshipMembershipRow] = try await client
                .from("relationship_members")
                .select("user_id")
                .eq("relationship_id", value: relationship.id)
                .execute()
                .value
            memberCount = memberships.count

            let markers: [SharedMarkerRow] = try await client
                .from("shared_items")
                .select("client_id")
                .eq("relationship_id", value: relationship.id)
                .eq("item_kind", value: "marker")
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            latestMarkerToken = markers.first.map { shortToken($0.clientID) } ?? "尚無標記"
            status = "關係：\(relationship.status)，成員：\(memberCount)/2"
        } catch {
            reportFailure("重新整理 RLS 狀態", error: error)
        }
    }

    func reset(message: String = "登入後可開始雙身分 RLS 驗證") {
        relationshipID = nil
        relationshipToken = "尚無關係"
        memberCount = 0
        latestMarkerToken = "尚無標記"
        invitationToken = nil
        status = message
    }

    private func shortToken(_ id: UUID) -> String {
        String(id.uuidString.lowercased().prefix(8))
    }

    private func reportFailure(_ action: String, error: Error) {
        status = "\(action)失敗：\(error.localizedDescription)"
    }
}
