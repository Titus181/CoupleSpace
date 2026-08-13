import Foundation
import Supabase

@MainActor
protocol ConversationRemoteServing: AnyObject {
    func fetchPendingSnapshot() async throws -> ConversationPendingSnapshot
    func fetchCachedSnapshot() async throws -> ConversationSnapshot?
    func persistCachedSnapshot(_ snapshot: ConversationSnapshot) async
    func enqueueMessage(body: String, clientID: UUID, localCreatedAt: Date) async throws
    func beginNextPendingMessage() async throws -> ChatMessage?
    func acknowledgePendingMessage(clientID: UUID) async throws
    func fetchSnapshot() async throws -> ConversationSnapshot
    func sendMessage(body: String, clientID: UUID) async throws -> Date
    func markRead(through messageID: UUID) async throws
    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws
    func stopObservingChanges() async
}

private struct ChatMessageRow: Decodable {
    let clientID: UUID
    let creatorUserID: UUID
    let textContent: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case creatorUserID = "creator_user_id"
        case textContent = "text_content"
        case createdAt = "created_at"
    }

    var message: ChatMessage {
        ChatMessage(
            id: clientID,
            senderUserID: creatorUserID,
            body: textContent,
            createdAt: createdAt
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

@MainActor
final class SupabaseConversationService: ConversationRemoteServing {
    private let client: SupabaseClient
    private let currentUserID: UUID
    private let relationshipID: UUID
    private let outboxStore: ConversationOutboxStore
    private let snapshotStore: ConversationSnapshotStore
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTasks: [Task<Void, Never>] = []

    init(
        client: SupabaseClient,
        currentUserID: UUID,
        relationshipID: UUID,
        outboxStore: ConversationOutboxStore = ConversationOutboxStore(),
        snapshotStore: ConversationSnapshotStore = ConversationSnapshotStore()
    ) {
        self.client = client
        self.currentUserID = currentUserID
        self.relationshipID = relationshipID
        self.outboxStore = outboxStore
        self.snapshotStore = snapshotStore
    }

    func fetchPendingSnapshot() async throws -> ConversationPendingSnapshot {
        let queue = try outboxStore.load(userID: currentUserID, relationshipID: relationshipID)
        return ConversationPendingSnapshot(
            currentUserID: currentUserID,
            messages: queue.messages
        )
    }

    func fetchCachedSnapshot() async throws -> ConversationSnapshot? {
        try snapshotStore.load(userID: currentUserID, relationshipID: relationshipID)
    }

    func persistCachedSnapshot(_ snapshot: ConversationSnapshot) async {
        guard snapshot.currentUserID == currentUserID else { return }
        try? snapshotStore.save(snapshot, userID: currentUserID, relationshipID: relationshipID)
    }

    func enqueueMessage(body: String, clientID: UUID, localCreatedAt: Date) async throws {
        guard let body = ChatTextPolicy.normalizedBody(body) else {
            throw ConversationServiceError.invalidMessage
        }
        var queue = try outboxStore.load(userID: currentUserID, relationshipID: relationshipID)
        try queue.enqueue(ConversationOutboxEntry(
            userID: currentUserID,
            relationshipID: relationshipID,
            clientID: clientID,
            body: body,
            localCreatedAt: localCreatedAt,
            attemptCount: 0
        ))
        try outboxStore.save(queue, userID: currentUserID, relationshipID: relationshipID)
    }

    func beginNextPendingMessage() async throws -> ChatMessage? {
        var queue = try outboxStore.load(userID: currentUserID, relationshipID: relationshipID)
        guard let entry = queue.beginFirstAttempt() else { return nil }
        try outboxStore.save(queue, userID: currentUserID, relationshipID: relationshipID)
        return ChatMessage(
            id: entry.clientID,
            senderUserID: entry.userID,
            body: entry.body,
            createdAt: entry.localCreatedAt,
            deliveryState: .sending
        )
    }

    func acknowledgePendingMessage(clientID: UUID) async throws {
        var queue = try outboxStore.load(userID: currentUserID, relationshipID: relationshipID)
        try queue.acknowledgeFirst(clientID: clientID)
        try outboxStore.save(queue, userID: currentUserID, relationshipID: relationshipID)
    }

    func fetchSnapshot() async throws -> ConversationSnapshot {
        let session = try await client.auth.session
        guard session.user.id == currentUserID else {
            throw ConversationServiceError.unexpectedAuthenticatedUser
        }
        let rows: [ChatMessageRow] = try await client
            .from("shared_items")
            .select("client_id,creator_user_id,text_content,created_at")
            .eq("relationship_id", value: relationshipID)
            .eq("item_kind", value: "message")
            .order("created_at", ascending: true)
            .order("client_id", ascending: true)
            .execute()
            .value
        let unreadCount: Int = try await client
            .rpc(
                "conversation_unread_count",
                params: ConversationRelationshipParameters(targetRelationshipID: relationshipID)
            )
            .execute()
            .value
        let snapshot = ConversationSnapshot(
            currentUserID: session.user.id,
            messages: rows.map(\.message),
            unreadCount: unreadCount
        )
        try snapshotStore.save(snapshot, userID: currentUserID, relationshipID: relationshipID)
        return snapshot
    }

    func sendMessage(body: String, clientID: UUID) async throws -> Date {
        _ = try await client.auth.session
        guard let body = ChatTextPolicy.normalizedBody(body) else {
            throw ConversationServiceError.invalidMessage
        }
        return try await client.rpc(
            "write_shared_message",
            params: SendChatMessageParameters(
                targetRelationshipID: relationshipID,
                targetClientID: clientID,
                targetBody: body
            )
        ).execute().value
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
}

private enum ConversationServiceError: LocalizedError {
    case invalidMessage
    case unexpectedAuthenticatedUser

    var errorDescription: String? {
        switch self {
        case .invalidMessage:
            "訊息內容不完整。"
        case .unexpectedAuthenticatedUser:
            "登入身分已變更。"
        }
    }
}

@MainActor
final class InMemoryConversationService: ConversationRemoteServing {
    private let currentUserID: UUID
    private var messages: [ChatMessage]
    private var unreadCount: Int
    private var pendingMessages: [ChatMessage] = []
    private var sendFailuresRemaining: Int

    init(
        currentUserID: UUID = UUID(),
        messages: [ChatMessage] = [],
        unreadCount: Int = 0,
        sendFailuresRemaining: Int = 0
    ) {
        self.currentUserID = currentUserID
        self.messages = messages
        self.unreadCount = unreadCount
        self.sendFailuresRemaining = sendFailuresRemaining
    }

    func fetchPendingSnapshot() async throws -> ConversationPendingSnapshot {
        ConversationPendingSnapshot(currentUserID: currentUserID, messages: pendingMessages)
    }

    func fetchCachedSnapshot() async throws -> ConversationSnapshot? {
        ConversationSnapshot(
            currentUserID: currentUserID,
            messages: messages,
            unreadCount: unreadCount
        )
    }

    func persistCachedSnapshot(_ snapshot: ConversationSnapshot) async {}

    func enqueueMessage(body: String, clientID: UUID, localCreatedAt: Date) async throws {
        guard let body = ChatTextPolicy.normalizedBody(body) else {
            throw ConversationServiceError.invalidMessage
        }
        pendingMessages.append(ChatMessage(
            id: clientID,
            senderUserID: currentUserID,
            body: body,
            createdAt: localCreatedAt,
            deliveryState: .sending
        ))
    }

    func beginNextPendingMessage() async throws -> ChatMessage? {
        pendingMessages.first.map {
            ChatMessage(
                id: $0.id,
                senderUserID: $0.senderUserID,
                body: $0.body,
                createdAt: $0.createdAt,
                deliveryState: .sending
            )
        }
    }

    func acknowledgePendingMessage(clientID: UUID) async throws {
        guard pendingMessages.first?.id == clientID else {
            throw ConversationOutboxError.unexpectedAcknowledgement
        }
        pendingMessages.removeFirst()
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

    func sendMessage(body: String, clientID: UUID) async throws -> Date {
        guard let body = ChatTextPolicy.normalizedBody(body) else {
            throw ConversationServiceError.invalidMessage
        }
        if sendFailuresRemaining > 0 {
            sendFailuresRemaining -= 1
            throw URLError(.notConnectedToInternet)
        }
        if let existing = messages.first(where: { $0.id == clientID }) {
            guard existing.senderUserID == currentUserID, existing.body == body else {
                throw ConversationServiceError.invalidMessage
            }
            return existing.createdAt
        }
        let acceptedAt = Date.now
        messages.append(ChatMessage(
            id: clientID,
            senderUserID: currentUserID,
            body: body,
            createdAt: acceptedAt
        ))
        return acceptedAt
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
