import Foundation
import Supabase

enum ConversationDeliveryResult: Equatable, Sendable {
    case accepted(Date)
    case rejected(String)
}

@MainActor
protocol ConversationRemoteServing: AnyObject {
    func fetchPendingSnapshot() async throws -> ConversationPendingSnapshot
    func fetchCachedSnapshot() async throws -> ConversationSnapshot?
    func persistCachedSnapshot(_ snapshot: ConversationSnapshot) async
    func enqueueMessage(
        _ draft: ChatMessageDraft,
        clientID: UUID,
        localCreatedAt: Date
    ) async throws
    func beginNextPendingMessage() async throws -> ChatMessage?
    func acknowledgePendingMessage(clientID: UUID) async throws
    func deliverPendingMessage(_ message: ChatMessage) async throws -> ConversationDeliveryResult
    func fetchSnapshot() async throws -> ConversationSnapshot
    func cachedPhotoData(for messageID: UUID) -> Data?
    func photoData(for messageID: UUID) async throws -> Data
    func setReaction(
        messageID: UUID,
        emoji: MomentEmoji,
        clientID: UUID
    ) async throws -> ChatMessageReaction
    func removeReaction(messageID: UUID) async throws
    func saveAsMoment(messageID: UUID, momentClientID: UUID) async throws -> UUID
    func markRead(through messageID: UUID) async throws
    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws
    func stopObservingChanges() async
}

private struct ChatMessageRow: Decodable {
    let clientID: UUID
    let creatorUserID: UUID
    let itemKind: String
    let textContent: String?
    let mediaByteSize: Int?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case creatorUserID = "creator_user_id"
        case itemKind = "item_kind"
        case textContent = "text_content"
        case mediaByteSize = "media_byte_size"
        case createdAt = "created_at"
    }

    func message(reaction: ChatMessageReaction?) throws -> ChatMessage? {
        let content: ChatMessageContent
        switch itemKind {
        case "message":
            guard let textContent else { throw ConversationServiceError.invalidServerMessage }
            content = .text(textContent)
        case "photo":
            guard let mediaByteSize else { return nil }
            guard mediaByteSize > 0 else {
                throw ConversationServiceError.invalidServerMessage
            }
            content = .photo
        default:
            return nil
        }
        return ChatMessage(
            id: clientID,
            senderUserID: creatorUserID,
            content: content,
            createdAt: createdAt,
            reaction: reaction
        )
    }
}

private struct ChatMessageReactionRow: Decodable {
    let messageClientID: UUID
    let clientID: UUID
    let reactorUserID: UUID
    let emojiValue: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case messageClientID = "message_client_id"
        case clientID = "client_id"
        case reactorUserID = "reactor_user_id"
        case emojiValue = "emoji_value"
        case updatedAt = "updated_at"
    }

    func reaction() throws -> ChatMessageReaction {
        guard let emoji = MomentEmoji(rawValue: emojiValue) else {
            throw ConversationServiceError.invalidServerReaction
        }
        return ChatMessageReaction(
            id: clientID,
            reactorUserID: reactorUserID,
            emoji: emoji,
            updatedAt: updatedAt
        )
    }
}

private struct SendChatMessageParameters: Encodable {
    let targetRelationshipID: UUID
    let targetClientID: UUID
    let targetBody: String

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetClientID = "target_client_id"
        case targetBody = "target_body"
    }
}

private struct FinalizeChatPhotoParameters: Encodable {
    let targetRelationshipID: UUID
    let targetClientID: UUID
    let targetByteSize: Int

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetClientID = "target_client_id"
        case targetByteSize = "target_byte_size"
    }
}

private struct ChatPhotoFinalizeResponse: Decodable {
    let accepted: Bool
    let reason: String?
    let acceptedAt: Date?

    enum CodingKeys: String, CodingKey {
        case accepted, reason
        case acceptedAt = "accepted_at"
    }
}

private struct ConversationRelationshipParameters: Encodable {
    let targetRelationshipID: UUID

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
    }
}

private struct MarkConversationReadParameters: Encodable {
    let targetRelationshipID: UUID
    let targetMessageClientID: UUID

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetMessageClientID = "target_message_client_id"
    }
}

private struct SetSharedItemReactionParameters: Encodable {
    let targetRelationshipID: UUID
    let targetMessageClientID: UUID
    let targetClientID: UUID
    let targetEmojiValue: String

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetMessageClientID = "target_message_client_id"
        case targetClientID = "target_client_id"
        case targetEmojiValue = "target_emoji_value"
    }
}

