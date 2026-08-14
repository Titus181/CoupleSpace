import Foundation

struct SharedAppointmentOutboxEntry: Codable, Equatable, Sendable {
    let userID: UUID
    let relationshipID: UUID
    let clientID: UUID
    let draft: SharedAppointmentDraft
    let localCreatedAt: Date
    var attemptCount: Int

    var appointment: SharedAppointment {
        SharedAppointment(
            id: clientID,
            creatorUserID: userID,
            title: draft.title,
            startsAt: draft.startsAt,
            location: draft.location,
            note: draft.note,
            reminderAt: draft.reminderAt,
            status: .scheduled,
            sourceMessageID: draft.sourceMessageID,
            createdAt: localCreatedAt,
            updatedAt: localCreatedAt,
            deliveryState: attemptCount > 0 ? .failed : .sending
        )
    }
}

struct SharedAppointmentOutboxQueue: Codable, Equatable, Sendable {
    private(set) var entries: [SharedAppointmentOutboxEntry] = []

    var isEmpty: Bool { entries.isEmpty }

    var appointments: [SharedAppointment] {
        let failed = (entries.first?.attemptCount ?? 0) > 0
        return entries.map { entry in
            var appointment = entry.appointment
            appointment.deliveryState = failed ? .failed : .sending
            return appointment
        }
    }

    mutating func enqueue(_ entry: SharedAppointmentOutboxEntry) throws {
        if let existing = entries.first(where: { $0.clientID == entry.clientID }) {
            guard existing == entry else {
                throw SharedAppointmentOutboxError.clientIDCollision
            }
            return
        }
        entries.append(entry)
    }

    mutating func beginFirstAttempt() -> SharedAppointmentOutboxEntry? {
        guard !entries.isEmpty else { return nil }
        entries[0].attemptCount += 1
        return entries[0]
    }

    mutating func acknowledgeFirst(clientID: UUID) throws {
        guard entries.first?.clientID == clientID else {
            throw SharedAppointmentOutboxError.unexpectedAcknowledgement
        }
        entries.removeFirst()
    }
}

struct SharedAppointmentOutboxStore {
    private let defaults: UserDefaults
    private let keyPrefix = "couplespace.shared-appointment-outbox.v1."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(userID: UUID, relationshipID: UUID) throws -> SharedAppointmentOutboxQueue {
        guard let data = defaults.data(forKey: key(userID: userID, relationshipID: relationshipID)) else {
            return SharedAppointmentOutboxQueue()
        }
        return try JSONDecoder().decode(SharedAppointmentOutboxQueue.self, from: data)
    }

    func enqueue(
        _ draft: SharedAppointmentDraft,
        userID: UUID,
        relationshipID: UUID,
        clientID: UUID,
        localCreatedAt: Date
    ) throws {
        var queue = try load(userID: userID, relationshipID: relationshipID)
        try queue.enqueue(SharedAppointmentOutboxEntry(
            userID: userID,
            relationshipID: relationshipID,
            clientID: clientID,
            draft: draft,
            localCreatedAt: localCreatedAt,
            attemptCount: 0
        ))
        try save(queue, userID: userID, relationshipID: relationshipID)
    }

    func beginFirstAttempt(
        userID: UUID,
        relationshipID: UUID
    ) throws -> SharedAppointmentOutboxEntry? {
        var queue = try load(userID: userID, relationshipID: relationshipID)
        guard let entry = queue.beginFirstAttempt() else { return nil }
        try save(queue, userID: userID, relationshipID: relationshipID)
        return entry
    }

    func acknowledgeFirst(
        clientID: UUID,
        userID: UUID,
        relationshipID: UUID
    ) throws {
        var queue = try load(userID: userID, relationshipID: relationshipID)
        try queue.acknowledgeFirst(clientID: clientID)
        try save(queue, userID: userID, relationshipID: relationshipID)
    }

    func clear(userID: UUID, relationshipID: UUID) {
        defaults.removeObject(forKey: key(userID: userID, relationshipID: relationshipID))
    }

    private func save(
        _ queue: SharedAppointmentOutboxQueue,
        userID: UUID,
        relationshipID: UUID
    ) throws {
        let key = key(userID: userID, relationshipID: relationshipID)
        guard !queue.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(try JSONEncoder().encode(queue), forKey: key)
    }

    private func key(userID: UUID, relationshipID: UUID) -> String {
        keyPrefix + userID.uuidString.lowercased() + "." + relationshipID.uuidString.lowercased()
    }
}

enum SharedAppointmentOutboxError: Error {
    case clientIDCollision
    case unexpectedAcknowledgement
}
