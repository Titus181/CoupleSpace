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

private struct SharedMarkerWriteParameters: Encodable {
    let targetRelationshipID: UUID
    let targetClientID: UUID

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetClientID = "target_client_id"
    }
}

private struct SharedMessageWriteParameters: Encodable {
    let targetRelationshipID: UUID
    let targetClientID: UUID
    let targetBody: String

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetClientID = "target_client_id"
        case targetBody = "target_body"
    }
}

private struct PhotoFinalizeParameters: Encodable {
    let targetRelationshipID: UUID
    let targetClientID: UUID
    let targetByteSize: Int

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetClientID = "target_client_id"
        case targetByteSize = "target_byte_size"
    }
}

private struct PhotoFinalizeResponse: Decodable {
    let accepted: Bool
    let reason: String?
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

private struct SharedMessageRow: Decodable {
    let clientID: UUID
    let textContent: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case textContent = "text_content"
    }
}

private struct SharedPhotoRow: Decodable {
    let clientID: UUID
    let creatorUserID: UUID?
    let itemKind: String?

    enum CodingKeys: String, CodingKey {
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

private struct ArchivedPhotoIdentityRow: Decodable {
    let itemKind: String

    enum CodingKeys: String, CodingKey {
        case itemKind = "item_kind"
    }
}

@MainActor
final class SupabasePairingPoC: ObservableObject {
    @Published private(set) var status = "登入後可開始雙身分 RLS 驗證"
    @Published private(set) var relationshipToken = "尚無關係"
    @Published private(set) var relationshipSnapshotStatus = "尚無本機關係快照"
    @Published private(set) var memberCount = 0
    @Published private(set) var latestMarkerToken = "尚無標記"
    @Published private(set) var recentMarkerTokens = "尚無標記"
    @Published private(set) var invitationToken: String?
    @Published private(set) var realtimeStatus = "尚未啟動 Realtime"
    @Published private(set) var isRealtimeActive = false
    @Published private(set) var storageStatus = "尚無 Supabase Storage 照片"
    @Published private(set) var storagePhotoData: Data?
    @Published private(set) var recentPhotoTokens = "尚無照片"
    @Published private(set) var relationshipStatus: String?
    @Published private(set) var lifecycleStatus = "尚未開始資料生命週期驗證"
    @Published private(set) var personalArchiveItemCount = 0
    @Published private(set) var hasPersonalArchive = false
    @Published private(set) var archiveExportStatus = "尚未準備個人封存匯出"
    @Published private(set) var archiveExportDocument: PersonalArchiveExportDocument?
    @Published private(set) var archiveExportFileName = "CoupleSpace-personal-archive"
    @Published private(set) var markerOutboxStatus = "尚無待送標記"
    @Published private(set) var hasPendingMarker = false
    @Published private(set) var isMarkerOutboxSending = false
    @Published private(set) var photoOutboxStatus = "尚無待送照片"
    @Published private(set) var hasPendingPhoto = false
    @Published private(set) var isPhotoOutboxSending = false
    @Published private(set) var messageOutboxStatus = "尚無待送訊息"
    @Published private(set) var hasPendingMessage = false
    @Published private(set) var isMessageOutboxSending = false
    @Published private(set) var recentTestMessages = "尚無測試訊息"

    private let client: SupabaseClient
    private let markerOutboxStore: MarkerOutboxStore
    private let photoOutboxStore: PhotoOutboxStore
    private let messageOutboxStore: MessageOutboxStore
    private let relationshipSnapshotStore: RelationshipSnapshotStore
    private var relationshipID: UUID?
    private var personalArchiveID: UUID?
    private var personalArchiveRelationshipID: UUID?
    private var archiveExportStagingURL: URL?
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTask: Task<Void, Never>?
    private var isForegroundRecoveryRunning = false

    var currentRelationshipID: UUID? { relationshipID }

