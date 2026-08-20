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
    func fetchPage(before cursor: ConversationPageCursor?, limit: Int) async throws
        -> ConversationPage
    func cachedPhotoData(for messageID: UUID) -> Data?
    func photoData(for messageID: UUID) async throws -> Data
    func setReaction(
        messageID: UUID,
        emojiValue: String,
        clientID: UUID
    ) async throws -> ChatMessageReaction
    func removeReaction(messageID: UUID) async throws
    func saveAsMoment(messageID: UUID, momentClientID: UUID) async throws -> UUID
    func markRead(through messageID: UUID) async throws
    func markAllRelationshipInteractionsRead() async throws
    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws
    func stopObservingChanges() async
}

extension ConversationRemoteServing {
    func fetchPage(before cursor: ConversationPageCursor?, limit: Int) async throws
        -> ConversationPage
    {
        let snapshot = try await fetchSnapshot()
        let eligible = snapshot.messages.filter { message in
            guard let cursor else { return true }
            if message.createdAt != cursor.createdAt {
                return message.createdAt < cursor.createdAt
            }
            return message.id.uuidString < cursor.clientID.uuidString
        }
        let descending = eligible.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString > $1.id.uuidString
        }
        let messages = Array(descending.prefix(limit)).sorted {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }
        let visibleIDs = Set(messages.map(\.id))
        return ConversationPage(
            snapshot: ConversationSnapshot(
                currentUserID: snapshot.currentUserID,
                messages: messages,
                unreadCount: snapshot.unreadCount,
                savedMomentMessageIDs: snapshot.savedMomentMessageIDs.intersection(visibleIDs)
            ),
            hasMore: eligible.count > limit
        )
    }
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
        guard let emojiValue = ChatReactionPolicy.normalizedEmojiValue(emojiValue) else {
            throw ConversationServiceError.invalidServerReaction
        }
        return ChatMessageReaction(
            id: clientID,
            reactorUserID: reactorUserID,
            emojiValue: emojiValue,
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

private struct SendAppointmentMessageParameters: Encodable {
    let targetRelationshipID: UUID
    let targetAppointmentClientID: UUID
    let targetClientID: UUID
    let targetBody: String

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetAppointmentClientID = "target_appointment_client_id"
        case targetClientID = "target_client_id"
        case targetBody = "target_body"
    }
}

private enum PushEventKind: String {
    case chatMessageCreated = "chat_message_created"
    case appointmentDiscussionMessageCreated = "appointment_discussion_message_created"
}

private struct EnqueuePushEventParameters: Encodable {
    let targetEventKind: String
    let targetSourceItemID: UUID

    enum CodingKeys: String, CodingKey {
        case targetEventKind = "target_event_kind"
        case targetSourceItemID = "target_source_item_id"
    }
}

private struct PushDeliveryInvocation: Encodable {
    let jobID: UUID

    enum CodingKeys: String, CodingKey { case jobID = "job_id" }
}

private struct MarkRelationshipInteractionsReadThroughMessageParameters: Encodable {
    let targetRelationshipID: UUID
    let targetScopeID: UUID
    let targetMessageClientID: UUID

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetScopeID = "target_scope_id"
        case targetMessageClientID = "target_message_client_id"
    }
}

private struct SharedItemIdentifierRow: Decodable {
    let id: UUID
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

private struct FinalizeAppointmentPhotoParameters: Encodable {
    let targetRelationshipID: UUID
    let targetAppointmentClientID: UUID
    let targetClientID: UUID
    let targetByteSize: Int

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetAppointmentClientID = "target_appointment_client_id"
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

private struct AppointmentConversationParameters: Encodable {
    let targetRelationshipID: UUID
    let targetAppointmentClientID: UUID

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetAppointmentClientID = "target_appointment_client_id"
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

private struct MarkAppointmentConversationReadParameters: Encodable {
    let targetRelationshipID: UUID
    let targetAppointmentClientID: UUID
    let targetMessageClientID: UUID

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetAppointmentClientID = "target_appointment_client_id"
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

private struct SavedMomentSourceRow: Decodable {
    let sourceMessageID: UUID?