private struct RemoveSharedItemReactionParameters: Encodable {
    let targetRelationshipID: UUID
    let targetMessageClientID: UUID

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetMessageClientID = "target_message_client_id"
    }
}

private struct SaveSharedItemAsMomentParameters: Encodable {
    let targetRelationshipID: UUID
    let targetMessageClientID: UUID
    let targetMomentClientID: UUID

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetMessageClientID = "target_message_client_id"
        case targetMomentClientID = "target_moment_client_id"
    }
}

private struct SavedMomentRow: Decodable {
    let momentClientID: UUID

    enum CodingKeys: String, CodingKey {
        case momentClientID = "moment_client_id"
    }
}

@MainActor
final class SupabaseConversationService: ConversationRemoteServing {
    private static let photoBucket = "couplespace-w1-photos"

    private let client: SupabaseClient
    private let currentUserID: UUID
    private let relationshipID: UUID
    private let outboxStore: ConversationOutboxStore
    private let snapshotStore: ConversationSnapshotStore
    private let photoCacheStore: ConversationPhotoCacheStore
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTasks: [Task<Void, Never>] = []

    init(
        client: SupabaseClient,
        currentUserID: UUID,
        relationshipID: UUID,
        outboxStore: ConversationOutboxStore = ConversationOutboxStore(),
        snapshotStore: ConversationSnapshotStore = ConversationSnapshotStore(),
        photoCacheStore: ConversationPhotoCacheStore = ConversationPhotoCacheStore()
    ) {
        self.client = client
        self.currentUserID = currentUserID
        self.relationshipID = relationshipID
        self.outboxStore = outboxStore
        self.snapshotStore = snapshotStore
        self.photoCacheStore = photoCacheStore
    }

    func fetchPendingSnapshot() async throws -> ConversationPendingSnapshot {
        let queue = try outboxStore.load(userID: currentUserID, relationshipID: relationshipID)
        return ConversationPendingSnapshot(currentUserID: currentUserID, messages: queue.messages)
    }

    func fetchCachedSnapshot() async throws -> ConversationSnapshot? {
        try snapshotStore.load(userID: currentUserID, relationshipID: relationshipID)
    }

    func persistCachedSnapshot(_ snapshot: ConversationSnapshot) async {
        guard snapshot.currentUserID == currentUserID else { return }
        try? snapshotStore.save(snapshot, userID: currentUserID, relationshipID: relationshipID)
    }

    func enqueueMessage(
        _ draft: ChatMessageDraft,
        clientID: UUID,
        localCreatedAt: Date
    ) async throws {
        switch draft {
        case let .text(value):
            guard let body = ChatTextPolicy.normalizedBody(value) else {
                throw ConversationServiceError.invalidMessage
            }
            try outboxStore.enqueueText(
                body,
                userID: currentUserID,
                relationshipID: relationshipID,
                clientID: clientID,
                localCreatedAt: localCreatedAt
            )
        case let .photo(data):
            guard !data.isEmpty else { throw ConversationServiceError.invalidPhoto }
            try outboxStore.enqueuePhoto(
                data,
                userID: currentUserID,
                relationshipID: relationshipID,
                clientID: clientID,
                localCreatedAt: localCreatedAt
            )
        }
    }

    func beginNextPendingMessage() async throws -> ChatMessage? {
        var queue = try outboxStore.load(userID: currentUserID, relationshipID: relationshipID)
        guard let entry = queue.beginFirstAttempt() else { return nil }
        try outboxStore.save(queue, userID: currentUserID, relationshipID: relationshipID)
        return ChatMessage(
            id: entry.clientID,
            senderUserID: entry.userID,
            content: entry.content.messageContent,
            createdAt: entry.localCreatedAt,
            deliveryState: .sending
        )
    }

    func acknowledgePendingMessage(clientID: UUID) async throws {
        try outboxStore.acknowledgeFirst(
            clientID: clientID,
            userID: currentUserID,
            relationshipID: relationshipID
        )
    }

    func deliverPendingMessage(_ message: ChatMessage) async throws -> ConversationDeliveryResult {
        _ = try await client.auth.session
        switch message.content {
        case let .text(value):
            guard let body = ChatTextPolicy.normalizedBody(value) else {
                throw ConversationServiceError.invalidMessage
            }
            let acceptedAt: Date = try await client.rpc(
                "write_shared_message",
                params: SendChatMessageParameters(
                    targetRelationshipID: relationshipID,
                    targetClientID: message.id,
                    targetBody: body
                )
            ).execute().value
            return .accepted(acceptedAt)
        case .photo:
            return try await deliverPendingPhoto(messageID: message.id)
        }
    }

