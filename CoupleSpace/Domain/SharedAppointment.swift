import Foundation

enum SharedAppointmentStatus: String, Codable, Sendable {
    case scheduled
    case cancelled
}

enum SharedAppointmentDeliveryState: Equatable, Sendable {
    case sending
    case synced
    case failed
}

struct SharedAppointment: Identifiable, Equatable, Sendable {
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
    var deliveryState: SharedAppointmentDeliveryState = .synced

    init(
        id: UUID,
        creatorUserID: UUID,
        title: String,
        startsAt: Date,
        location: String?,
        note: String?,
        reminderAt: Date?,
        status: SharedAppointmentStatus,
        sourceMessageID: UUID?,
        interactionBoundarySourceIdentity: UUID? = nil,
        createdAt: Date,
        updatedAt: Date,
        deliveryState: SharedAppointmentDeliveryState = .synced
    ) {
        self.id = id
        self.creatorUserID = creatorUserID
        self.title = title
        self.startsAt = startsAt
        self.location = location
        self.note = note
        self.reminderAt = reminderAt
        self.status = status
        self.sourceMessageID = sourceMessageID
        self.interactionBoundarySourceIdentity = interactionBoundarySourceIdentity
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deliveryState = deliveryState
    }
}

struct SharedAppointmentDiscussionSummary: Identifiable, Equatable, Sendable {
    let appointmentID: UUID
    let latestActivityAt: Date
    let unreadCount: Int

    var id: UUID { appointmentID }
}

enum SharedAppointmentEventKind: String, Sendable {
    case rescheduled
    case cancelled
}

struct SharedAppointmentEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let appointmentID: UUID
    let actorUserID: UUID
    let kind: SharedAppointmentEventKind
    let previousStartsAt: Date?
    let startsAt: Date?
    let createdAt: Date
}

struct SharedAppointmentDraft: Codable, Equatable, Sendable {
    let title: String
    let startsAt: Date
    let location: String?
    let note: String?
    let reminderAt: Date?
    let sourceMessageID: UUID?
}

enum SharedAppointmentPolicy {
    static let maximumTitleLength = 200
    static let maximumLocationLength = 200
    static let maximumNoteLength = 1_000

    static func normalizedDraft(_ draft: SharedAppointmentDraft) -> SharedAppointmentDraft? {
        guard let title = normalizedRequired(draft.title, maximum: maximumTitleLength) else {
            return nil
        }
        let location = normalizedOptional(draft.location, maximum: maximumLocationLength)
        let note = normalizedOptional(draft.note, maximum: maximumNoteLength)
        if draft.location?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
           location == nil {
            return nil
        }
        if draft.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
           note == nil {
            return nil
        }
        guard draft.reminderAt == nil || draft.reminderAt! <= draft.startsAt else {
            return nil
        }
        return SharedAppointmentDraft(
            title: title,
            startsAt: draft.startsAt,
            location: location,
            note: note,
            reminderAt: draft.reminderAt,
            sourceMessageID: draft.sourceMessageID
        )
    }

    private static func normalizedRequired(_ value: String, maximum: Int) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= maximum else { return nil }
        return normalized
    }

    private static func normalizedOptional(_ value: String?, maximum: Int) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard normalized.count <= maximum else { return nil }
        return normalized
    }
}
