import Foundation
import Supabase

@MainActor
protocol TogetherNowRemoteServing: AnyObject {
    func fetchSnapshot() async throws -> TogetherNowSnapshot
    func updateNames(displayName: String?, privatePartnerName: String?) async throws
    func setStatus(
        _ draft: CurrentStatusDraft,
        tonightExpiresAt: Date?,
        momentClientID: UUID?
    ) async throws -> CurrentRelationshipStatus
    func clearStatus() async throws
    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws
    func stopObservingChanges() async
}

private struct TogetherNowMembershipRow: Decodable {
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
    }
}

private struct UserProfileRow: Decodable {
    let userID: UUID
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
    }
}

private struct PartnerAliasRow: Decodable {
    let ownerUserID: UUID
    let partnerUserID: UUID
    let privateName: String

    enum CodingKeys: String, CodingKey {
        case ownerUserID = "owner_user_id"
        case partnerUserID = "partner_user_id"
        case privateName = "private_name"
    }
}

private struct CurrentStatusRow: Decodable {
    let userID: UUID
    let statusKind: String
    let customText: String?
    let expirationKind: String
    let expiresAt: Date?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case statusKind = "status_kind"
        case customText = "custom_text"
        case expirationKind = "expiration_kind"
        case expiresAt = "expires_at"
        case updatedAt = "updated_at"
    }

    func status() throws -> CurrentRelationshipStatus {
        let content: CurrentStatusContent
        if statusKind == "custom" {
            guard let customText else { throw TogetherNowServiceError.invalidServerState }
            content = .custom(customText)
        } else {
            guard let kind = CurrentStatusKind(rawValue: statusKind) else {
                throw TogetherNowServiceError.invalidServerState
            }
            content = .fixed(kind)
        }
        guard let expiration = CurrentStatusExpiration(rawValue: expirationKind) else {
            throw TogetherNowServiceError.invalidServerState
        }
        return CurrentRelationshipStatus(
            userID: userID,
            content: content,
            expiration: expiration,
            expiresAt: expiresAt,
            updatedAt: updatedAt
        )
    }
}

private struct UpdateRelationshipNamesParameters: Encodable {
    let targetRelationshipID: UUID
    let targetDisplayName: String?
    let targetPartnerName: String?

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetDisplayName = "target_display_name"
        case targetPartnerName = "target_partner_name"
    }
}

private struct SetCurrentStatusParameters: Encodable {
    let targetRelationshipID: UUID
    let targetStatusKind: String
    let targetCustomText: String?
    let targetExpirationKind: String
    let targetTonightExpiresAt: Date?
    let targetMomentClientID: UUID?

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetStatusKind = "target_status_kind"
        case targetCustomText = "target_custom_text"
        case targetExpirationKind = "target_expiration_kind"
        case targetTonightExpiresAt = "target_tonight_expires_at"
        case targetMomentClientID = "target_moment_client_id"
    }
}

private struct RelationshipIDParameter: Encodable {
    let targetRelationshipID: UUID

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
    }
}

@MainActor
final class SupabaseTogetherNowService: TogetherNowRemoteServing {
    private let client: SupabaseClient
    private let relationshipID: UUID
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTasks: [Task<Void, Never>] = []

    init(client: SupabaseClient, relationshipID: UUID) {
        self.client = client
        self.relationshipID = relationshipID
    }

