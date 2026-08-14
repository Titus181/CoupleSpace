import Foundation

struct ConversationPendingSnapshot: Equatable, Sendable {
    let currentUserID: UUID
    let messages: [ChatMessage]
}

enum ConversationOutboxContent: Codable, Equatable, Sendable {
    case text(String)
    case photo(localFileName: String, byteSize: Int)

    private enum CodingKeys: String, CodingKey { case kind, body, localFileName, byteSize }
    private enum Kind: String, Codable { case text, photo }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .text:
            self = .text(try container.decode(String.self, forKey: .body))
        case .photo:
            self = .photo(
                localFileName: try container.decode(String.self, forKey: .localFileName),
                byteSize: try container.decode(Int.self, forKey: .byteSize)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(body):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(body, forKey: .body)
        case let .photo(localFileName, byteSize):
            try container.encode(Kind.photo, forKey: .kind)
            try container.encode(localFileName, forKey: .localFileName)
            try container.encode(byteSize, forKey: .byteSize)
        }
    }

    var messageContent: ChatMessageContent {
        switch self {
        case let .text(body): .text(body)
        case .photo: .photo
        }
    }
}

enum ConversationOutboxLifecyclePolicy {
    enum ClosedRelationshipAction: Equatable {
        case discardUnsentText
        case acknowledgeDeliveredPhoto
        case deleteOrphanPhoto
    }

    enum ReconciliationError: LocalizedError, Equatable {
        case remoteIdentityMismatch

        var errorDescription: String? {
            "遠端照片識別與待送對話項目不一致"
        }
    }

    static func actionForClosingRelationship(
        content: ConversationOutboxContent,
        remoteCreatorID: UUID?,
        remoteItemKind: String?,
        currentUserID: UUID
    ) throws -> ClosedRelationshipAction {
        guard case .photo = content else { return .discardUnsentText }
        guard remoteCreatorID != nil || remoteItemKind != nil else {
            return .deleteOrphanPhoto
        }
        guard remoteCreatorID == currentUserID, remoteItemKind == "photo" else {
            throw ReconciliationError.remoteIdentityMismatch
        }
        return .acknowledgeDeliveredPhoto
    }

    static func actionForArchivedRelationship(
        content: ConversationOutboxContent,
        archivedItemKind: String?
    ) throws -> ClosedRelationshipAction {
        guard case .photo = content else { return .discardUnsentText }
        guard let archivedItemKind else { return .deleteOrphanPhoto }
        guard archivedItemKind == "photo" else {
            throw ReconciliationError.remoteIdentityMismatch
        }
        return .acknowledgeDeliveredPhoto
    }
}

struct ConversationOutboxEntry: Codable, Equatable, Sendable {
    let userID: UUID
    let relationshipID: UUID
    let clientID: UUID
    let content: ConversationOutboxContent
    let localCreatedAt: Date
    var attemptCount: Int

    init(
        userID: UUID,
        relationshipID: UUID,
        clientID: UUID,
        body: String,
        localCreatedAt: Date,
        attemptCount: Int
    ) {
        self.init(
            userID: userID,
            relationshipID: relationshipID,
            clientID: clientID,
            content: .text(body),
            localCreatedAt: localCreatedAt,
            attemptCount: attemptCount
        )
    }

    init(
        userID: UUID,
        relationshipID: UUID,
        clientID: UUID,
        content: ConversationOutboxContent,
        localCreatedAt: Date,
        attemptCount: Int
    ) {
        self.userID = userID
        self.relationshipID = relationshipID
        self.clientID = clientID
        self.content = content
        self.localCreatedAt = localCreatedAt
        self.attemptCount = attemptCount
    }

