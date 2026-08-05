import Foundation

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