    func fetchSnapshot() async throws -> ConversationSnapshot {
        let session = try await client.auth.session
        guard session.user.id == currentUserID else {
            throw ConversationServiceError.unexpectedAuthenticatedUser
        }
        let rows: [ChatMessageRow] = try await client
            .from("shared_items")
            .select("client_id,creator_user_id,item_kind,text_content,media_byte_size,created_at")
            .eq("relationship_id", value: relationshipID)
            .order("created_at", ascending: true)
            .order("client_id", ascending: true)
            .execute()
            .value
        let reactionRows: [ChatMessageReactionRow] = try await client
            .from("shared_item_reactions")
            .select("message_client_id,client_id,reactor_user_id,emoji_value,updated_at")
            .eq("relationship_id", value: relationshipID)
            .execute()
            .value
        let reactions = try Dictionary(
            uniqueKeysWithValues: reactionRows.map { ($0.messageClientID, try $0.reaction()) }
        )
        let messages = try rows.compactMap { try $0.message(reaction: reactions[$0.clientID]) }
        let unreadCount: Int = try await client.rpc(
            "conversation_unread_count",
            params: ConversationRelationshipParameters(targetRelationshipID: relationshipID)
        ).execute().value
        let snapshot = ConversationSnapshot(
            currentUserID: currentUserID,
            messages: messages,
            unreadCount: unreadCount
        )
        try snapshotStore.save(snapshot, userID: currentUserID, relationshipID: relationshipID)
        return snapshot
    }

    func cachedPhotoData(for messageID: UUID) -> Data? {
        if let data = try? photoCacheStore.load(
            userID: currentUserID,
            relationshipID: relationshipID,
            messageID: messageID
        ) {
            return data
        }
        guard let queue = try? outboxStore.load(
            userID: currentUserID,
            relationshipID: relationshipID
        ), let entry = queue.entries.first(where: { $0.clientID == messageID }) else { return nil }
        return try? outboxStore.data(for: entry)
    }

    func photoData(for messageID: UUID) async throws -> Data {
        if let cached = cachedPhotoData(for: messageID) { return cached }
        let data = try await client.storage.from(Self.photoBucket)
            .download(path: photoPath(messageID: messageID))
        try? photoCacheStore.save(
            data,
            userID: currentUserID,
            relationshipID: relationshipID,
            messageID: messageID
        )
        return data
    }

    func setReaction(
        messageID: UUID,
        emoji: MomentEmoji,
        clientID: UUID
    ) async throws -> ChatMessageReaction {
        _ = try await client.auth.session
        let rows: [ChatMessageReactionRow] = try await client.rpc(
            "set_shared_item_reaction",
            params: SetSharedItemReactionParameters(
                targetRelationshipID: relationshipID,
                targetMessageClientID: messageID,
                targetClientID: clientID,
                targetEmojiValue: emoji.rawValue
            )
        ).execute().value
        guard let row = rows.first else { throw ConversationServiceError.missingReaction }
        return try row.reaction()
    }

    func removeReaction(messageID: UUID) async throws {
        _ = try await client.auth.session
        try await client.rpc(
            "remove_shared_item_reaction",
            params: RemoveSharedItemReactionParameters(
                targetRelationshipID: relationshipID,
                targetMessageClientID: messageID
            )
        ).execute()
    }

    func saveAsMoment(messageID: UUID, momentClientID: UUID) async throws -> UUID {
        _ = try await client.auth.session
        let rows: [SavedMomentRow] = try await client.rpc(
            "create_moment_from_shared_item",
            params: SaveSharedItemAsMomentParameters(
                targetRelationshipID: relationshipID,
                targetMessageClientID: messageID,
                targetMomentClientID: momentClientID
            )
        ).execute().value
        guard let row = rows.first else { throw ConversationServiceError.missingSavedMoment }
        return row.momentClientID
    }

