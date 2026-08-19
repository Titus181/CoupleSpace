import Foundation

enum SharedAppointmentLocalSnapshotPolicy {
    static let maximumAppointmentCount = 200
}

private struct SharedAppointmentCachedItem: Codable {
    let id: UUID
    let creatorUserID: UUID
    let title: String
    let startsAt: Date
    let location: String?
    let note: String?
    let reminderAt: Date?
    let status: SharedAppointmentStatus
    let sourceMessageID: UUID?
    let interactionBoundarySourceIdentity: UUID?
    let createdAt: Date
    let updatedAt: Date

    init(_ appointment: SharedAppointment) {
        id = appointment.id
        creatorUserID = appointment.creatorUserID
        title = appointment.title
        startsAt = appointment.startsAt
        location = appointment.location
        note = appointment.note
        reminderAt = appointment.reminderAt
        status = appointment.status
        sourceMessageID = appointment.sourceMessageID
        interactionBoundarySourceIdentity = appointment.interactionBoundarySourceIdentity
        createdAt = appointment.createdAt
        updatedAt = appointment.updatedAt
    }

    var appointment: SharedAppointment {
        SharedAppointment(
            id: id,
            creatorUserID: creatorUserID,
            title: title,
            startsAt: startsAt,
            location: location,
            note: note,
            reminderAt: reminderAt,
            status: status,
            sourceMessageID: sourceMessageID,
            interactionBoundarySourceIdentity: interactionBoundarySourceIdentity,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct SharedAppointmentSnapshotStore {
    private let defaults: UserDefaults
    private let keyPrefix = "couplespace.shared-appointment-snapshot.v1."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(userID: UUID, relationshipID: UUID) throws -> [SharedAppointment]? {
        guard let data = defaults.data(forKey: key(userID: userID, relationshipID: relationshipID)) else {
            return nil
        }
        return try JSONDecoder().decode([SharedAppointmentCachedItem].self, from: data)
            .map(\.appointment)
    }

    func save(
        _ appointments: [SharedAppointment],
        userID: UUID,
        relationshipID: UUID
    ) throws {
        let cached = appointments
            .filter { $0.deliveryState == .synced }
            .sorted { ($0.startsAt, $0.id.uuidString) < ($1.startsAt, $1.id.uuidString) }
            .suffix(SharedAppointmentLocalSnapshotPolicy.maximumAppointmentCount)
            .map(SharedAppointmentCachedItem.init)
        defaults.set(
            try JSONEncoder().encode(cached),
            forKey: key(userID: userID, relationshipID: relationshipID)
        )
    }

    func upsert(
        _ appointment: SharedAppointment,
        userID: UUID,
        relationshipID: UUID
    ) throws {
        var appointments = try load(userID: userID, relationshipID: relationshipID) ?? []
        appointments.removeAll { $0.id == appointment.id }
        appointments.append(appointment)
        try save(appointments, userID: userID, relationshipID: relationshipID)
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