    init(
        client: SupabaseClient,
        markerOutboxStore: MarkerOutboxStore? = nil,
        photoOutboxStore: PhotoOutboxStore? = nil,
        messageOutboxStore: MessageOutboxStore? = nil,
        relationshipSnapshotStore: RelationshipSnapshotStore? = nil
    ) {
        self.client = client
        self.markerOutboxStore = markerOutboxStore ?? MarkerOutboxStore()
        self.photoOutboxStore = photoOutboxStore ?? PhotoOutboxStore()
        self.messageOutboxStore = messageOutboxStore ?? MessageOutboxStore()
        self.relationshipSnapshotStore = relationshipSnapshotStore ?? RelationshipSnapshotStore()
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
        guard !isMarkerOutboxSending else {
            markerOutboxStatus = "正在依序傳送，請稍候"
            return
        }
        isMarkerOutboxSending = true
        defer { isMarkerOutboxSending = false }

        do {
            let session = try await client.auth.session
            var queue = try markerOutboxStore.load(userID: session.user.id)
            guard queue.entries.allSatisfy({ $0.relationshipID == relationshipID }) else {
                markerOutboxStatus = "另一段關係仍有待送標記，未建立新項目"
                return
            }

            queue.enqueue(MarkerOutboxEntry(
                relationshipID: relationshipID,
                clientID: UUID(),
                attemptCount: 0
            ))
            try markerOutboxStore.save(queue, userID: session.user.id)
            hasPendingMarker = true
            markerOutboxStatus = "有 \(queue.count) 個待送標記"
            await sendPendingMarkers(userID: session.user.id)
        } catch {
            markerOutboxStatus = "無法建立待送標記：\(error.localizedDescription)"
        }
    }

    func retryPendingMarker() async {
        guard !isMarkerOutboxSending else {
            markerOutboxStatus = "正在依序傳送，請稍候"
            return
        }
        isMarkerOutboxSending = true
        defer { isMarkerOutboxSending = false }

        do {
            let session = try await client.auth.session
            let queue = try markerOutboxStore.load(userID: session.user.id)
            guard !queue.isEmpty else {
                hasPendingMarker = false
                markerOutboxStatus = "尚無待送標記"
                return
            }
            guard queue.entries.allSatisfy({ $0.relationshipID == relationshipID }) else {
                markerOutboxStatus = "待送標記不屬於目前關係"
                return
            }

            await sendPendingMarkers(userID: session.user.id)
        } catch {
            markerOutboxStatus = "無法讀取待送標記：\(error.localizedDescription)"
        }
    }

    func discardPendingMarkersFromOtherRelationship() async {
        guard let relationshipID else {
            markerOutboxStatus = "目前沒有可比對的關係，未清除待送標記"
            return
        }

        do {
            let session = try await client.auth.session
            let didDiscard = try markerOutboxStore.discardIfOnlyFromOtherRelationships(
                userID: session.user.id,
                currentRelationshipID: relationshipID
            )
            guard didDiscard else {
                markerOutboxStatus = "目前關係的待送標記不可清除，請改用重試"
                return
            }
            hasPendingMarker = false
            markerOutboxStatus = "已清除其他關係的待送測試標記"
        } catch {
            markerOutboxStatus = "清除其他關係待送標記失敗：\(error.localizedDescription)"
        }
    }

    func writeTestMessage() async {
        guard let relationshipID else {
            status = "請先建立或加入測試關係"
            return
        }
        guard !isMessageOutboxSending else {
            messageOutboxStatus = "正在依序傳送訊息，請稍候"
            return
        }
        isMessageOutboxSending = true
        defer { isMessageOutboxSending = false }

        do {
            let session = try await client.auth.session
            var queue = try messageOutboxStore.load(userID: session.user.id)
            guard queue.entries.allSatisfy({ $0.relationshipID == relationshipID }) else {
                messageOutboxStatus = "另一段關係仍有待送訊息，未建立新項目"
                return
            }
            let clientID = UUID()
            let body = "W1 test \(shortToken(clientID))"
            queue.enqueue(MessageOutboxEntry(
                relationshipID: relationshipID,
                clientID: clientID,
                body: body,
                attemptCount: 0
            ))
            try messageOutboxStore.save(queue, userID: session.user.id)
            hasPendingMessage = true
            messageOutboxStatus = "有 \(queue.count) 則待送訊息"
            await sendPendingMessages(userID: session.user.id)
        } catch {
            messageOutboxStatus = "無法建立待送訊息：\(error.localizedDescription)"
        }
    }