    func markRead(through messageID: UUID) async throws {
        _ = try await client.auth.session
        try await client.rpc(
            "mark_conversation_read",
            params: MarkConversationReadParameters(
                targetRelationshipID: relationshipID,
                targetMessageClientID: messageID
            )
        ).execute()
    }

    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws {
        await stopObservingChanges()
        let channel = client.channel("conversation-\(UUID().uuidString.lowercased())")
        let messages = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "shared_items",
            filter: .eq("relationship_id", value: relationshipID.uuidString.lowercased())
        )
        let readState = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "conversation_read_states",
            filter: .eq("relationship_id", value: relationshipID.uuidString.lowercased())
        )
        realtimeChannel = channel
        realtimeTasks = [messages, readState].map { stream in
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

    private func deliverPendingPhoto(messageID: UUID) async throws -> ConversationDeliveryResult {
        let queue = try outboxStore.load(userID: currentUserID, relationshipID: relationshipID)
        guard let entry = queue.entries.first, entry.clientID == messageID,
              case let .photo(_, byteSize) = entry.content else {
            throw ConversationServiceError.pendingMessageMismatch
        }
        let data = try outboxStore.data(for: entry)
        guard data.count == byteSize else { throw ConversationServiceError.invalidPhoto }
        let path = photoPath(messageID: messageID)
        let bucket = client.storage.from(Self.photoBucket)
        var objectAlreadyExists = false
        if entry.attemptCount > 1, (try? await bucket.download(path: path)) != nil {
            objectAlreadyExists = true
        }
        if !objectAlreadyExists {
            try await bucket.upload(
                path,
                data: data,
                options: FileOptions(contentType: "image/jpeg", upsert: false)
            )
        }
        let results: [ChatPhotoFinalizeResponse] = try await client.rpc(
            "finalize_chat_photo_upload",
            params: FinalizeChatPhotoParameters(
                targetRelationshipID: relationshipID,
                targetClientID: messageID,
                targetByteSize: data.count
            )
        ).execute().value
        guard let result = results.first else { throw ConversationServiceError.missingPhotoResult }
        if result.accepted {
            guard let acceptedAt = result.acceptedAt else {
                throw ConversationServiceError.missingPhotoResult
            }
            try? photoCacheStore.save(
                data,
                userID: currentUserID,
                relationshipID: relationshipID,
                messageID: messageID
            )
            return .accepted(acceptedAt)
        }
        let message: String
        switch result.reason {
        case "monthly_photo_limit":
            message = "本月照片新增已達目前上限。"
        case "total_storage_limit":
            message = "你們的照片總容量已達目前上限。"
        default:
            throw ConversationServiceError.unknownPhotoRejection
        }
        do {
            _ = try await bucket.remove(paths: [path])
        } catch {
            throw ConversationServiceError.photoRejectionCleanupFailed
        }
        return .rejected(message)
    }

    private func photoPath(messageID: UUID) -> String {
        relationshipID.uuidString.lowercased() + "/" + messageID.uuidString.lowercased() + ".jpg"
    }
}

private enum ConversationServiceError: LocalizedError {
    case invalidMessage
    case invalidPhoto
    case invalidServerMessage
    case invalidServerReaction
    case unexpectedAuthenticatedUser
    case pendingMessageMismatch
    case missingPhotoResult
    case unknownPhotoRejection
    case photoRejectionCleanupFailed
    case missingReaction
    case missingSavedMoment

    var errorDescription: String? {
        switch self {
        case .invalidMessage: "訊息內容不完整。"
        case .invalidPhoto: "照片內容無效。"
        case .invalidServerMessage: "伺服器回傳的訊息無效。"
        case .invalidServerReaction: "伺服器回傳的 Emoji 回應無效。"
        case .unexpectedAuthenticatedUser: "登入身分已變更。"
        case .pendingMessageMismatch: "待送訊息順序不一致。"
        case .missingPhotoResult: "伺服器未回傳照片結果。"
        case .unknownPhotoRejection: "伺服器拒絕照片，但原因無法辨識。"
        case .photoRejectionCleanupFailed: "照片未通過額度檢查，遠端暫存清理尚未完成。"
        case .missingReaction: "伺服器未回傳 Emoji 回應。"
        case .missingSavedMoment: "伺服器未回傳收藏結果。"
        }
    }
}

@MainActor
final class InMemoryConversationService: ConversationRemoteServing {
    private let currentUserID: UUID
    private var messages: [ChatMessage]
    private var unreadCount: Int
    private var pendingMessages: [ChatMessage] = []
    private var photoDataByMessageID: [UUID: Data] = [:]
    private var sendFailuresRemaining: Int
    private var savedMomentByMessageID: [UUID: UUID] = [:]

    init(
        currentUserID: UUID = UUID(),
        messages: [ChatMessage] = [],
        unreadCount: Int = 0,
        sendFailuresRemaining: Int = 0,
        photoDataByMessageID: [UUID: Data] = [:]
    ) {
        self.currentUserID = currentUserID
        self.messages = messages
        self.unreadCount = unreadCount
        self.sendFailuresRemaining = sendFailuresRemaining
        self.photoDataByMessageID = photoDataByMessageID
    }

