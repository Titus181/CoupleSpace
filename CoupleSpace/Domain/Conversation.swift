import Foundation

enum ChatMessageContent: Equatable, Sendable {
    case text(String)
    case photo
}

struct ChatMessageReaction: Equatable, Sendable {
    let id: UUID
    let reactorUserID: UUID
    let emojiValue: String
    let updatedAt: Date

    init(id: UUID, reactorUserID: UUID, emoji: MomentEmoji, updatedAt: Date) {
        self.init(
            id: id,
            reactorUserID: reactorUserID,
            emojiValue: emoji.rawValue,
            updatedAt: updatedAt
        )
    }

    init(id: UUID, reactorUserID: UUID, emojiValue: String, updatedAt: Date) {
        self.id = id
        self.reactorUserID = reactorUserID
        self.emojiValue = emojiValue
        self.updatedAt = updatedAt
    }

    var emoji: MomentEmoji? { MomentEmoji(rawValue: emojiValue) }
    var symbol: String { emoji?.symbol ?? emojiValue }
    var accessibilityLabel: String { emoji?.accessibilityLabel ?? emojiValue }
}

enum ChatReactionPolicy {
    static func normalizedEmojiValue(_ value: String) -> String? {
        if MomentEmoji(rawValue: value) != nil { return value }
        return MomentResponsePolicy.normalizedEmoji(value)
    }
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