    enum CodingKeys: String, CodingKey {
        case sourceMessageID = "source_shared_item_client_id"
    }
}

@MainActor
final class SupabaseConversationService: ConversationRemoteServing {
    private static let photoBucket = "couplespace-w1-photos"
    private static let cursorDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let client: SupabaseClient
    private let currentUserID: UUID
    private let relationshipID: UUID
    private let scope: ConversationScope
    private let outboxStore: ConversationOutboxStore
    private let snapshotStore: ConversationSnapshotStore
    private let photoCacheStore: ConversationPhotoCacheStore
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTasks: [Task<Void, Never>] = []

    init(
        client: SupabaseClient,
        currentUserID: UUID,
        relationshipID: UUID,
        scope: ConversationScope = .main,
        outboxStore: ConversationOutboxStore? = nil,
        snapshotStore: ConversationSnapshotStore? = nil,
        photoCacheStore: ConversationPhotoCacheStore = ConversationPhotoCacheStore()
    ) {
        self.client = client
        self.currentUserID = currentUserID
        self.relationshipID = relationshipID
        self.scope = scope
        self.outboxStore = outboxStore ?? ConversationOutboxStore(
            appointmentScopeID: scope.appointmentID
        )
        self.snapshotStore = snapshotStore ?? ConversationSnapshotStore(
            appointmentScopeID: scope.appointmentID
        )
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
            let acceptedAt: Date
            switch scope {
            case .main:
                acceptedAt = try await client.rpc(
                    "write_shared_message",
                    params: SendChatMessageParameters(
                        targetRelationshipID: relationshipID,
                        targetClientID: message.id,
                        targetBody: body
                    )
                ).execute().value
            case let .appointment(appointmentID):
                acceptedAt = try await client.rpc(
                    "write_appointment_discussion_message",
                    params: SendAppointmentMessageParameters(
                        targetRelationshipID: relationshipID,
                        targetAppointmentClientID: appointmentID,
                        targetClientID: message.id,
                        targetBody: body
                    )
                ).execute().value
            }
            try await enqueuePushEvent(for: message.id)
            return .accepted(acceptedAt)
        case .photo:
            return try await deliverPendingPhoto(messageID: message.id)
        }
    }

    func fetchSnapshot() async throws -> ConversationSnapshot {
        try await fetchPage(before: nil, limit: 50).snapshot
    }

    private func enqueuePushEvent(for messageID: UUID) async throws {
        var query = client
            .from("shared_items")
            .select("id")
            .eq("relationship_id", value: relationshipID)
            .eq("client_id", value: messageID)
            .in("item_kind", values: ["message", "photo"])
        let eventKind: PushEventKind
        switch scope {
        case .main:
            query = query.is("appointment_client_id", value: nil)
            eventKind = .chatMessageCreated
        case let .appointment(appointmentID):
            query = query.eq("appointment_client_id", value: appointmentID)
            eventKind = .appointmentDiscussionMessageCreated
        }
        let rows: [SharedItemIdentifierRow] = try await query.limit(1).execute().value
        guard let sourceItemID = rows.first?.id else {
            throw ConversationServiceError.invalidServerMessage
        }
        let jobID: UUID = try await client.rpc(
            "enqueue_push_event",
            params: EnqueuePushEventParameters(
                targetEventKind: eventKind.rawValue,
                targetSourceItemID: sourceItemID
            )
        ).execute().value
        try? await client.functions.invoke(
            "send-w1-push",
            options: FunctionInvokeOptions(body: PushDeliveryInvocation(jobID: jobID))
        )
    }

