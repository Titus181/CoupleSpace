import Foundation

struct ChatMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let senderUserID: UUID
    let body: String
    let createdAt: Date
    var deliveryState: ChatMessageDeliveryState = .synced
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

enum ChatTextPolicy {
    static let maximumLength = 4_000

    static func normalizedBody(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= maximumLength else { return nil }
        return normalized
    }
}
