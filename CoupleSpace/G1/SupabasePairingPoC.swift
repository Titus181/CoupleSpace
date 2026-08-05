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

private struct RelationshipLifecycleParameters: Encodable {
    let targetRelationshipID: UUID

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
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

private struct SharedPhotoRow: Decodable {
    let clientID: UUID

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
    }
}

private struct SharedItemInsert: Encodable {
    let relationshipID: UUID
    let clientID: UUID
    let creatorUserID: UUID
    let itemKind: String

    enum CodingKeys: String, CodingKey {
        case relationshipID = "relationship_id"
        case clientID = "client_id"
        case creatorUserID = "creator_user_id"
        case itemKind = "item_kind"
    }
}

private struct PersonalArchiveRow: Decodable {
    let id: UUID
    let relationshipID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case relationshipID = "relationship_id"
    }
}

private struct PersonalArchiveItemRow: Decodable {
    let clientID: UUID
    let itemKind: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
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
    @Published private(set) var realtimeStatus = "尚未啟動 Realtime"
    @Published private(set) var isRealtimeActive = false
    @Published private(set) var storageStatus = "尚無 Supabase Storage 照片"
    @Published private(set) var storagePhotoData: Data?
    @Published private(set) var relationshipStatus: String?
    @Published private(set) var lifecycleStatus = "尚未開始資料生命週期驗證"
    @Published private(set) var personalArchiveItemCount = 0
    @Published private(set) var hasPersonalArchive = false