    func fetchSnapshot() async throws -> TogetherNowSnapshot {
        let session = try await client.auth.session
        let currentUserID = session.user.id
        let memberships: [TogetherNowMembershipRow] = try await client
            .from("relationship_members")
            .select("user_id")
            .eq("relationship_id", value: relationshipID)
            .eq("membership_status", value: "active")
            .execute()
            .value
        guard let partnerUserID = memberships.map(\.userID).first(where: { $0 != currentUserID }) else {
            throw TogetherNowServiceError.missingPartner
        }

        let profiles: [UserProfileRow] = try await client
            .from("user_profiles")
            .select("user_id,display_name")
            .execute()
            .value
        let aliases: [PartnerAliasRow] = try await client
            .from("relationship_partner_aliases")
            .select("owner_user_id,partner_user_id,private_name")
            .eq("relationship_id", value: relationshipID)
            .execute()
            .value
        let statusRows: [CurrentStatusRow] = try await client
            .from("current_relationship_statuses")
            .select("user_id,status_kind,custom_text,expiration_kind,expires_at,updated_at")
            .eq("relationship_id", value: relationshipID)
            .execute()
            .value
        let statuses = try statusRows.map { try $0.status() }

        return TogetherNowSnapshot(
            currentUserID: currentUserID,
            partnerUserID: partnerUserID,
            currentDisplayName: profiles.first { $0.userID == currentUserID }?.displayName,
            partnerDisplayName: profiles.first { $0.userID == partnerUserID }?.displayName,
            privatePartnerName: aliases.first {
                $0.ownerUserID == currentUserID && $0.partnerUserID == partnerUserID
            }?.privateName,
            currentStatus: statuses.first { $0.userID == currentUserID },
            partnerStatus: statuses.first { $0.userID == partnerUserID }
        )
    }

    func updateNames(displayName: String?, privatePartnerName: String?) async throws {
        _ = try await client.auth.session
        try await client.rpc(
            "update_relationship_names",
            params: UpdateRelationshipNamesParameters(
                targetRelationshipID: relationshipID,
                targetDisplayName: displayName,
                targetPartnerName: privatePartnerName
            )
        ).execute()
    }

    func setStatus(
        _ draft: CurrentStatusDraft,
        tonightExpiresAt: Date?,
        momentClientID: UUID?
    ) async throws -> CurrentRelationshipStatus {
        _ = try await client.auth.session
        let statusKind: String
        let customText: String?
        switch draft.content {
        case let .fixed(kind):
            statusKind = kind.rawValue
            customText = nil
        case let .custom(value):
            guard let value = TogetherNowTextPolicy.normalizedCustomStatus(value) else {
                throw TogetherNowServiceError.invalidDraft
            }
            statusKind = "custom"
            customText = value
        }
        let rows: [CurrentStatusRow] = try await client.rpc(
            "set_current_relationship_status",
            params: SetCurrentStatusParameters(
                targetRelationshipID: relationshipID,
                targetStatusKind: statusKind,
                targetCustomText: customText,
                targetExpirationKind: draft.expiration.rawValue,
                targetTonightExpiresAt: tonightExpiresAt,
                targetMomentClientID: momentClientID
            )
        ).execute().value
        guard let row = rows.first else { throw TogetherNowServiceError.missingSavedStatus }
        return try row.status()
    }

    func clearStatus() async throws {
        _ = try await client.auth.session
        try await client.rpc(
            "clear_current_relationship_status",
            params: RelationshipIDParameter(targetRelationshipID: relationshipID)
        ).execute()
    }

    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws {
        await stopObservingChanges()
        let channel = client.channel("together-now-\(UUID().uuidString.lowercased())")
        let profiles = channel.postgresChange(AnyAction.self, schema: "public", table: "user_profiles")
        let aliases = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "relationship_partner_aliases",
            filter: .eq("relationship_id", value: relationshipID.uuidString.lowercased())
        )
        let statuses = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "current_relationship_statuses",
            filter: .eq("relationship_id", value: relationshipID.uuidString.lowercased())
        )
        realtimeChannel = channel
        realtimeTasks = [profiles, aliases, statuses].map { stream in
            Task {
                for await _ in stream {
                    guard !Task.isCancelled else { return }
                    await onChange()
                }
            }
        }
        do {
            try await channel.subscribeWithError()
        } catch {
            realtimeTasks.forEach { $0.cancel() }
            realtimeTasks = []
            realtimeChannel = nil
            await client.removeChannel(channel)
            throw error
        }
    }

    func stopObservingChanges() async {
        realtimeTasks.forEach { $0.cancel() }
        realtimeTasks = []
        if let realtimeChannel {
            await client.removeChannel(realtimeChannel)
            self.realtimeChannel = nil
        }
    }
}