    private enum CodingKeys: String, CodingKey {
        case userID, relationshipID, clientID, content, body, localCreatedAt, attemptCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(UUID.self, forKey: .userID)
        relationshipID = try container.decode(UUID.self, forKey: .relationshipID)
        clientID = try container.decode(UUID.self, forKey: .clientID)
        localCreatedAt = try container.decode(Date.self, forKey: .localCreatedAt)
        attemptCount = try container.decode(Int.self, forKey: .attemptCount)
        if let decoded = try container.decodeIfPresent(ConversationOutboxContent.self, forKey: .content) {
            content = decoded
        } else {
            content = .text(try container.decode(String.self, forKey: .body))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(relationshipID, forKey: .relationshipID)
        try container.encode(clientID, forKey: .clientID)
        try container.encode(content, forKey: .content)
        try container.encode(localCreatedAt, forKey: .localCreatedAt)
        try container.encode(attemptCount, forKey: .attemptCount)
    }
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
                content: entry.content.messageContent,
                createdAt: entry.localCreatedAt,
                deliveryState: isBlockedByFailedHead ? .failed : .sending
            )
        }
    }

    mutating func enqueue(_ entry: ConversationOutboxEntry) throws {
        if let existing = entries.first(where: { $0.clientID == entry.clientID }) {
            guard existing == entry else { throw ConversationOutboxError.clientIDCollision }
            return
        }
        entries.append(entry)
    }

    mutating func beginFirstAttempt() -> ConversationOutboxEntry? {
        guard !entries.isEmpty else { return nil }
        entries[0].attemptCount += 1
        return entries[0]
    }

    mutating func acknowledgeFirst(clientID: UUID) throws -> ConversationOutboxEntry {
        guard entries.first?.clientID == clientID else {
            throw ConversationOutboxError.unexpectedAcknowledgement
        }
        return entries.removeFirst()
    }
}

struct ConversationOutboxStore {
    private let defaults: UserDefaults
    private let directoryURL: URL
    private let fileManager: FileManager
    private let availableCapacity: (URL) -> Int64?
    private let appointmentScopeID: UUID?
    private let keyPrefix = "couplespace.conversation-outbox.v1."

    init(
        defaults: UserDefaults = .standard,
        directoryURL: URL? = nil,
        fileManager: FileManager = .default,
        availableCapacity: ((URL) -> Int64?)? = nil,
        appointmentScopeID: UUID? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.appointmentScopeID = appointmentScopeID
        self.directoryURL = directoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first
                .map { $0.appendingPathComponent("ConversationOutbox", isDirectory: true) }
            ?? fileManager.temporaryDirectory
                .appendingPathComponent("ConversationOutbox", isDirectory: true)
        self.availableCapacity = availableCapacity
            ?? { PhotoOutboxCapacityPolicy.availableBytes(at: $0, fileManager: fileManager) }
    }

    func load(userID: UUID, relationshipID: UUID) throws -> ConversationOutboxQueue {
        guard let data = defaults.data(forKey: key(userID: userID, relationshipID: relationshipID)) else {
            return ConversationOutboxQueue()
        }
        let queue = try JSONDecoder().decode(ConversationOutboxQueue.self, from: data)
        for entry in queue.entries {
            if case let .photo(localFileName, _) = entry.content {
                _ = try validatedFileURL(
                    userID: entry.userID,
                    relationshipID: entry.relationshipID,
                    clientID: entry.clientID,
                    localFileName: localFileName
                )
            }
        }
        return queue
    }

    func enqueueText(
        _ body: String,
        userID: UUID,
        relationshipID: UUID,
        clientID: UUID,
        localCreatedAt: Date
    ) throws {
        var queue = try load(userID: userID, relationshipID: relationshipID)
        try queue.enqueue(ConversationOutboxEntry(
            userID: userID,
            relationshipID: relationshipID,
            clientID: clientID,
            content: .text(body),
            localCreatedAt: localCreatedAt,
            attemptCount: 0
        ))
        try save(queue, userID: userID, relationshipID: relationshipID)
    }

    func enqueuePhoto(
        _ data: Data,
        userID: UUID,
        relationshipID: UUID,
        clientID: UUID,
        localCreatedAt: Date
    ) throws {
        guard PhotoOutboxCapacityPolicy.permitsWrite(
            jpegByteCount: data.count,
            availableBytes: availableCapacity(
                scopedDirectoryURL(userID: userID, relationshipID: relationshipID)
            )
        ) else { throw ConversationOutboxError.insufficientCapacity }
        let scopedDirectoryURL = scopedDirectoryURL(
            userID: userID,
            relationshipID: relationshipID
        )
        try fileManager.createDirectory(at: scopedDirectoryURL, withIntermediateDirectories: true)
        let localFileName = fileName(clientID: clientID)
        let fileURL = try validatedFileURL(
            userID: userID,
            relationshipID: relationshipID,
            clientID: clientID,
            localFileName: localFileName
        )
        try data.write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        do {
            var queue = try load(userID: userID, relationshipID: relationshipID)
            try queue.enqueue(ConversationOutboxEntry(
                userID: userID,
                relationshipID: relationshipID,
                clientID: clientID,
                content: .photo(localFileName: localFileName, byteSize: data.count),
                localCreatedAt: localCreatedAt,
                attemptCount: 0
            ))
            try save(queue, userID: userID, relationshipID: relationshipID)
        } catch {
            try? fileManager.removeItem(at: fileURL)
            throw error
        }
    }

