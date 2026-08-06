import Foundation

struct RelationshipSnapshot: Codable, Equatable {
    let relationshipID: UUID
    let status: String
    let memberCount: Int
}

struct RelationshipSnapshotStore {
    private let defaults: UserDefaults
    private let keyPrefix = "couplespace.w1.relationship-snapshot."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(userID: UUID) throws -> RelationshipSnapshot? {
        guard let data = defaults.data(forKey: key(userID)) else { return nil }
        return try JSONDecoder().decode(RelationshipSnapshot.self, from: data)
    }

    func save(_ snapshot: RelationshipSnapshot, userID: UUID) throws {
        defaults.set(try JSONEncoder().encode(snapshot), forKey: key(userID))
    }

    func clear(userID: UUID) {
        defaults.removeObject(forKey: key(userID))
    }

    private func key(_ userID: UUID) -> String {
        keyPrefix + userID.uuidString.lowercased()
    }
}

enum MessageDeliveryState: Equatable {
    case queued
    case sending(attempt: Int)
    case sent(serverCreatedAt: Date)
    case failed(attempt: Int)
}

enum MessageDeliveryEvent {
    case beginAttempt
    case serverAccepted(Date)
    case recoverableFailure
}

struct MessageDeliveryReducer {
    static func reduce(
        _ state: MessageDeliveryState,
        event: MessageDeliveryEvent
    ) -> MessageDeliveryState {
        switch (state, event) {
        case (.queued, .beginAttempt):
            return .sending(attempt: 1)
        case let (.failed(attempt), .beginAttempt):
            return .sending(attempt: attempt + 1)
        case let (.sending, .serverAccepted(date)):
            return .sent(serverCreatedAt: date)
        case let (.sending(attempt), .recoverableFailure):
            return .failed(attempt: attempt)
        default:
            return state
        }
    }
}

struct MessageIdentity {
    static func recordName(for id: UUID) -> String {
        "message_\(id.uuidString.lowercased())"
    }
}

enum TextMessagePolicy {
    static let maximumLength = 4_000

    static func normalized(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= maximumLength else { return nil }
        return normalized
    }
}

struct MessageOutboxEntry: Codable, Equatable {
    let relationshipID: UUID
    let clientID: UUID
    let body: String
    var attemptCount: Int
}

struct MessageOutboxQueue: Codable, Equatable {
    private(set) var entries: [MessageOutboxEntry] = []

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }
    var first: MessageOutboxEntry? { entries.first }

    mutating func enqueue(_ entry: MessageOutboxEntry) {
        entries.append(entry)
    }

    mutating func beginFirstAttempt() -> MessageOutboxEntry? {
        guard !entries.isEmpty else { return nil }
        entries[0].attemptCount += 1
        return entries[0]
    }

    mutating func acknowledgeFirst(clientID: UUID) -> Bool {
        guard entries.first?.clientID == clientID else { return false }
        entries.removeFirst()
        return true
    }
}

struct MessageOutboxStore {
    private let defaults: UserDefaults
    private let keyPrefix = "couplespace.w1.message-outbox."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(userID: UUID) throws -> MessageOutboxQueue {
        guard let data = defaults.data(forKey: key(userID)) else {
            return MessageOutboxQueue()
        }
        return try JSONDecoder().decode(MessageOutboxQueue.self, from: data)
    }

    func save(_ queue: MessageOutboxQueue, userID: UUID) throws {
        guard !queue.isEmpty else {
            defaults.removeObject(forKey: key(userID))
            return
        }
        defaults.set(try JSONEncoder().encode(queue), forKey: key(userID))
    }

    private func key(_ userID: UUID) -> String {
        keyPrefix + userID.uuidString.lowercased()
    }
}

struct MarkerOutboxEntry: Codable, Equatable {
    let relationshipID: UUID
    let clientID: UUID
    var attemptCount: Int
}

struct MarkerOutboxQueue: Codable, Equatable {
    private(set) var entries: [MarkerOutboxEntry] = []

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }
    var first: MarkerOutboxEntry? { entries.first }

    mutating func enqueue(_ entry: MarkerOutboxEntry) {
        entries.append(entry)
    }

    mutating func beginFirstAttempt() -> MarkerOutboxEntry? {
        guard !entries.isEmpty else { return nil }
        entries[0].attemptCount += 1
        return entries[0]
    }

    mutating func acknowledgeFirst(clientID: UUID) -> Bool {
        guard entries.first?.clientID == clientID else { return false }
        entries.removeFirst()
        return true
    }
}

struct MarkerOutboxStore {
    private let defaults: UserDefaults
    private let keyPrefix = "couplespace.w1.marker-outbox."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(userID: UUID) throws -> MarkerOutboxQueue {
        guard let data = defaults.data(forKey: key(userID)) else {
            return MarkerOutboxQueue()
        }

        do {
            return try JSONDecoder().decode(MarkerOutboxQueue.self, from: data)
        } catch let queueError {
            if let legacyEntry = try? JSONDecoder().decode(MarkerOutboxEntry.self, from: data) {
                return MarkerOutboxQueue(entries: [legacyEntry])
            }
            throw queueError
        }
    }