private enum TogetherNowServiceError: LocalizedError {
    case invalidDraft
    case invalidServerState
    case missingPartner
    case missingSavedStatus

    var errorDescription: String? {
        switch self {
        case .invalidDraft: "狀態內容不完整。"
        case .invalidServerState: "無法讀取現在的我們。"
        case .missingPartner: "找不到目前的伴侶關係。"
        case .missingSavedStatus: "伺服器未回傳更新後的狀態。"
        }
    }
}

@MainActor
final class InMemoryTogetherNowService: TogetherNowRemoteServing {
    private var snapshot: TogetherNowSnapshot
    private var onChange: (@MainActor () async -> Void)?

    init(snapshot: TogetherNowSnapshot = .preview) {
        self.snapshot = snapshot
    }

    func fetchSnapshot() async throws -> TogetherNowSnapshot { snapshot }

    func updateNames(displayName: String?, privatePartnerName: String?) async throws {
        snapshot = TogetherNowSnapshot(
            currentUserID: snapshot.currentUserID,
            partnerUserID: snapshot.partnerUserID,
            currentDisplayName: displayName,
            partnerDisplayName: snapshot.partnerDisplayName,
            privatePartnerName: privatePartnerName,
            currentStatus: snapshot.currentStatus,
            partnerStatus: snapshot.partnerStatus
        )
    }

    func setStatus(
        _ draft: CurrentStatusDraft,
        tonightExpiresAt: Date?,
        momentClientID: UUID?
    ) async throws -> CurrentRelationshipStatus {
        let expiresAt: Date?
        switch draft.expiration {
        case .oneHour: expiresAt = Date().addingTimeInterval(3_600)
        case .fourHours: expiresAt = Date().addingTimeInterval(14_400)
        case .tonight: expiresAt = tonightExpiresAt
        case .manual: expiresAt = nil
        }
        let status = CurrentRelationshipStatus(
            userID: snapshot.currentUserID,
            content: draft.content,
            expiration: draft.expiration,
            expiresAt: expiresAt,
            updatedAt: .now
        )
        snapshot = TogetherNowSnapshot(
            currentUserID: snapshot.currentUserID,
            partnerUserID: snapshot.partnerUserID,
            currentDisplayName: snapshot.currentDisplayName,
            partnerDisplayName: snapshot.partnerDisplayName,
            privatePartnerName: snapshot.privatePartnerName,
            currentStatus: status,
            partnerStatus: snapshot.partnerStatus
        )
        return status
    }

    func clearStatus() async throws {
        snapshot = TogetherNowSnapshot(
            currentUserID: snapshot.currentUserID,
            partnerUserID: snapshot.partnerUserID,
            currentDisplayName: snapshot.currentDisplayName,
            partnerDisplayName: snapshot.partnerDisplayName,
            privatePartnerName: snapshot.privatePartnerName,
            currentStatus: nil,
            partnerStatus: snapshot.partnerStatus
        )
    }

    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws {
        self.onChange = onChange
    }

    func stopObservingChanges() async {
        onChange = nil
    }
}

extension TogetherNowSnapshot {
    nonisolated static let preview: TogetherNowSnapshot = {
        let currentUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
        let partnerUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D2")!
        return TogetherNowSnapshot(
            currentUserID: currentUserID,
            partnerUserID: partnerUserID,
            currentDisplayName: nil,
            partnerDisplayName: "伴侶",
            privatePartnerName: nil,
            currentStatus: nil,
            partnerStatus: nil
        )
    }()
}