    func save(_ queue: ConversationOutboxQueue, userID: UUID, relationshipID: UUID) throws {
        let key = key(userID: userID, relationshipID: relationshipID)
        guard !queue.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(try JSONEncoder().encode(queue), forKey: key)
    }

    func data(for entry: ConversationOutboxEntry) throws -> Data {
        guard case let .photo(localFileName, _) = entry.content else {
            throw ConversationOutboxError.notAPhoto
        }
        let fileURL = try validatedFileURL(
            userID: entry.userID,
            relationshipID: entry.relationshipID,
            clientID: entry.clientID,
            localFileName: localFileName
        )
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw ConversationOutboxError.missingLocalFile
        }
        return try Data(contentsOf: fileURL)
    }

    func acknowledgeFirst(
        clientID: UUID,
        userID: UUID,
        relationshipID: UUID
    ) throws {
        var queue = try load(userID: userID, relationshipID: relationshipID)
        let acknowledged = try queue.acknowledgeFirst(clientID: clientID)
        try save(queue, userID: userID, relationshipID: relationshipID)
        if case let .photo(localFileName, _) = acknowledged.content {
            let fileURL = try validatedFileURL(
                userID: acknowledged.userID,
                relationshipID: acknowledged.relationshipID,
                clientID: acknowledged.clientID,
                localFileName: localFileName
            )
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    func clearAll(userID: UUID) {
        let userPrefix = keyPrefix + userID.uuidString.lowercased() + "."
        let matchingKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(userPrefix) }
        matchingKeys.forEach(defaults.removeObject(forKey:))
        try? fileManager.removeItem(
            at: directoryURL.appendingPathComponent(userID.uuidString.lowercased(), isDirectory: true)
        )
    }

    func clearAppointmentDiscussions(userID: UUID, relationshipID: UUID) {
        let discussionPrefix = baseKey(userID: userID, relationshipID: relationshipID)
            + ".appointment."
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(discussionPrefix) }
            .forEach(defaults.removeObject(forKey:))
        let relationshipDirectory = directoryURL
            .appendingPathComponent(userID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(relationshipID.uuidString.lowercased(), isDirectory: true)
        try? fileManager.removeItem(
            at: relationshipDirectory.appendingPathComponent("appointments", isDirectory: true)
        )
    }

    private func key(userID: UUID, relationshipID: UUID) -> String {
        let base = baseKey(userID: userID, relationshipID: relationshipID)
        guard let appointmentScopeID else { return base }
        return base + ".appointment." + appointmentScopeID.uuidString.lowercased()
    }

    private func baseKey(userID: UUID, relationshipID: UUID) -> String {
        keyPrefix + userID.uuidString.lowercased() + "." + relationshipID.uuidString.lowercased()
    }

    private func fileName(clientID: UUID) -> String {
        clientID.uuidString.lowercased() + ".jpg"
    }

    private func scopedDirectoryURL(userID: UUID, relationshipID: UUID) -> URL {
        let relationshipDirectory = directoryURL
            .appendingPathComponent(userID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(relationshipID.uuidString.lowercased(), isDirectory: true)
        guard let appointmentScopeID else { return relationshipDirectory }
        return relationshipDirectory
            .appendingPathComponent("appointments", isDirectory: true)
            .appendingPathComponent(appointmentScopeID.uuidString.lowercased(), isDirectory: true)
    }

    private func validatedFileURL(
        userID: UUID,
        relationshipID: UUID,
        clientID: UUID,
        localFileName: String
    ) throws -> URL {
        guard localFileName == fileName(clientID: clientID) else {
            throw ConversationOutboxError.invalidLocalFileName
        }
        return scopedDirectoryURL(userID: userID, relationshipID: relationshipID)
            .appendingPathComponent(localFileName, isDirectory: false)
    }
}

private enum ConversationCachedContent: Codable, Equatable {
    case text(String)
    case photo
}

private struct ConversationCachedReaction: Codable, Equatable {
    let id: UUID
    let reactorUserID: UUID
    let emojiValue: String
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, reactorUserID, emojiValue, emoji, updatedAt
    }

    init(_ reaction: ChatMessageReaction) {
        id = reaction.id
        reactorUserID = reaction.reactorUserID
        emojiValue = reaction.emojiValue
        updatedAt = reaction.updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        reactorUserID = try container.decode(UUID.self, forKey: .reactorUserID)
        if let value = try container.decodeIfPresent(String.self, forKey: .emojiValue) {
            emojiValue = value
        } else {
            emojiValue = try container.decode(MomentEmoji.self, forKey: .emoji).rawValue
        }
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(reactorUserID, forKey: .reactorUserID)
        try container.encode(emojiValue, forKey: .emojiValue)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var reaction: ChatMessageReaction {
        ChatMessageReaction(
            id: id,
            reactorUserID: reactorUserID,
            emojiValue: emojiValue,
            updatedAt: updatedAt
        )
    }
}

private struct ConversationCachedMessage: Codable, Equatable {
    let id: UUID
    let senderUserID: UUID
    let content: ConversationCachedContent
    let createdAt: Date
    let reaction: ConversationCachedReaction?

    init(_ message: ChatMessage) {
        id = message.id
        senderUserID = message.senderUserID
        switch message.content {
        case let .text(body): content = .text(body)
        case .photo: content = .photo
        }
        createdAt = message.createdAt
        reaction = message.reaction.map(ConversationCachedReaction.init)
    }

    private enum CodingKeys: String, CodingKey { case id, senderUserID, content, body, createdAt, reaction }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        senderUserID = try container.decode(UUID.self, forKey: .senderUserID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        reaction = try container.decodeIfPresent(ConversationCachedReaction.self, forKey: .reaction)
        if let decoded = try container.decodeIfPresent(ConversationCachedContent.self, forKey: .content) {
            content = decoded
        } else {
            content = .text(try container.decode(String.self, forKey: .body))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(senderUserID, forKey: .senderUserID)
        try container.encode(content, forKey: .content)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(reaction, forKey: .reaction)
    }

    var message: ChatMessage {
        let messageContent: ChatMessageContent
        switch content {
        case let .text(body): messageContent = .text(body)
        case .photo: messageContent = .photo
        }
        return ChatMessage(
            id: id,
            senderUserID: senderUserID,
            content: messageContent,
            createdAt: createdAt,
            reaction: reaction?.reaction
        )
    }
}

private struct ConversationCachedSnapshot: Codable, Equatable {
    let messages: [ConversationCachedMessage]
    let unreadCount: Int
}

struct ConversationSnapshotStore {
    private let defaults: UserDefaults
    private let appointmentScopeID: UUID?
    private let keyPrefix = "couplespace.conversation-snapshot.v1."

    init(defaults: UserDefaults = .standard, appointmentScopeID: UUID? = nil) {
        self.defaults = defaults
        self.appointmentScopeID = appointmentScopeID
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
        defaults.set(
            try JSONEncoder().encode(ConversationCachedSnapshot(
                messages: messages,
                unreadCount: snapshot.unreadCount
            )),
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
        let base = keyPrefix + userID.uuidString.lowercased() + "."
            + relationshipID.uuidString.lowercased()
        guard let appointmentScopeID else { return base }
        return base + ".appointment." + appointmentScopeID.uuidString.lowercased()
    }
}

struct ConversationPhotoCacheStore {
    private let directoryURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("ConversationPhotos", isDirectory: true)
            ?? fileManager.temporaryDirectory.appendingPathComponent("ConversationPhotos", isDirectory: true)
    }

    func load(userID: UUID, relationshipID: UUID, messageID: UUID) throws -> Data? {
        let url = fileURL(userID: userID, relationshipID: relationshipID, messageID: messageID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func save(_ data: Data, userID: UUID, relationshipID: UUID, messageID: UUID) throws {
        let url = fileURL(userID: userID, relationshipID: relationshipID, messageID: messageID)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func clearAll(userID: UUID) {
        try? fileManager.removeItem(at: directoryURL.appendingPathComponent(userID.uuidString.lowercased()))
    }

    private func fileURL(userID: UUID, relationshipID: UUID, messageID: UUID) -> URL {
        directoryURL
            .appendingPathComponent(userID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(relationshipID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(messageID.uuidString.lowercased() + ".jpg")
    }
}

enum ConversationOutboxError: Error, Equatable {
    case clientIDCollision
    case unexpectedAcknowledgement
    case invalidLocalFileName
    case missingLocalFile
    case insufficientCapacity
    case notAPhoto
}

enum ConversationRecoveryRetryPolicy {
    static let maximumAttempts = 3

    static func delayNanoseconds(afterAttempt attempt: Int) -> UInt64? {
        switch attempt {
        case 1: 1_000_000_000
        case 2: 4_000_000_000
        default: nil
        }
    }
}