    func fetchPage(before cursor: ConversationPageCursor?, limit: Int) async throws
        -> ConversationPage
    {
        let session = try await client.auth.session
        guard session.user.id == currentUserID else {
            throw ConversationServiceError.unexpectedAuthenticatedUser
        }
        var messageQuery = client
            .from("shared_items")
            .select("client_id,creator_user_id,item_kind,text_content,media_byte_size,created_at")
            .eq("relationship_id", value: relationshipID)
            .in("item_kind", values: ["message", "photo"])
        switch scope {
        case .main:
            messageQuery = messageQuery.is("appointment_client_id", value: nil)
        case let .appointment(appointmentID):
            messageQuery = messageQuery.eq("appointment_client_id", value: appointmentID)
        }
        if let cursor {
            let timestamp = Self.cursorDateFormatter.string(from: cursor.createdAt)
            messageQuery = messageQuery.or(
                "created_at.lt.\(timestamp),and(created_at.eq.\(timestamp),client_id.lt.\(cursor.clientID.uuidString.lowercased()))"
            )
        }
        let rows: [ChatMessageRow] = try await messageQuery
            .order("created_at", ascending: false)
            .order("client_id", ascending: false)
            .limit(limit + 1)
            .execute()
            .value
        let pageRows = Array(rows.prefix(limit))
        let messageIDs = pageRows.map(\.clientID)
        let reactionRows: [ChatMessageReactionRow]
        if messageIDs.isEmpty {
            reactionRows = []
        } else {
            reactionRows = try await client
                .from("shared_item_reactions")
                .select("message_client_id,client_id,reactor_user_id,emoji_value,updated_at")
                .eq("relationship_id", value: relationshipID)
                .in("message_client_id", values: messageIDs)
                .execute()
                .value
        }
        let reactions = try Dictionary(
            uniqueKeysWithValues: reactionRows.map { ($0.messageClientID, try $0.reaction()) }
        )
        let messages = try pageRows
            .compactMap { try $0.message(reaction: reactions[$0.clientID]) }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        let visibleMessageIDs = Set(messages.map(\.id))
        let savedMomentRows: [SavedMomentSourceRow]
        if messageIDs.isEmpty {
            savedMomentRows = []
        } else {
            savedMomentRows = try await client
                .from("moments")
                .select("source_shared_item_client_id")
                .eq("relationship_id", value: relationshipID)
                .in("source_shared_item_client_id", values: messageIDs)
                .is("deleted_at", value: nil)
                .execute()
                .value
        }
        let savedMomentMessageIDs = Set(savedMomentRows.compactMap(\.sourceMessageID))
            .intersection(visibleMessageIDs)
        let unreadCount: Int
        switch scope {
        case .main:
            unreadCount = try await client.rpc(
                "conversation_unread_count",
                params: ConversationRelationshipParameters(targetRelationshipID: relationshipID)
            ).execute().value
        case let .appointment(appointmentID):
            unreadCount = try await client.rpc(
                "appointment_discussion_unread_count",
                params: AppointmentConversationParameters(
                    targetRelationshipID: relationshipID,
                    targetAppointmentClientID: appointmentID
                )
            ).execute().value
        }
        let snapshot = ConversationSnapshot(
            currentUserID: currentUserID,
            messages: messages,
            unreadCount: unreadCount,
            savedMomentMessageIDs: savedMomentMessageIDs
        )
        return ConversationPage(snapshot: snapshot, hasMore: rows.count > limit)
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
        emojiValue: String,
        clientID: UUID
    ) async throws -> ChatMessageReaction {
        guard let emojiValue = ChatReactionPolicy.normalizedEmojiValue(emojiValue) else {
            throw ConversationServiceError.invalidServerReaction
        }
        _ = try await client.auth.session
        let rows: [ChatMessageReactionRow] = try await client.rpc(
            "set_shared_item_reaction",
            params: SetSharedItemReactionParameters(
                targetRelationshipID: relationshipID,
                targetMessageClientID: messageID,
                targetClientID: clientID,
                targetEmojiValue: emojiValue
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
        switch scope {
        case .main:
            try await client.rpc(
                "mark_conversation_read",
                params: MarkConversationReadParameters(
                    targetRelationshipID: relationshipID,
                    targetMessageClientID: messageID
                )
            ).execute()
        case let .appointment(appointmentID):
            try await client.rpc(
                "mark_appointment_discussion_read",
                params: MarkAppointmentConversationReadParameters(
                    targetRelationshipID: relationshipID,
                    targetAppointmentClientID: appointmentID,
                    targetMessageClientID: messageID
                )
            ).execute()
        }
        let scopeID: UUID
        switch scope {
        case .main: scopeID = relationshipID
        case let .appointment(appointmentID): scopeID = appointmentID
        }
        try await client.rpc(
            "mark_relationship_interactions_read_through_message",
            params: MarkRelationshipInteractionsReadThroughMessageParameters(
                targetRelationshipID: relationshipID,
                targetScopeID: scopeID,
                targetMessageClientID: messageID
            )
        ).execute()
    }

    func markAllRelationshipInteractionsRead() async throws {
        _ = try await client.auth.session
        try await client.rpc(
            "mark_all_relationship_interactions_read",
            params: ConversationRelationshipParameters(targetRelationshipID: relationshipID)
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
        let moments = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "moments",
            filter: .eq("relationship_id", value: relationshipID.uuidString.lowercased())
        )
        realtimeChannel = channel
        realtimeTasks = [messages, readState, moments].map { stream in
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
        let results: [ChatPhotoFinalizeResponse]
        switch scope {
        case .main:
            results = try await client.rpc(
                "finalize_chat_photo_upload",
                params: FinalizeChatPhotoParameters(
                    targetRelationshipID: relationshipID,
                    targetClientID: messageID,
                    targetByteSize: data.count
                )
            ).execute().value
        case let .appointment(appointmentID):
            results = try await client.rpc(
                "finalize_appointment_discussion_photo_upload",
                params: FinalizeAppointmentPhotoParameters(
                    targetRelationshipID: relationshipID,
                    targetAppointmentClientID: appointmentID,
                    targetClientID: messageID,
                    targetByteSize: data.count
                )
            ).execute().value
        }
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
            try? await enqueuePushEvent(for: messageID)
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
    private let returnsCachedSnapshot: Bool
    private let onMarkRead: @MainActor (UUID) async -> Void

    init(
        currentUserID: UUID = UUID(),
        messages: [ChatMessage] = [],
        unreadCount: Int = 0,
        sendFailuresRemaining: Int = 0,
        photoDataByMessageID: [UUID: Data] = [:],
        returnsCachedSnapshot: Bool = true,
        onMarkRead: @escaping @MainActor (UUID) async -> Void = { _ in }
    ) {
        self.currentUserID = currentUserID
        self.messages = messages
        self.unreadCount = unreadCount
        self.sendFailuresRemaining = sendFailuresRemaining
        self.photoDataByMessageID = photoDataByMessageID
        self.returnsCachedSnapshot = returnsCachedSnapshot
        self.onMarkRead = onMarkRead
    }

    func fetchPendingSnapshot() async throws -> ConversationPendingSnapshot {
        ConversationPendingSnapshot(currentUserID: currentUserID, messages: pendingMessages)
    }

    func fetchCachedSnapshot() async throws -> ConversationSnapshot? {
        guard returnsCachedSnapshot else { return nil }
        return ConversationSnapshot(
            currentUserID: currentUserID,
            messages: messages,
            unreadCount: unreadCount
        )
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
            unreadCount: unreadCount,
            savedMomentMessageIDs: Set(savedMomentByMessageID.keys)
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
        emojiValue: String,
        clientID: UUID
    ) async throws -> ChatMessageReaction {
        guard let emojiValue = ChatReactionPolicy.normalizedEmojiValue(emojiValue) else {
            throw ConversationServiceError.invalidServerReaction
        }
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              messages[index].senderUserID != currentUserID else {
            throw ConversationServiceError.invalidMessage
        }
        let reaction = ChatMessageReaction(
            id: clientID,
            reactorUserID: currentUserID,
            emojiValue: emojiValue,
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
        await onMarkRead(messageID)
    }

    func markAllRelationshipInteractionsRead() async throws {}

    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws {}
    func stopObservingChanges() async {}
}