    func save(_ queue: MarkerOutboxQueue, userID: UUID) throws {
        guard !queue.isEmpty else {
            clear(userID: userID)
            return
        }
        defaults.set(try JSONEncoder().encode(queue), forKey: key(userID))
    }

    func clear(userID: UUID) {
        defaults.removeObject(forKey: key(userID))
    }

    private func key(_ userID: UUID) -> String {
        keyPrefix + userID.uuidString.lowercased()
    }
}

struct PhotoOutboxEntry: Codable, Equatable {
    let relationshipID: UUID
    let clientID: UUID
    var attemptCount: Int
    let localFileName: String
}

struct PhotoOutboxQueue: Codable, Equatable {
    private(set) var entries: [PhotoOutboxEntry] = []

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }
    var first: PhotoOutboxEntry? { entries.first }

    mutating func enqueue(_ entry: PhotoOutboxEntry) {
        entries.append(entry)
    }

    mutating func beginFirstAttempt() -> PhotoOutboxEntry? {
        guard !entries.isEmpty else { return nil }
        entries[0].attemptCount += 1
        return entries[0]
    }

    mutating func acknowledgeFirst(clientID: UUID) -> PhotoOutboxEntry? {
        guard entries.first?.clientID == clientID else { return nil }
        return entries.removeFirst()
    }
}

enum PhotoOutboxStoreError: LocalizedError, Equatable {
    case invalidLocalFileName
    case missingLocalFile

    var errorDescription: String? {
        switch self {
        case .invalidLocalFileName:
            "待送照片的本機檔名無效"
        case .missingLocalFile:
            "待送照片的本機檔案遺失"
        }
    }
}

struct PhotoOutboxStore {
    private let defaults: UserDefaults
    private let directoryURL: URL
    private let fileManager: FileManager
    private let keyPrefix = "couplespace.w1.photo-outbox."

    init(
        defaults: UserDefaults = .standard,
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.directoryURL = directoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first
                .map { $0.appendingPathComponent("W1PhotoOutbox", isDirectory: true) }
            ?? fileManager.temporaryDirectory
                .appendingPathComponent("W1PhotoOutbox", isDirectory: true)
    }

    func create(
        jpegData: Data,
        relationshipID: UUID,
        clientID: UUID,
        userID: UUID
    ) throws -> PhotoOutboxEntry {
        var queue = try load(userID: userID)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let entry = PhotoOutboxEntry(
            relationshipID: relationshipID,
            clientID: clientID,
            attemptCount: 0,
            localFileName: fileName(clientID: clientID)
        )
        let fileURL = try validatedFileURL(for: entry)
        try jpegData.write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )

        do {
            queue.enqueue(entry)
            try save(queue, userID: userID)
        } catch {
            try? fileManager.removeItem(at: fileURL)
            throw error
        }
        return entry
    }

    func load(userID: UUID) throws -> PhotoOutboxQueue {
        guard let data = defaults.data(forKey: key(userID)) else {
            return PhotoOutboxQueue()
        }

        let queue: PhotoOutboxQueue
        do {
            queue = try JSONDecoder().decode(PhotoOutboxQueue.self, from: data)
        } catch let queueError {
            guard let legacyEntry = try? JSONDecoder().decode(PhotoOutboxEntry.self, from: data) else {
                throw queueError
            }
            queue = PhotoOutboxQueue(entries: [legacyEntry])
        }
        for entry in queue.entries {
            _ = try validatedFileURL(for: entry)
        }
        return queue
    }

    func save(_ queue: PhotoOutboxQueue, userID: UUID) throws {
        guard !queue.isEmpty else {
            defaults.removeObject(forKey: key(userID))
            return
        }
        defaults.set(try JSONEncoder().encode(queue), forKey: key(userID))
    }

    func beginAttempt(userID: UUID) throws -> PhotoOutboxEntry? {
        var queue = try load(userID: userID)
        guard let entry = queue.beginFirstAttempt() else { return nil }
        try save(queue, userID: userID)
        return entry
    }

    func data(for entry: PhotoOutboxEntry) throws -> Data {
        let fileURL = try validatedFileURL(for: entry)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw PhotoOutboxStoreError.missingLocalFile
        }
        return try Data(contentsOf: fileURL)
    }

    func acknowledgeFirst(clientID: UUID, userID: UUID) throws -> Bool {
        var queue = try load(userID: userID)
        guard let acknowledgedEntry = queue.acknowledgeFirst(clientID: clientID) else {
            return false
        }
        let fileURL = try validatedFileURL(for: acknowledgedEntry)
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        try save(queue, userID: userID)
        return true
    }

    private func key(_ userID: UUID) -> String {
        keyPrefix + userID.uuidString.lowercased()
    }

    private func fileName(clientID: UUID) -> String {
        clientID.uuidString.lowercased() + ".jpg"
    }

    private func validatedFileURL(for entry: PhotoOutboxEntry) throws -> URL {
        guard entry.localFileName == fileName(clientID: entry.clientID) else {
            throw PhotoOutboxStoreError.invalidLocalFileName
        }
        return directoryURL.appendingPathComponent(entry.localFileName, isDirectory: false)
    }
}