    private let client: SupabaseClient
    private var relationshipID: UUID?
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTask: Task<Void, Never>?

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
                .insert(SharedItemInsert(
                    relationshipID: relationshipID,
                    clientID: markerID,
                    creatorUserID: session.user.id,
                    itemKind: "marker"
                ))
                .execute()
            status = "已寫入 RLS 驗證標記"
            await refresh()
        } catch {
            reportFailure("寫入標記", error: error)
        }
    }

    func beginUnpairing() async {
        guard let relationshipID else {
            lifecycleStatus = "請先建立或加入測試關係"
            return
        }

        do {
            try await client
                .rpc(
                    "begin_unpairing",
                    params: RelationshipLifecycleParameters(
                        targetRelationshipID: relationshipID
                    )
                )
                .execute()
            lifecycleStatus = "關係已進入 closing；共同內容應停止新增"
            await refresh()
        } catch {
            lifecycleStatus = "開始解除配對失敗：\(error.localizedDescription)"
        }
    }

    func sealPersonalArchive() async {
        guard let relationshipID else {
            lifecycleStatus = "請先建立或加入測試關係"
            return
        }

        do {
            let archiveID: UUID = try await client
                .rpc(
                    "seal_personal_archive",
                    params: RelationshipLifecycleParameters(
                        targetRelationshipID: relationshipID
                    )
                )
                .execute()
                .value
            lifecycleStatus = "個人唯讀封存已建立：\(shortToken(archiveID))"
            await refresh()
        } catch {
            lifecycleStatus = "建立個人封存失敗：\(error.localizedDescription)"
        }
    }

    func startRealtime() async {
        guard let relationshipID else {
            realtimeStatus = "請先建立或加入測試關係"
            return
        }

        await stopRealtime()

        let channel = client.channel("w1-shared-items-\(UUID().uuidString.lowercased())")
        let changes = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "shared_items",
            filter: .eq(
                "relationship_id",
                value: relationshipID.uuidString.lowercased()
            )
        )

        realtimeChannel = channel
        realtimeTask = Task { [weak self] in
            for await _ in changes {
                guard !Task.isCancelled else { return }
                await self?.receiveRealtimeChange()
            }
        }

        do {
            try await channel.subscribeWithError()
            isRealtimeActive = true
            realtimeStatus = "Realtime 已連線，等待對方寫入標記"
        } catch {
            realtimeTask?.cancel()
            realtimeTask = nil
            realtimeChannel = nil
            await client.removeChannel(channel)
            isRealtimeActive = false
            realtimeStatus = "Realtime 連線失敗：\(error.localizedDescription)"
        }
    }

    func stopRealtime() async {
        realtimeTask?.cancel()
        realtimeTask = nil

        if let realtimeChannel {
            await client.removeChannel(realtimeChannel)
            self.realtimeChannel = nil
        }

        isRealtimeActive = false
        realtimeStatus = "尚未啟動 Realtime"
    }

    func uploadStoragePhoto(_ jpegData: Data) async {
        guard let relationshipID else {
            storageStatus = "請先建立或加入測試關係"
            return
        }

        storageStatus = "正在上傳私有照片…"
        let clientID = UUID()
        let path = storagePath(relationshipID: relationshipID, clientID: clientID)
        let bucket = client.storage.from("couplespace-w1-photos")

        do {
            let session = try await client.auth.session
            try await bucket.upload(
                path,
                data: jpegData,
                options: FileOptions(contentType: "image/jpeg", upsert: false)
            )

            do {
                try await client
                    .from("shared_items")
                    .insert(SharedItemInsert(
                        relationshipID: relationshipID,
                        clientID: clientID,
                        creatorUserID: session.user.id,
                        itemKind: "photo"
                    ))
                    .execute()
            } catch {
                _ = try? await bucket.remove(paths: [path])
                throw error
            }

            storagePhotoData = jpegData
            storageStatus = "私有照片已上傳；請在另一個裝置重新整理"
        } catch {
            storageStatus = "Storage 照片上傳失敗：\(error.localizedDescription)"
        }
    }

    func refreshStoragePhoto() async {
        guard let relationshipID else {
            storageStatus = "請先建立或加入測試關係"
            return
        }

        storageStatus = "正在讀取私有照片…"

        do {
            let photos: [SharedPhotoRow] = try await client
                .from("shared_items")
                .select("client_id")
                .eq("relationship_id", value: relationshipID)
                .eq("item_kind", value: "photo")
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            guard let photo = photos.first else {
                storagePhotoData = nil
                storageStatus = "此關係尚無 Supabase Storage 照片"
                return
            }

            storagePhotoData = try await client.storage
                .from("couplespace-w1-photos")
                .download(path: storagePath(
                    relationshipID: relationshipID,
                    clientID: photo.clientID
                ))
            storageStatus = "已讀取另一個裝置可見的私有照片"
        } catch {
            storageStatus = "Storage 照片讀取失敗：\(error.localizedDescription)"
        }
    }

    func reportStoragePhotoSelectionFailure(_ error: Error?) {
        if let error {
            storageStatus = "照片選取失敗：\(error.localizedDescription)"
        } else {
            storageStatus = "照片選取失敗：無法讀取圖片資料"
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
                await stopRealtime()
                let archives: [PersonalArchiveRow] = try await client
                    .from("personal_archives")
                    .select("id,relationship_id")
                    .order("sealed_at", ascending: false)
                    .limit(1)
                    .execute()
                    .value

                if let archive = archives.first {
                    relationshipID = nil
                    relationshipStatus = "archived"
                    relationshipToken = shortToken(archive.relationshipID)
                    memberCount = 0
                    latestMarkerToken = "共同資料已封存"
                    storagePhotoData = nil
                    storageStatus = "關係封存後不再讀取共同 Storage"
                    try await refreshPersonalArchive(archive)
                    status = "關係已封存；目前只能讀取自己的個人封存"
                } else {
                    reset(message: "尚未建立 Supabase 測試關係")
                }
                return
            }

            relationshipID = relationship.id
            relationshipStatus = relationship.status
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
            let archives: [PersonalArchiveRow] = try await client
                .from("personal_archives")
                .select("id,relationship_id")
                .eq("relationship_id", value: relationship.id)
                .limit(1)
                .execute()
                .value
            if let archive = archives.first {
                try await refreshPersonalArchive(archive)
                lifecycleStatus = "個人封存已建立；等待另一方完成"
            } else {
                hasPersonalArchive = false
                personalArchiveItemCount = 0
                lifecycleStatus = relationship.status == "closing"
                    ? "關係 closing；請建立自己的個人封存"
                    : "關係 active；尚未開始解除配對"
            }
            status = "關係：\(relationship.status)，成員：\(memberCount)/2"
        } catch {
            reportFailure("重新整理 RLS 狀態", error: error)
        }
    }

    func clearSession() async {
        await stopRealtime()
        reset()
    }

    private func reset(message: String = "登入後可開始雙身分 RLS 驗證") {
        relationshipID = nil
        relationshipStatus = nil
        relationshipToken = "尚無關係"
        memberCount = 0
        latestMarkerToken = "尚無標記"
        invitationToken = nil
        storagePhotoData = nil
        storageStatus = "尚無 Supabase Storage 照片"
        lifecycleStatus = "尚未開始資料生命週期驗證"
        personalArchiveItemCount = 0
        hasPersonalArchive = false
        status = message
    }

    private func refreshPersonalArchive(_ archive: PersonalArchiveRow) async throws {
        let items: [PersonalArchiveItemRow] = try await client
            .from("personal_archive_items")
            .select("client_id,item_kind")
            .eq("archive_id", value: archive.id)
            .order("created_at", ascending: false)
            .execute()
            .value
        hasPersonalArchive = true
        personalArchiveItemCount = items.count

        guard let photo = items.first(where: { $0.itemKind == "photo" }) else {
            storagePhotoData = nil
            storageStatus = "個人封存尚無照片"
            return
        }

        do {
            storagePhotoData = try await client.storage
                .from("couplespace-w1-photos")
                .download(path: storagePath(
                    relationshipID: archive.relationshipID,
                    clientID: photo.clientID
                ))
            storageStatus = "已從個人封存讀取私有照片"
        } catch {
            storagePhotoData = nil
            storageStatus = "個人封存照片讀取失敗：\(error.localizedDescription)"
        }
    }

    private func receiveRealtimeChange() async {
        realtimeStatus = "收到 Realtime 變更，已重新讀取 RLS 資料"
        await refresh()
    }

    private func shortToken(_ id: UUID) -> String {
        String(id.uuidString.lowercased().prefix(8))
    }

    private func storagePath(relationshipID: UUID, clientID: UUID) -> String {
        "\(relationshipID.uuidString.lowercased())/\(clientID.uuidString.lowercased()).jpg"
    }

    private func reportFailure(_ action: String, error: Error) {
        status = "\(action)失敗：\(error.localizedDescription)"
    }
}