    func retryPendingMessages() async {
        guard !isMessageOutboxSending else {
            messageOutboxStatus = "正在依序傳送訊息，請稍候"
            return
        }
        isMessageOutboxSending = true
        defer { isMessageOutboxSending = false }

        do {
            let session = try await client.auth.session
            let queue = try messageOutboxStore.load(userID: session.user.id)
            guard !queue.isEmpty else {
                hasPendingMessage = false
                messageOutboxStatus = "尚無待送訊息"
                return
            }
            guard queue.entries.allSatisfy({ $0.relationshipID == relationshipID }) else {
                messageOutboxStatus = "待送訊息不屬於目前關係"
                return
            }
            await sendPendingMessages(userID: session.user.id)
        } catch {
            messageOutboxStatus = "無法讀取待送訊息：\(error.localizedDescription)"
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

    func deletePersonalArchive() async {
        guard let personalArchiveID else {
            lifecycleStatus = "目前沒有可刪除的個人封存"
            return
        }

        do {
            let queuedObjectCount: Int = try await client
                .rpc(
                    "delete_personal_archive",
                    params: ["target_archive_id": personalArchiveID]
                )
                .execute()
                .value

            self.personalArchiveID = nil
            personalArchiveRelationshipID = nil
            hasPersonalArchive = false
            personalArchiveItemCount = 0
            storagePhotoData = nil
            cleanupArchiveExportStaging()
            archiveExportDocument = nil
            archiveExportStatus = "個人封存已刪除"

            if queuedObjectCount > 0 {
                do {
                    try await client.functions.invoke("process-storage-gc")
                    lifecycleStatus = "個人封存已刪除；最後一份照片已完成清理"
                } catch {
                    lifecycleStatus = "個人封存已刪除；照片已排入清理佇列，稍後可重試"
                }
            } else {
                lifecycleStatus = "個人封存已刪除；另一方封存與照片不受影響"
            }
        } catch {
            lifecycleStatus = "刪除個人封存失敗：\(error.localizedDescription)"
        }
    }

    func preparePersonalArchiveExport() async {
        guard relationshipStatus == "archived",
              let personalArchiveID,
              let relationshipID = personalArchiveRelationshipID else {
            archiveExportStatus = "只有已完成解除配對的個人封存可以匯出"
            return
        }

        archiveExportStatus = "正在準備個人封存匯出…"
        cleanupArchiveExportStaging()
        archiveExportDocument = nil

        do {
            try PersonalArchiveExportStaging.cleanupAbandoned()
            _ = try await client.auth.session
            let rows: [PersonalArchiveItemRow] = try await client
                .from("personal_archive_items")
                .select("client_id,item_kind,created_at,text_content,media_byte_size")
                .eq("archive_id", value: personalArchiveID)
                .order("created_at", ascending: true)
                .order("client_id", ascending: true)
                .execute()
                .value

            var items: [PersonalArchiveExportItem] = []
            for row in rows {
                let photoFile = row.itemKind == "photo"
                    ? PersonalArchiveExportPackage.photoFileName(clientID: row.clientID)
                    : nil
                items.append(PersonalArchiveExportItem(
                    clientID: row.clientID,
                    kind: row.itemKind,
                    createdAt: row.createdAt,
                    text: row.textContent,
                    photoFile: photoFile
                ))

            }

            let package = try PersonalArchiveExportPackage(
                relationshipID: relationshipID,
                exportedAt: .now,
                items: items
            )
            let requiredBytes = PersonalArchiveExportCapacityPolicy.requiredBytes(
                manifestByteCount: try package.manifestData().count,
                photoByteSizes: rows
                    .filter { $0.itemKind == "photo" }
                    .map(\.mediaByteSize)
            )
            let stagingDirectory = FileManager.default.temporaryDirectory
            let availableBytes = PersonalArchiveExportCapacityPolicy.availableBytes(
                at: stagingDirectory
            )
            guard PersonalArchiveExportCapacityPolicy.permitsStaging(
                requiredBytes: requiredBytes,
                availableBytes: availableBytes
            ) else {
                throw PersonalArchiveExportError.insufficientStagingCapacity
            }
            var staging = try PersonalArchiveExportStaging(package: package)
            do {
                for row in rows where row.itemKind == "photo" {
                    let data = try await client.storage
                        .from("couplespace-w1-photos")
                        .download(path: storagePath(
                            relationshipID: relationshipID,
                            clientID: row.clientID
                        ))
                    try staging.writePhoto(clientID: row.clientID, jpegData: data)
                }

                let exportFileName = "CoupleSpace-personal-archive-\(shortToken(relationshipID))"
                archiveExportDocument = try PersonalArchiveExportDocument(
                    staging: staging,
                    exportFileName: exportFileName
                )
                archiveExportStagingURL = staging.directoryURL
                archiveExportFileName = exportFileName
                archiveExportStatus = "匯出已準備：manifest.json 與 \(package.expectedPhotoIDs.count) 張照片"
            } catch {
                try? staging.remove()
                throw error
            }
        } catch {
            archiveExportStatus = "個人封存匯出準備失敗：\(error.localizedDescription)"
        }
    }

    func finishPersonalArchiveExport(_ result: Result<URL, Error>) {
        archiveExportDocument = nil
        cleanupArchiveExportStaging()
        switch result {
        case .success:
            archiveExportStatus = "個人封存已交付至所選位置"
        case let .failure(error):
            archiveExportStatus = "個人封存交付失敗：\(error.localizedDescription)"
        }
    }

    func retryStorageGC() async {
        do {
            try await client.functions.invoke("process-storage-gc")
            lifecycleStatus = "照片清理佇列已處理"
        } catch {
            lifecycleStatus = "照片清理重試失敗：\(error.localizedDescription)"
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
            realtimeStatus = "Realtime 已連線，等待對方寫入共同資料"
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
        guard !isPhotoOutboxSending else {
            photoOutboxStatus = "正在傳送照片，請稍候"
            return
        }
        isPhotoOutboxSending = true
        defer { isPhotoOutboxSending = false }

        do {
            let session = try await client.auth.session
            _ = try photoOutboxStore.create(
                jpegData: jpegData,
                relationshipID: relationshipID,
                clientID: UUID(),
                userID: session.user.id
            )
            hasPendingPhoto = true
            photoOutboxStatus = "照片已保存，等待上傳"
            await sendPendingPhotos(userID: session.user.id)
        } catch {
            photoOutboxStatus = "無法保存待送照片：\(error.localizedDescription)"
        }
    }

    func retryPendingPhoto() async {
        guard !isPhotoOutboxSending else {
            photoOutboxStatus = "正在傳送照片，請稍候"
            return
        }
        isPhotoOutboxSending = true
        defer { isPhotoOutboxSending = false }

        do {
            let session = try await client.auth.session
            let queue = try photoOutboxStore.load(userID: session.user.id)
            guard let entry = queue.first else {
                hasPendingPhoto = false
                photoOutboxStatus = "尚無待送照片"
                return
            }
            guard entry.relationshipID == relationshipID else {
                photoOutboxStatus = "待送照片不屬於目前關係"
                return
            }
            await sendPendingPhotos(userID: session.user.id)
        } catch {
            photoOutboxStatus = "無法讀取待送照片：\(error.localizedDescription)"
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
                .order("client_id", ascending: false)
                .limit(3)
                .execute()
                .value

            guard let photo = photos.first else {
                storagePhotoData = nil
                recentPhotoTokens = "尚無照片"
                storageStatus = "此關係尚無 Supabase Storage 照片"
                return
            }

            recentPhotoTokens = photos.reversed()
                .map { shortToken($0.clientID) }
                .joined(separator: " → ")

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
            let session = try await client.auth.session
            try restoreRelationshipSnapshot(userID: session.user.id)
            try refreshMarkerOutbox(userID: session.user.id)
            try refreshPhotoOutbox(userID: session.user.id)
            try refreshMessageOutbox(userID: session.user.id)
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
                    relationshipSnapshotStore.clear(userID: session.user.id)
                    relationshipID = nil
                    relationshipStatus = "archived"
                    relationshipToken = shortToken(archive.relationshipID)
                    relationshipSnapshotStatus = "Supabase 已確認關係已封存"
                    memberCount = 0
                    latestMarkerToken = "共同資料已封存"
                    recentMarkerTokens = "共同資料已封存"
                    storagePhotoData = nil
                    storageStatus = "關係封存後不再讀取共同 Storage"
                    await reconcilePhotoOutboxAfterRelationshipClosed(
                        userID: session.user.id,
                        relationshipID: archive.relationshipID,
                        archiveID: archive.id
                    )
                    try await refreshPersonalArchive(archive)
                    status = "關係已封存；目前只能讀取自己的個人封存"
                } else {
                    relationshipSnapshotStore.clear(userID: session.user.id)
                    reset(message: "尚未建立 Supabase 測試關係")
                    relationshipSnapshotStatus = "Supabase 已確認目前無關係"
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
            try relationshipSnapshotStore.save(
                RelationshipSnapshot(
                    relationshipID: relationship.id,
                    status: relationship.status,
                    memberCount: memberCount
                ),
                userID: session.user.id
            )
            relationshipSnapshotStatus = "Supabase 已更新"

            let markers: [SharedMarkerRow] = try await client
                .from("shared_items")
                .select("client_id")
                .eq("relationship_id", value: relationship.id)
                .eq("item_kind", value: "marker")
                .order("created_at", ascending: false)
                .limit(3)
                .execute()
                .value
            latestMarkerToken = markers.first.map { shortToken($0.clientID) } ?? "尚無標記"
            recentMarkerTokens = markers.reversed()
                .map { shortToken($0.clientID) }
                .joined(separator: " → ")
            if recentMarkerTokens.isEmpty {
                recentMarkerTokens = "尚無標記"
            }
            let messages: [SharedMessageRow] = try await client
                .from("shared_items")
                .select("client_id,text_content")
                .eq("relationship_id", value: relationship.id)
                .eq("item_kind", value: "message")
                .order("created_at", ascending: false)
                .order("client_id", ascending: false)
                .limit(3)
                .execute()
                .value
            recentTestMessages = messages.reversed()
                .map(\.textContent)
                .joined(separator: " → ")
            if recentTestMessages.isEmpty {
                recentTestMessages = "尚無測試訊息"
            }
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
                personalArchiveID = nil
                personalArchiveRelationshipID = nil
                hasPersonalArchive = false
                personalArchiveItemCount = 0
                lifecycleStatus = relationship.status == "closing"
                    ? "關係 closing；請建立自己的個人封存"
                    : "關係 active；尚未開始解除配對"
            }
            if relationship.status == "closing" {
                await reconcilePhotoOutboxAfterRelationshipClosed(
                    userID: session.user.id,
                    relationshipID: relationship.id,
                    archiveID: nil
                )
            }
            status = "關係：\(relationship.status)，成員：\(memberCount)/2"
        } catch {
            reportFailure("重新整理 RLS 狀態", error: error)
        }
    }

    func recoverPendingOutboxesOnForeground() async {
        guard !isForegroundRecoveryRunning else { return }
        isForegroundRecoveryRunning = true
        defer { isForegroundRecoveryRunning = false }

        do {
            let session = try await client.auth.session
            for attempt in 1...ForegroundRecoveryRetryPolicy.maximumAttempts {
                await refresh()

                let plan = try foregroundRecoveryPlan(userID: session.user.id)
                guard !plan.isEmpty else { return }

                for kind in plan {
                    guard relationshipStatus == "active" else { return }
                    switch kind {
                    case .marker:
                        await retryPendingMarker()
                    case .message:
                        await retryPendingMessages()
                    case .photo:
                        await retryPendingPhoto()
                    }
                }

                guard !(try foregroundRecoveryPlan(userID: session.user.id)).isEmpty else {
                    return
                }
                guard let delay = ForegroundRecoveryRetryPolicy.delayNanoseconds(
                    afterAttempt: attempt
                ) else {
                    status = "前景自動重試已暫停；待送項目已保留"
                    return
                }
                status = "前景恢復仍有待送項目；稍後進行第 \(attempt + 1) 次嘗試"
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
            }
        } catch {
            status = "前景恢復未完成：\(error.localizedDescription)"
        }
    }

    private func foregroundRecoveryPlan(userID: UUID) throws -> [PendingOutboxKind] {
        ForegroundOutboxRecoveryPolicy.plan(
            relationshipStatus: relationshipStatus,
            currentRelationshipID: relationshipID,
            markerRelationshipIDs: try markerOutboxStore.load(userID: userID)
                .entries.map(\.relationshipID),
            messageRelationshipIDs: try messageOutboxStore.load(userID: userID)
                .entries.map(\.relationshipID),
            photoRelationshipIDs: try photoOutboxStore.load(userID: userID)
                .entries.map(\.relationshipID)
        )
    }

    func clearSession() async {
        await stopRealtime()
        reset()
    }

    private func reset(message: String = "登入後可開始雙身分 RLS 驗證") {
        relationshipID = nil
        relationshipStatus = nil
        relationshipToken = "尚無關係"
        relationshipSnapshotStatus = "尚無本機關係快照"
        memberCount = 0
        latestMarkerToken = "尚無標記"
        recentMarkerTokens = "尚無標記"
        invitationToken = nil
        storagePhotoData = nil
        storageStatus = "尚無 Supabase Storage 照片"
        recentPhotoTokens = "尚無照片"
        lifecycleStatus = "尚未開始資料生命週期驗證"
        personalArchiveItemCount = 0
        hasPersonalArchive = false
        archiveExportStatus = "尚未準備個人封存匯出"
        cleanupArchiveExportStaging()
        archiveExportDocument = nil
        archiveExportFileName = "CoupleSpace-personal-archive"
        hasPendingMarker = false
        markerOutboxStatus = "尚無待送標記"
        hasPendingPhoto = false
        photoOutboxStatus = "尚無待送照片"
        hasPendingMessage = false
        messageOutboxStatus = "尚無待送訊息"
        recentTestMessages = "尚無測試訊息"
        personalArchiveID = nil
        personalArchiveRelationshipID = nil
        status = message
    }

    private func cleanupArchiveExportStaging() {
        guard let archiveExportStagingURL else { return }
        try? FileManager.default.removeItem(at: archiveExportStagingURL)
        self.archiveExportStagingURL = nil
    }

    private func restoreRelationshipSnapshot(userID: UUID) throws {
        guard let snapshot = try relationshipSnapshotStore.load(userID: userID) else {
            relationshipSnapshotStatus = "尚無本機關係快照"
            return
        }
        relationshipID = snapshot.relationshipID
        relationshipStatus = snapshot.status
        relationshipToken = shortToken(snapshot.relationshipID)
        memberCount = snapshot.memberCount
        relationshipSnapshotStatus = "顯示上次已同步資料"
    }

    private func sendPendingMarkers(userID: UUID) async {
        do {
            var queue = try markerOutboxStore.load(userID: userID)
            let originalCount = queue.count
            var deliveredCount = 0
            var lastDeliveredID: UUID?

            while let sendingEntry = queue.beginFirstAttempt() {
                try markerOutboxStore.save(queue, userID: userID)
                hasPendingMarker = true
                markerOutboxStatus = "正在依序傳送第 \(deliveredCount + 1)/\(originalCount) 個標記（第 \(sendingEntry.attemptCount) 次）"

                try await client
                    .rpc(
                        "write_shared_marker",
                        params: SharedMarkerWriteParameters(
                            targetRelationshipID: sendingEntry.relationshipID,
                            targetClientID: sendingEntry.clientID
                        )
                    )
                    .execute()

                guard queue.acknowledgeFirst(clientID: sendingEntry.clientID) else {
                    markerOutboxStatus = "Outbox 順序不一致，已停止重送"
                    return
                }
                try markerOutboxStore.save(queue, userID: userID)
                deliveredCount += 1
                lastDeliveredID = sendingEntry.clientID
            }

            hasPendingMarker = false
            await refresh()
            if let lastDeliveredID {
                markerOutboxStatus = "已依序送達 \(deliveredCount) 個標記；最後：\(shortToken(lastDeliveredID))"
                status = "已依序寫入 RLS 驗證標記"
            }
        } catch {
            hasPendingMarker = true
            if let queue = try? markerOutboxStore.load(userID: userID),
               let first = queue.first {
                markerOutboxStatus = "尚有 \(queue.count) 個待送標記；第一個已嘗試 \(first.attemptCount) 次"
            } else {
                markerOutboxStatus = "Outbox 讀取失敗，已停止重送"
            }
            status = "標記傳送失敗：\(error.localizedDescription)"
        }
    }

    private func refreshMarkerOutbox(userID: UUID) throws {
        let queue = try markerOutboxStore.load(userID: userID)
        guard let first = queue.first else {
            hasPendingMarker = false
            markerOutboxStatus = "尚無待送標記"
            return
        }

        hasPendingMarker = true
        markerOutboxStatus = "有 \(queue.count) 個待送標記（第一個已嘗試 \(first.attemptCount) 次）"
    }

    private func sendPendingMessages(userID: UUID) async {
        do {
            var queue = try messageOutboxStore.load(userID: userID)
            let originalCount = queue.count
            var deliveredCount = 0

            while let sendingEntry = queue.beginFirstAttempt() {
                try messageOutboxStore.save(queue, userID: userID)
                hasPendingMessage = true
                messageOutboxStatus = "正在傳送第 \(deliveredCount + 1)/\(originalCount) 則訊息（第 \(sendingEntry.attemptCount) 次）"

                try await client
                    .rpc(
                        "write_shared_message",
                        params: SharedMessageWriteParameters(
                            targetRelationshipID: sendingEntry.relationshipID,
                            targetClientID: sendingEntry.clientID,
                            targetBody: sendingEntry.body
                        )
                    )
                    .execute()

                guard queue.acknowledgeFirst(clientID: sendingEntry.clientID) else {
                    messageOutboxStatus = "訊息 Outbox 順序不一致，已停止重送"
                    return
                }
                try messageOutboxStore.save(queue, userID: userID)
                deliveredCount += 1
            }

            hasPendingMessage = false
            await refresh()
            messageOutboxStatus = "已依序送達 \(deliveredCount) 則測試訊息"
        } catch {
            hasPendingMessage = true
            if let queue = try? messageOutboxStore.load(userID: userID),
               let first = queue.first {
                messageOutboxStatus = "尚有 \(queue.count) 則待送訊息；第一則已嘗試 \(first.attemptCount) 次"
            } else {
                messageOutboxStatus = "訊息 Outbox 讀取失敗，已停止重送"
            }
        }
    }

    private func refreshMessageOutbox(userID: UUID) throws {
        let queue = try messageOutboxStore.load(userID: userID)
        guard let first = queue.first else {
            hasPendingMessage = false
            messageOutboxStatus = "尚無待送訊息"
            return
        }
        hasPendingMessage = true
        messageOutboxStatus = "有 \(queue.count) 則待送訊息（第一則已嘗試 \(first.attemptCount) 次）"
    }

    private func sendPendingPhotos(userID: UUID) async {
        do {
            let originalCount = try photoOutboxStore.load(userID: userID).count
            var deliveredCount = 0

            while let entry = try photoOutboxStore.beginAttempt(userID: userID) {
                guard entry.relationshipID == relationshipID else {
                    photoOutboxStatus = "待送照片不屬於目前關係"
                    return
                }

                let jpegData = try photoOutboxStore.data(for: entry)
                let path = storagePath(
                    relationshipID: entry.relationshipID,
                    clientID: entry.clientID
                )
                let bucket = client.storage.from("couplespace-w1-photos")
                hasPendingPhoto = true
                photoOutboxStatus = "正在傳送第 \(deliveredCount + 1)/\(originalCount) 張照片（第 \(entry.attemptCount) 次）"
                storageStatus = "正在上傳私有照片…"

                var objectAlreadyExists = false
                if entry.attemptCount > 1,
                   (try? await bucket.download(path: path)) != nil {
                    objectAlreadyExists = true
                }
                if !objectAlreadyExists {
                    try await bucket.upload(
                        path,
                        data: jpegData,
                        options: FileOptions(contentType: "image/jpeg", upsert: false)
                    )
                }

                let finalizeResults: [PhotoFinalizeResponse] = try await client
                    .rpc(
                        "finalize_w1_photo_upload",
                        params: PhotoFinalizeParameters(
                            targetRelationshipID: entry.relationshipID,
                            targetClientID: entry.clientID,
                            targetByteSize: jpegData.count
                        )
                    )
                    .execute()
                    .value
                guard let finalizeResult = finalizeResults.first else {
                    throw SupabasePhotoOutboxError.missingFinalizeResponse
                }

                switch try PhotoFinalizationPolicy.action(
                    accepted: finalizeResult.accepted,
                    reason: finalizeResult.reason
                ) {
                case .acknowledgeDelivered:
                    break
                case let .deleteQuotaRejectedObject(quotaMessage):
                    guard try await PhotoQuotaCleanupCoordinator.deleteThenAcknowledge(
                        deleteRemoteObject: {
                            _ = try await bucket.remove(paths: [path])
                        },
                        acknowledgeLocalEntry: {
                            try photoOutboxStore.acknowledgeFirst(
                                clientID: entry.clientID,
                                userID: userID
                            )
                        }
                    ) else {
                        throw SupabasePhotoOutboxError.remoteIdentityMismatch
                    }
                    let remainingCount = try photoOutboxStore.load(userID: userID).count
                    hasPendingPhoto = remainingCount > 0
                    photoOutboxStatus = PhotoFinalizationPolicy.rejectedOutboxStatus(
                        message: quotaMessage,
                        remainingCount: remainingCount
                    )
                    storageStatus = quotaMessage
                    return
                }

                guard try photoOutboxStore.acknowledgeFirst(
                    clientID: entry.clientID,
                    userID: userID
                ) else {
                    photoOutboxStatus = "照片 Outbox 順序不一致，已停止重送"
                    return
                }
                deliveredCount += 1
            }

            hasPendingPhoto = false
            await refreshStoragePhoto()
            photoOutboxStatus = "已依序送達 \(deliveredCount) 張照片"
        } catch {
            hasPendingPhoto = true
            if let queue = try? photoOutboxStore.load(userID: userID),
               let first = queue.first {
                photoOutboxStatus = "尚有 \(queue.count) 張待送照片；第一張已嘗試 \(first.attemptCount) 次"
            } else {
                photoOutboxStatus = "照片 Outbox 讀取失敗"
            }
            storageStatus = "Storage 照片上傳失敗：\(error.localizedDescription)"
        }
    }

    private func refreshPhotoOutbox(userID: UUID) throws {
        let queue = try photoOutboxStore.load(userID: userID)
        guard let first = queue.first else {
            hasPendingPhoto = false
            photoOutboxStatus = "尚無待送照片"
            return
        }
        hasPendingPhoto = true
        photoOutboxStatus = "有 \(queue.count) 張待送照片（第一張已嘗試 \(first.attemptCount) 次）"
    }

    private func reconcilePhotoOutboxAfterRelationshipClosed(
        userID: UUID,
        relationshipID: UUID,
        archiveID: UUID?
    ) async {
        guard !isPhotoOutboxSending else { return }
        isPhotoOutboxSending = true
        defer { isPhotoOutboxSending = false }

        do {
            var deliveredCount = 0
            var deletedOrphanCount = 0
            while let entry = try photoOutboxStore.load(userID: userID).first,
                  entry.relationshipID == relationshipID {
                let action: PhotoOutboxLifecyclePolicy.ClosedRelationshipAction
                if let archiveID {
                    let archivedItems: [ArchivedPhotoIdentityRow] = try await client
                        .from("personal_archive_items")
                        .select("item_kind")
                        .eq("archive_id", value: archiveID)
                        .eq("client_id", value: entry.clientID)
                        .limit(1)
                        .execute()
                        .value
                    action = try PhotoOutboxLifecyclePolicy.actionForArchivedRelationship(
                        archivedItemKind: archivedItems.first?.itemKind
                    )
                } else {
                    let sharedItems: [SharedPhotoRow] = try await client
                        .from("shared_items")
                        .select("client_id,creator_user_id,item_kind")
                        .eq("relationship_id", value: relationshipID)
                        .eq("client_id", value: entry.clientID)
                        .limit(1)
                        .execute()
                        .value
                    action = try PhotoOutboxLifecyclePolicy.actionForClosingRelationship(
                        remoteCreatorID: sharedItems.first?.creatorUserID,
                        remoteItemKind: sharedItems.first?.itemKind,
                        currentUserID: userID
                    )
                }

                switch action {
                case .acknowledgeDelivered:
                    deliveredCount += 1
                case .deleteOrphan:
                    try await client.storage
                        .from("couplespace-w1-photos")
                        .remove(paths: [storagePath(
                            relationshipID: relationshipID,
                            clientID: entry.clientID
                        )])
                    deletedOrphanCount += 1
                }

                guard try photoOutboxStore.acknowledgeFirst(
                    clientID: entry.clientID,
                    userID: userID
                ) else {
                    throw SupabasePhotoOutboxError.remoteIdentityMismatch
                }
            }

            try refreshPhotoOutbox(userID: userID)
            guard deliveredCount > 0 || deletedOrphanCount > 0 else { return }
            photoOutboxStatus = "關係關閉後已整理照片 Outbox：\(deliveredCount) 張已送達，\(deletedOrphanCount) 張 orphan 已移除"
        } catch {
            hasPendingPhoto = true
            photoOutboxStatus = "關係關閉後照片 Outbox 整理失敗，已保留待重試：\(error.localizedDescription)"
        }
    }

    private func refreshPersonalArchive(_ archive: PersonalArchiveRow) async throws {
        let items: [PersonalArchiveItemRow] = try await client
            .from("personal_archive_items")
            .select("client_id,item_kind,created_at,text_content")
            .eq("archive_id", value: archive.id)
            .order("created_at", ascending: false)
            .execute()
            .value
        personalArchiveID = archive.id
        personalArchiveRelationshipID = archive.relationshipID
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

private enum SupabasePhotoOutboxError: LocalizedError {
    case remoteIdentityMismatch
    case missingFinalizeResponse

    var errorDescription: String? {
        switch self {
        case .remoteIdentityMismatch:
            "遠端照片識別與待送項目不一致"
        case .missingFinalizeResponse:
            "伺服器未回傳照片配額確認結果"
        }
    }
}