struct PhotoOutboxLifecyclePolicy {
    static func canBeginUnpairing(
        hasPendingPhoto: Bool,
        isSendingPhoto: Bool
    ) -> Bool {
        !hasPendingPhoto && !isSendingPhoto
    }
}

struct PhotoDimensions: Equatable {
    let width: Int
    let height: Int
}

struct PhotoAssetPolicy {
    static let fullMaxDimension = 1_600
    static let thumbnailMaxDimension = 320
    static let jpegCompressionQuality = 0.8

    static func recordName(for id: UUID) -> String {
        "photo_\(id.uuidString.lowercased())"
    }

    static func scaledDimensions(
        width: Int,
        height: Int,
        maxDimension: Int
    ) -> PhotoDimensions {
        guard width > 0, height > 0, maxDimension > 0 else {
            return PhotoDimensions(width: 0, height: 0)
        }

        let largestDimension = max(width, height)
        guard largestDimension > maxDimension else {
            return PhotoDimensions(width: width, height: height)
        }

        let scale = Double(maxDimension) / Double(largestDimension)
        return PhotoDimensions(
            width: max(1, Int((Double(width) * scale).rounded())),
            height: max(1, Int((Double(height) * scale).rounded()))
        )
    }
}

enum RelationshipLifecyclePhase: Equatable {
    case active
    case closing
    case archived
}

struct RelationshipArchivePolicy {
    static func canWriteSharedContent(in phase: RelationshipLifecyclePhase) -> Bool {
        phase == .active
    }

    static func canFinalizeUnpairing(
        expectedParticipants: Set<UUID>,
        archivedParticipants: Set<UUID>
    ) -> Bool {
        expectedParticipants.count == 2 && archivedParticipants == expectedParticipants
    }

    static func canManagePersonalArchive(actorID: UUID, archiveOwnerID: UUID) -> Bool {
        actorID == archiveOwnerID
    }

    static func personalArchiveDeletionTargets(requestedBy participantID: UUID) -> Set<UUID> {
        [participantID]
    }
}

struct MessageOrderingValue: Equatable {
    let id: UUID
    let clientCreatedAt: Date
    let serverCreatedAt: Date?

    static func ordered(_ values: [Self]) -> [Self] {
        values.sorted { lhs, rhs in
            let lhsDate = lhs.serverCreatedAt ?? lhs.clientCreatedAt
            let rhsDate = rhs.serverCreatedAt ?? rhs.clientCreatedAt

            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

struct PrivateNotificationEnvelope: Equatable {
    let relationshipID: UUID
    let eventID: UUID
    let kind: String

    var userVisibleTitle: String { "CoupleSpace 有新動態" }
    var userVisibleBody: String { "打開 App 查看" }
}

struct PrivateNotificationPayload: Codable, Equatable {
    struct APS: Codable, Equatable {
        struct Alert: Codable, Equatable {
            let title: String
            let body: String
        }

        let alert: Alert
        let sound: String
    }

    let aps: APS
    let eventKind: String
    let eventID: UUID

    enum CodingKeys: String, CodingKey {
        case aps
        case eventKind = "event_kind"
        case eventID = "event_id"
    }

    init(envelope: PrivateNotificationEnvelope) {
        aps = APS(
            alert: APS.Alert(
                title: envelope.userVisibleTitle,
                body: envelope.userVisibleBody
            ),
            sound: "default"
        )
        eventKind = envelope.kind
        eventID = envelope.eventID
    }
}

struct InteractionContribution: Equatable {
    let relationshipID: UUID
    let interactionID: UUID
    let participantID: UUID
    let occurredAt: Date
}

struct MeaningfulInteractionRule {
    static func isSatisfied(
        by contributions: [InteractionContribution],
        expectedParticipants: Set<UUID>
    ) -> Bool {
        guard expectedParticipants.count == 2,
              let relationshipID = contributions.first?.relationshipID,
              let interactionID = contributions.first?.interactionID,
              contributions.allSatisfy({
                  $0.relationshipID == relationshipID &&
                  $0.interactionID == interactionID &&
                  expectedParticipants.contains($0.participantID)
              })
        else {
            return false
        }

        return Set(contributions.map(\.participantID)) == expectedParticipants
    }
}

enum SupabaseSessionDecision: Equatable {
    case signedOut
    case refreshingExpiredSession
    case signedIn
}

struct SupabaseSessionPolicy {
    static func decision(hasSession: Bool, isExpired: Bool) -> SupabaseSessionDecision {
        guard hasSession else { return .signedOut }
        return isExpired ? .refreshingExpiredSession : .signedIn
    }
}
