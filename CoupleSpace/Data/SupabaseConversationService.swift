import Foundation
import Supabase

@MainActor
protocol ConversationRemoteServing: AnyObject {
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
    private let relationshipID: UUID
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTasks: [Task<Void, Never>] = []

    init(client: SupabaseClient, relationshipID: UUID) {
        self.client = client
        self.relationshipID = relationshipID
    }

    func fetchSnapshot() async throws -> ConversationSnapshot {
        let session = try await client.auth.session
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
        return ConversationSnapshot(
            currentUserID: session.user.id,
            messages: rows.map(\.message),
            unreadCount: unreadCount
        )
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

    var errorDescription: String? { "訊息內容不完整。" }
}

@MainActor
final class InMemoryConversationService: ConversationRemoteServing {
    private let currentUserID: UUID
    private var messages: [ChatMessage]
    private var unreadCount: Int

    init(
        currentUserID: UUID = UUID(),
        messages: [ChatMessage] = [],
        unreadCount: Int = 0
    ) {
        self.currentUserID = currentUserID
        self.messages = messages
        self.unreadCount = unreadCount
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