    func fetchPendingSnapshot() async throws -> ConversationPendingSnapshot {
        ConversationPendingSnapshot(currentUserID: currentUserID, messages: pendingMessages)
    }

    func fetchCachedSnapshot() async throws -> ConversationSnapshot? {
        ConversationSnapshot(currentUserID: currentUserID, messages: messages, unreadCount: unreadCount)
    }

    func persistCachedSnapshot(_ snapshot: ConversationSnapshot) async {}

    func enqueueMessage(
        _ draft: ChatMessageDraft,
        clientID: UUID,
        localCreatedAt: Date
    ) async throws {
        let content: ChatMessageContent
        switch draft {
        case let .text(value):
            guard let body = ChatTextPolicy.normalizedBody(value) else {
                throw ConversationServiceError.invalidMessage
            }
            content = .text(body)
        case let .photo(data):
            guard !data.isEmpty else { throw ConversationServiceError.invalidPhoto }
            content = .photo
            photoDataByMessageID[clientID] = data
        }
        pendingMessages.append(ChatMessage(
            id: clientID,
            senderUserID: currentUserID,
            content: content,
            createdAt: localCreatedAt,
            deliveryState: .sending
        ))
    }

    func beginNextPendingMessage() async throws -> ChatMessage? {
        pendingMessages.first.map {
            ChatMessage(
                id: $0.id,
                senderUserID: $0.senderUserID,
                content: $0.content,
                createdAt: $0.createdAt,
                deliveryState: .sending,
                reaction: $0.reaction
            )
        }
    }

    func acknowledgePendingMessage(clientID: UUID) async throws {
        guard pendingMessages.first?.id == clientID else {
            throw ConversationOutboxError.unexpectedAcknowledgement
        }
        pendingMessages.removeFirst()
    }

    func deliverPendingMessage(_ message: ChatMessage) async throws -> ConversationDeliveryResult {
        if sendFailuresRemaining > 0 {
            sendFailuresRemaining -= 1
            throw URLError(.notConnectedToInternet)
        }
        if let existing = messages.first(where: { $0.id == message.id }) {
            guard existing.senderUserID == currentUserID, existing.content == message.content else {
                throw ConversationServiceError.invalidMessage
            }
            return .accepted(existing.createdAt)
        }
        let acceptedAt = Date.now
        messages.append(ChatMessage(
            id: message.id,
            senderUserID: currentUserID,
            content: message.content,
            createdAt: acceptedAt
        ))
        return .accepted(acceptedAt)
    }

    func fetchSnapshot() async throws -> ConversationSnapshot {
        ConversationSnapshot(
            currentUserID: currentUserID,
            messages: messages.sorted {
                ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
            },
            unreadCount: unreadCount
        )
    }

    func cachedPhotoData(for messageID: UUID) -> Data? { photoDataByMessageID[messageID] }

    func photoData(for messageID: UUID) async throws -> Data {
        guard let data = photoDataByMessageID[messageID] else {
            throw ConversationServiceError.invalidPhoto
        }
        return data
    }

    func setReaction(
        messageID: UUID,
        emoji: MomentEmoji,
        clientID: UUID
    ) async throws -> ChatMessageReaction {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              messages[index].senderUserID != currentUserID else {
            throw ConversationServiceError.invalidMessage
        }
        let reaction = ChatMessageReaction(
            id: clientID,
            reactorUserID: currentUserID,
            emoji: emoji,
            updatedAt: .now
        )
        messages[index].reaction = reaction
        return reaction
    }

    func removeReaction(messageID: UUID) async throws {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              messages[index].senderUserID != currentUserID else {
            throw ConversationServiceError.invalidMessage
        }
        messages[index].reaction = nil
    }

    func saveAsMoment(messageID: UUID, momentClientID: UUID) async throws -> UUID {
        guard messages.contains(where: { $0.id == messageID && $0.deliveryState == .synced }) else {
            throw ConversationServiceError.invalidMessage
        }
        if let existing = savedMomentByMessageID[messageID] { return existing }
        savedMomentByMessageID[messageID] = momentClientID
        return momentClientID
    }

    func markRead(through messageID: UUID) async throws {
        guard messages.contains(where: { $0.id == messageID }) else {
            throw ConversationServiceError.invalidMessage
        }
        unreadCount = 0
    }

    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws {}
    func stopObservingChanges() async {}
}
