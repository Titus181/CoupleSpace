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

enum SharedAppointmentOperation: Codable, Equatable, Sendable {
    case update(SharedAppointmentDraft)
    case cancel
}

struct SharedAppointmentOperationOutboxEntry: Codable, Equatable, Sendable {
    let userID: UUID
    let relationshipID: UUID
    let operationID: UUID
    let appointmentID: UUID
    let operation: SharedAppointmentOperation
    let localCreatedAt: Date
    var attemptCount: Int

    func applying(to appointment: SharedAppointment) -> SharedAppointment {
        guard appointment.id == appointmentID else { return appointment }
        switch operation {
        case let .update(draft):
            return SharedAppointment(
                id: appointment.id,
                creatorUserID: appointment.creatorUserID,
                title: draft.title,
                startsAt: draft.startsAt,
                location: draft.location,
                note: draft.note,
                reminderAt: draft.reminderAt,
                status: appointment.status,
                sourceMessageID: appointment.sourceMessageID,
                createdAt: appointment.createdAt,
                updatedAt: appointment.updatedAt,
                deliveryState: appointment.deliveryState
            )
        case .cancel:
            return SharedAppointment(
                id: appointment.id,
                creatorUserID: appointment.creatorUserID,
                title: appointment.title,
                startsAt: appointment.startsAt,
                location: appointment.location,
                note: appointment.note,
                reminderAt: appointment.reminderAt,
                status: .cancelled,
                sourceMessageID: appointment.sourceMessageID,
                createdAt: appointment.createdAt,
                updatedAt: appointment.updatedAt,
                deliveryState: appointment.deliveryState
            )
        }
    }
}

struct SharedAppointmentOperationOutboxQueue: Codable, Equatable, Sendable {
    private(set) var entries: [SharedAppointmentOperationOutboxEntry] = []

    var isEmpty: Bool { entries.isEmpty }

    mutating func enqueue(_ entry: SharedAppointmentOperationOutboxEntry) throws {
        if let existing = entries.first(where: { $0.operationID == entry.operationID }) {
            guard existing == entry else {
                throw SharedAppointmentOperationOutboxError.operationIDCollision
            }
            return
        }
        if case .update = entry.operation,
           entries.contains(where: {
               $0.appointmentID == entry.appointmentID && $0.operation == .cancel
           }) {
            throw SharedAppointmentOperationOutboxError.appointmentAlreadyPendingCancellation
        }
        entries.append(entry)
    }

    mutating func beginFirstAttempt() -> SharedAppointmentOperationOutboxEntry? {
        guard !entries.isEmpty else { return nil }
        entries[0].attemptCount += 1
        return entries[0]
    }

    mutating func acknowledgeFirst(operationID: UUID) throws {
        guard entries.first?.operationID == operationID else {
            throw SharedAppointmentOperationOutboxError.unexpectedAcknowledgement
        }
        entries.removeFirst()
    }
}

struct SharedAppointmentOperationOutboxStore {
    private let defaults: UserDefaults
    private let keyPrefix = "couplespace.shared-appointment-operation-outbox.v1."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(
        userID: UUID,
        relationshipID: UUID
    ) throws -> SharedAppointmentOperationOutboxQueue {
        guard let data = defaults.data(forKey: key(userID: userID, relationshipID: relationshipID)) else {
            return SharedAppointmentOperationOutboxQueue()
        }
        return try JSONDecoder().decode(SharedAppointmentOperationOutboxQueue.self, from: data)
    }

    func enqueue(
        appointmentID: UUID,
        operationID: UUID,
        operation: SharedAppointmentOperation,
        userID: UUID,
        relationshipID: UUID,
        localCreatedAt: Date
    ) throws {
        var queue = try load(userID: userID, relationshipID: relationshipID)
        try queue.enqueue(SharedAppointmentOperationOutboxEntry(
            userID: userID,
            relationshipID: relationshipID,
            operationID: operationID,
            appointmentID: appointmentID,
            operation: operation,
            localCreatedAt: localCreatedAt,
            attemptCount: 0
        ))
        try save(queue, userID: userID, relationshipID: relationshipID)
    }

    func beginFirstAttempt(
        userID: UUID,
        relationshipID: UUID
    ) throws -> SharedAppointmentOperationOutboxEntry? {
        var queue = try load(userID: userID, relationshipID: relationshipID)
        guard let entry = queue.beginFirstAttempt() else { return nil }
        try save(queue, userID: userID, relationshipID: relationshipID)
        return entry
    }

    func acknowledgeFirst(
        operationID: UUID,
        userID: UUID,
        relationshipID: UUID
    ) throws {
        var queue = try load(userID: userID, relationshipID: relationshipID)
        try queue.acknowledgeFirst(operationID: operationID)
        try save(queue, userID: userID, relationshipID: relationshipID)
    }

    func clear(userID: UUID, relationshipID: UUID) {
        defaults.removeObject(forKey: key(userID: userID, relationshipID: relationshipID))
    }

    private func save(
        _ queue: SharedAppointmentOperationOutboxQueue,
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

enum SharedAppointmentOperationOutboxError: Error {
    case operationIDCollision
    case appointmentAlreadyPendingCancellation
    case unexpectedAcknowledgement
}
