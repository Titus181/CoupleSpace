import Foundation

struct ConversationPendingSnapshot: Equatable, Sendable {
    let currentUserID: UUID
    let messages: [ChatMessage]
}

struct ConversationOutboxEntry: Codable, Equatable, Sendable {
    let userID: UUID
    let relationshipID: UUID
    let clientID: UUID
    let body: String
    let localCreatedAt: Date
    var attemptCount: Int

}

struct ConversationOutboxQueue: Codable, Equatable, Sendable {
    private(set) var entries: [ConversationOutboxEntry] = []

    var isEmpty: Bool { entries.isEmpty }
    var messages: [ChatMessage] {
        let isBlockedByFailedHead = entries.first?.attemptCount ?? 0 > 0
        return entries.map { entry in
            ChatMessage(
                id: entry.clientID,
                senderUserID: entry.userID,
                body: entry.body,
                createdAt: entry.localCreatedAt,
                deliveryState: isBlockedByFailedHead ? .failed : .sending
            )
        }
    }

    mutating func enqueue(_ entry: ConversationOutboxEntry) throws {
        if let existing = entries.first(where: { $0.clientID == entry.clientID }) {
            guard existing == entry else {
                throw ConversationOutboxError.clientIDCollision
            }
            return
        }
        entries.append(entry)
    }

    mutating func beginFirstAttempt() -> ConversationOutboxEntry? {
        guard !entries.isEmpty else { return nil }
        entries[0].attemptCount += 1
        return entries[0]
    }

    mutating func acknowledgeFirst(clientID: UUID) throws {
        guard entries.first?.clientID == clientID else {
            throw ConversationOutboxError.unexpectedAcknowledgement
        }
        entries.removeFirst()
    }
}

struct ConversationOutboxStore {
    private let defaults: UserDefaults
    private let keyPrefix = "couplespace.conversation-outbox.v1."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(userID: UUID, relationshipID: UUID) throws -> ConversationOutboxQueue {
        guard let data = defaults.data(forKey: key(userID: userID, relationshipID: relationshipID)) else {
            return ConversationOutboxQueue()
        }
        return try JSONDecoder().decode(ConversationOutboxQueue.self, from: data)
    }

    func save(_ queue: ConversationOutboxQueue, userID: UUID, relationshipID: UUID) throws {
        let key = key(userID: userID, relationshipID: relationshipID)
        guard !queue.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(try JSONEncoder().encode(queue), forKey: key)
    }

    func clearAll(userID: UUID) {
        let userPrefix = keyPrefix + userID.uuidString.lowercased() + "."
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(userPrefix) }
            .forEach(defaults.removeObject(forKey:))
    }

    private func key(userID: UUID, relationshipID: UUID) -> String {
        keyPrefix
            + userID.uuidString.lowercased()
            + "."
            + relationshipID.uuidString.lowercased()
    }
}

private struct ConversationCachedMessage: Codable, Equatable {
    let id: UUID
    let senderUserID: UUID
    let body: String
    let createdAt: Date

    init(_ message: ChatMessage) {
        id = message.id
        senderUserID = message.senderUserID
        body = message.body
        createdAt = message.createdAt
    }

    var message: ChatMessage {
        ChatMessage(
            id: id,
            senderUserID: senderUserID,
            body: body,
            createdAt: createdAt
        )
    }
}

private struct ConversationCachedSnapshot: Codable, Equatable {
    let messages: [ConversationCachedMessage]
    let unreadCount: Int
}

struct ConversationSnapshotStore {
    private let defaults: UserDefaults
    private let keyPrefix = "couplespace.conversation-snapshot.v1."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(userID: UUID, relationshipID: UUID) throws -> ConversationSnapshot? {
        guard let data = defaults.data(forKey: key(userID: userID, relationshipID: relationshipID)) else {
            return nil
        }
        let cached = try JSONDecoder().decode(ConversationCachedSnapshot.self, from: data)
        return ConversationSnapshot(
            currentUserID: userID,
            messages: cached.messages.map(\.message),
            unreadCount: cached.unreadCount
        )
    }

    func save(_ snapshot: ConversationSnapshot, userID: UUID, relationshipID: UUID) throws {
        let messages = snapshot.messages
            .filter { $0.deliveryState == .synced }
            .suffix(ConversationLocalSnapshotPolicy.maximumMessageCount)
            .map(ConversationCachedMessage.init)
        let cached = ConversationCachedSnapshot(
            messages: messages,
            unreadCount: snapshot.unreadCount
        )
        defaults.set(
            try JSONEncoder().encode(cached),
            forKey: key(userID: userID, relationshipID: relationshipID)
        )
    }

    func clearAll(userID: UUID) {
        let userPrefix = keyPrefix + userID.uuidString.lowercased() + "."
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(userPrefix) }
            .forEach(defaults.removeObject(forKey:))
    }

    private func key(userID: UUID, relationshipID: UUID) -> String {
        keyPrefix
            + userID.uuidString.lowercased()
            + "."
            + relationshipID.uuidString.lowercased()
    }
}

enum ConversationOutboxError: Error, Equatable {
    case clientIDCollision
    case unexpectedAcknowledgement
}

enum ConversationRecoveryRetryPolicy {
    static let maximumAttempts = 3

    static func delayNanoseconds(afterAttempt attempt: Int) -> UInt64? {
        switch attempt {
        case 1:
            1_000_000_000
        case 2:
            4_000_000_000
        default:
            nil
        }
    }
}
