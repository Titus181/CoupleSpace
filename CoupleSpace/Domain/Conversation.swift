import Foundation

enum ChatMessageContent: Equatable, Sendable {
    case text(String)
    case photo
}

struct ChatMessageReaction: Equatable, Sendable {
    let id: UUID
    let reactorUserID: UUID
    let emoji: MomentEmoji
    let updatedAt: Date
}

struct ChatMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let senderUserID: UUID
    let content: ChatMessageContent
    let createdAt: Date
    var deliveryState: ChatMessageDeliveryState = .synced
    var reaction: ChatMessageReaction?

    init(
        id: UUID,
        senderUserID: UUID,
        content: ChatMessageContent,
        createdAt: Date,
        deliveryState: ChatMessageDeliveryState = .synced,
        reaction: ChatMessageReaction? = nil
    ) {
        self.id = id
        self.senderUserID = senderUserID
        self.content = content
        self.createdAt = createdAt
        self.deliveryState = deliveryState
        self.reaction = reaction
    }

    init(
        id: UUID,
        senderUserID: UUID,
        body: String,
        createdAt: Date,
        deliveryState: ChatMessageDeliveryState = .synced,
        reaction: ChatMessageReaction? = nil
    ) {
        self.init(
            id: id,
            senderUserID: senderUserID,
            content: .text(body),
            createdAt: createdAt,
            deliveryState: deliveryState,
            reaction: reaction
        )
    }

    var textBody: String? {
        guard case let .text(body) = content else { return nil }
        return body
    }
}

enum ChatMessageDeliveryState: Equatable, Sendable {
    case sending
    case synced
    case failed
}

struct ConversationSnapshot: Equatable, Sendable {
    let currentUserID: UUID
    let messages: [ChatMessage]
    let unreadCount: Int
}

enum ChatMessageDraft: Equatable, Sendable {
    case text(String)
    case photo(Data)
}

enum ConversationLocalSnapshotPolicy {
    static let maximumMessageCount = 200
}

enum ChatTextPolicy {
    static let maximumLength = 4_000

    static func normalizedBody(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= maximumLength else { return nil }
        return normalized
    }
}
