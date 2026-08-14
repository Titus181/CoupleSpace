import Foundation
import Supabase

enum SharedAppointmentOperationDeliveryResult: Equatable, Sendable {
    case accepted(SharedAppointment)
    case rejected(SharedAppointment?, String)
}

@MainActor
protocol SharedAppointmentRemoteServing: AnyObject {
    func fetchPendingAppointments() async throws -> [SharedAppointment]
    func fetchAppointments() async throws -> [SharedAppointment]
    func fetchAppointmentEvents() async throws -> [SharedAppointmentEvent]
    func fetchRecentDiscussionSummaries() async throws -> [SharedAppointmentDiscussionSummary]
    func enqueueAppointment(
        _ draft: SharedAppointmentDraft,
        clientID: UUID,
        localCreatedAt: Date
    ) async throws
    func beginNextPendingAppointment() async throws -> SharedAppointmentOutboxEntry?
    func deliverPendingAppointment(
        _ entry: SharedAppointmentOutboxEntry
    ) async throws -> SharedAppointment
    func acknowledgePendingAppointment(clientID: UUID) async throws
    func fetchPendingAppointmentOperations() async throws -> [SharedAppointmentOperationOutboxEntry]
    func enqueueAppointmentOperation(
        appointmentID: UUID,
        operationID: UUID,
        operation: SharedAppointmentOperation,
        localCreatedAt: Date
    ) async throws
    func beginNextPendingAppointmentOperation() async throws -> SharedAppointmentOperationOutboxEntry?
    func deliverPendingAppointmentOperation(
        _ entry: SharedAppointmentOperationOutboxEntry
    ) async throws -> SharedAppointmentOperationDeliveryResult
    func acknowledgePendingAppointmentOperation(operationID: UUID) async throws
    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws
    func stopObservingChanges() async
}

private struct SharedAppointmentRow: Decodable {
    let clientID: UUID
    let creatorUserID: UUID
    let title: String
    let startsAt: Date
    let location: String?
    let note: String?
    let reminderAt: Date?
    let status: String
    let sourceSharedItemClientID: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case creatorUserID = "creator_user_id"
        case title
        case startsAt = "starts_at"
        case location, note
        case reminderAt = "reminder_at"
        case status
        case sourceSharedItemClientID = "source_shared_item_client_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func appointment() throws -> SharedAppointment {
        guard let status = SharedAppointmentStatus(rawValue: status) else {
            throw SharedAppointmentServiceError.invalidServerState
        }
        return SharedAppointment(
            id: clientID,
            creatorUserID: creatorUserID,
            title: title,
            startsAt: startsAt,
            location: location,
            note: note,
            reminderAt: reminderAt,
            status: status,
            sourceMessageID: sourceSharedItemClientID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private struct CreateSharedAppointmentParameters: Encodable {
    let targetRelationshipID: UUID
    let targetClientID: UUID
    let targetTitle: String
    let targetStartsAt: Date
    let targetLocation: String?
    let targetNote: String?
    let targetReminderAt: Date?
    let targetSourceSharedItemClientID: UUID?

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetClientID = "target_client_id"
        case targetTitle = "target_title"
        case targetStartsAt = "target_starts_at"
        case targetLocation = "target_location"
        case targetNote = "target_note"
        case targetReminderAt = "target_reminder_at"
        case targetSourceSharedItemClientID = "target_source_shared_item_client_id"
    }
}

private struct UpdateSharedAppointmentParameters: Encodable {
    let targetRelationshipID: UUID
    let targetAppointmentClientID: UUID
    let targetOperationID: UUID
    let targetTitle: String
    let targetStartsAt: Date
    let targetLocation: String?
    let targetNote: String?
    let targetReminderAt: Date?

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetAppointmentClientID = "target_appointment_client_id"
        case targetOperationID = "target_operation_id"
        case targetTitle = "target_title"
        case targetStartsAt = "target_starts_at"
        case targetLocation = "target_location"
        case targetNote = "target_note"
        case targetReminderAt = "target_reminder_at"
    }
}

private struct CancelSharedAppointmentParameters: Encodable {
    let targetRelationshipID: UUID
    let targetAppointmentClientID: UUID
    let targetOperationID: UUID

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetAppointmentClientID = "target_appointment_client_id"
        case targetOperationID = "target_operation_id"
    }
}

private struct RecentAppointmentDiscussionsParameters: Encodable {
    let targetRelationshipID: UUID

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
    }
}

private struct SharedAppointmentDiscussionSummaryRow: Decodable {
    let appointmentClientID: UUID
    let latestActivityAt: Date
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case appointmentClientID = "appointment_client_id"
        case latestActivityAt = "latest_activity_at"
        case unreadCount = "unread_count"
    }

    var summary: SharedAppointmentDiscussionSummary {
        SharedAppointmentDiscussionSummary(
            appointmentID: appointmentClientID,
            latestActivityAt: latestActivityAt,
            unreadCount: unreadCount
        )
    }
}

private struct SharedAppointmentEventRow: Decodable {
    let operationID: UUID
    let appointmentClientID: UUID
    let actorUserID: UUID
    let eventKind: String
    let previousStartsAt: Date?
    let startsAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case operationID = "operation_id"
        case appointmentClientID = "appointment_client_id"
        case actorUserID = "actor_user_id"
        case eventKind = "event_kind"
        case previousStartsAt = "previous_starts_at"
        case startsAt = "starts_at"
        case createdAt = "created_at"
    }

    func event() throws -> SharedAppointmentEvent {
        guard let kind = SharedAppointmentEventKind(rawValue: eventKind) else {
            throw SharedAppointmentServiceError.invalidServerState
        }
        switch kind {
        case .rescheduled:
            guard let previousStartsAt, let startsAt, previousStartsAt != startsAt else {
                throw SharedAppointmentServiceError.invalidServerState
            }
        case .cancelled:
            guard previousStartsAt == nil, startsAt == nil else {
                throw SharedAppointmentServiceError.invalidServerState
            }
        }
        return SharedAppointmentEvent(
            id: operationID,
            appointmentID: appointmentClientID,
            actorUserID: actorUserID,
            kind: kind,
            previousStartsAt: previousStartsAt,
            startsAt: startsAt,
            createdAt: createdAt
        )
    }
}

@MainActor
final class SupabaseSharedAppointmentService: SharedAppointmentRemoteServing {
    private let client: SupabaseClient
    private let currentUserID: UUID
    private let relationshipID: UUID
    private let outboxStore: SharedAppointmentOutboxStore
    private let operationOutboxStore: SharedAppointmentOperationOutboxStore
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTasks: [Task<Void, Never>] = []

    init(
        client: SupabaseClient,
        currentUserID: UUID,
        relationshipID: UUID,
        outboxStore: SharedAppointmentOutboxStore,
        operationOutboxStore: SharedAppointmentOperationOutboxStore = .init()
    ) {
        self.client = client
        self.currentUserID = currentUserID
        self.relationshipID = relationshipID
        self.outboxStore = outboxStore
        self.operationOutboxStore = operationOutboxStore
    }

    convenience init(
        client: SupabaseClient,
        currentUserID: UUID,
        relationshipID: UUID
    ) {
        self.init(
            client: client,
            currentUserID: currentUserID,
            relationshipID: relationshipID,
            outboxStore: SharedAppointmentOutboxStore()
        )
    }

    func fetchPendingAppointments() async throws -> [SharedAppointment] {
        try outboxStore.load(
            userID: currentUserID,
            relationshipID: relationshipID
        ).appointments
    }

    func fetchAppointments() async throws -> [SharedAppointment] {
        let session = try await client.auth.session
        guard session.user.id == currentUserID else {
            throw SharedAppointmentServiceError.accountChanged
        }
        let rows: [SharedAppointmentRow] = try await client
            .from("shared_appointments")
            .select("client_id,creator_user_id,title,starts_at,location,note,reminder_at,status,source_shared_item_client_id,created_at,updated_at")
            .eq("relationship_id", value: relationshipID)
            .order("starts_at", ascending: true)
            .execute()
            .value
        return try rows.map { try $0.appointment() }
    }

    func fetchAppointmentEvents() async throws -> [SharedAppointmentEvent] {
        let session = try await client.auth.session
        guard session.user.id == currentUserID else {
            throw SharedAppointmentServiceError.accountChanged
        }
        let rows: [SharedAppointmentEventRow] = try await client
            .from("shared_appointment_events")
            .select("operation_id,appointment_client_id,actor_user_id,event_kind,previous_starts_at,starts_at,created_at")
            .eq("relationship_id", value: relationshipID)
            .order("created_at", ascending: true)
            .order("operation_id", ascending: true)
            .execute()
            .value
        return try rows.map { try $0.event() }
    }

    func fetchRecentDiscussionSummaries() async throws -> [SharedAppointmentDiscussionSummary] {
        let session = try await client.auth.session
        guard session.user.id == currentUserID else {
            throw SharedAppointmentServiceError.accountChanged
        }
        let rows: [SharedAppointmentDiscussionSummaryRow] = try await client.rpc(
            "recent_appointment_discussions",
            params: RecentAppointmentDiscussionsParameters(
                targetRelationshipID: relationshipID
            )
        ).execute().value
        return rows.map(\.summary)
    }

    func enqueueAppointment(
        _ draft: SharedAppointmentDraft,
        clientID: UUID,
        localCreatedAt: Date
    ) async throws {
        guard let normalized = SharedAppointmentPolicy.normalizedDraft(draft) else {
            throw SharedAppointmentServiceError.invalidDraft
        }
        try outboxStore.enqueue(
            normalized,
            userID: currentUserID,
            relationshipID: relationshipID,
            clientID: clientID,
            localCreatedAt: localCreatedAt
        )
    }

    func beginNextPendingAppointment() async throws -> SharedAppointmentOutboxEntry? {
        try outboxStore.beginFirstAttempt(
            userID: currentUserID,
            relationshipID: relationshipID
        )
    }

    func deliverPendingAppointment(
        _ entry: SharedAppointmentOutboxEntry
    ) async throws -> SharedAppointment {
        guard entry.userID == currentUserID,
              entry.relationshipID == relationshipID else {
            throw SharedAppointmentServiceError.invalidOutboxIdentity
        }
        let session = try await client.auth.session
        guard session.user.id == currentUserID else {
            throw SharedAppointmentServiceError.accountChanged
        }
        guard let normalized = SharedAppointmentPolicy.normalizedDraft(entry.draft) else {
            throw SharedAppointmentServiceError.invalidDraft
        }
        let rows: [SharedAppointmentRow] = try await client.rpc(
            "create_shared_appointment",
            params: CreateSharedAppointmentParameters(
                targetRelationshipID: relationshipID,
                targetClientID: entry.clientID,
                targetTitle: normalized.title,
                targetStartsAt: normalized.startsAt,
                targetLocation: normalized.location,
                targetNote: normalized.note,
                targetReminderAt: normalized.reminderAt,
                targetSourceSharedItemClientID: normalized.sourceMessageID
            )
        ).execute().value
        guard let row = rows.first else {
            throw SharedAppointmentServiceError.missingSavedAppointment
        }
        return try row.appointment()
    }

    func acknowledgePendingAppointment(clientID: UUID) async throws {
        try outboxStore.acknowledgeFirst(
            clientID: clientID,
            userID: currentUserID,
            relationshipID: relationshipID
        )
    }

    func fetchPendingAppointmentOperations() async throws -> [SharedAppointmentOperationOutboxEntry] {
        try operationOutboxStore.load(
            userID: currentUserID,
            relationshipID: relationshipID
        ).entries
    }

    func enqueueAppointmentOperation(
        appointmentID: UUID,
        operationID: UUID,
        operation: SharedAppointmentOperation,
        localCreatedAt: Date
    ) async throws {
        if case let .update(draft) = operation,
           SharedAppointmentPolicy.normalizedDraft(draft) == nil {
            throw SharedAppointmentServiceError.invalidDraft
        }
        try operationOutboxStore.enqueue(
            appointmentID: appointmentID,
            operationID: operationID,
            operation: operation,
            userID: currentUserID,
            relationshipID: relationshipID,
            localCreatedAt: localCreatedAt
        )
    }

    func beginNextPendingAppointmentOperation() async throws -> SharedAppointmentOperationOutboxEntry? {
        try operationOutboxStore.beginFirstAttempt(
            userID: currentUserID,
            relationshipID: relationshipID
        )
    }

    func deliverPendingAppointmentOperation(
        _ entry: SharedAppointmentOperationOutboxEntry
    ) async throws -> SharedAppointmentOperationDeliveryResult {
        guard entry.userID == currentUserID,
              entry.relationshipID == relationshipID else {
            throw SharedAppointmentServiceError.invalidOutboxIdentity
        }
        do {
            let appointment: SharedAppointment
            switch entry.operation {
            case let .update(draft):
                appointment = try await performUpdateAppointment(
                    id: entry.appointmentID,
                    operationID: entry.operationID,
                    draft: draft
                )
            case .cancel:
                appointment = try await performCancelAppointment(
                    id: entry.appointmentID,
                    operationID: entry.operationID
                )
            }
            return .accepted(appointment)
        } catch let error as PostgrestError where Self.isTerminalOperationError(error.message) {
            let remoteAppointment = try? await fetchAppointment(id: entry.appointmentID)
            return .rejected(
                remoteAppointment,
                Self.terminalOperationMessage(serverMessage: error.message)
            )
        }
    }

    func acknowledgePendingAppointmentOperation(operationID: UUID) async throws {
        try operationOutboxStore.acknowledgeFirst(
            operationID: operationID,
            userID: currentUserID,
            relationshipID: relationshipID
        )
    }

    private func performUpdateAppointment(
        id: UUID,
        operationID: UUID,
        draft: SharedAppointmentDraft
    ) async throws -> SharedAppointment {
        let session = try await client.auth.session
        guard session.user.id == currentUserID else {
            throw SharedAppointmentServiceError.accountChanged
        }
        guard let normalized = SharedAppointmentPolicy.normalizedDraft(draft) else {
            throw SharedAppointmentServiceError.invalidDraft
        }
        let rows: [SharedAppointmentRow] = try await client.rpc(
            "update_shared_appointment",
            params: UpdateSharedAppointmentParameters(
                targetRelationshipID: relationshipID,
                targetAppointmentClientID: id,
                targetOperationID: operationID,
                targetTitle: normalized.title,
                targetStartsAt: normalized.startsAt,
                targetLocation: normalized.location,
                targetNote: normalized.note,
                targetReminderAt: normalized.reminderAt
            )
        ).execute().value
        guard let row = rows.first else {
            throw SharedAppointmentServiceError.missingSavedAppointment
        }
        return try row.appointment()
    }

    private func performCancelAppointment(
        id: UUID,
        operationID: UUID
    ) async throws -> SharedAppointment {
        let session = try await client.auth.session
        guard session.user.id == currentUserID else {
            throw SharedAppointmentServiceError.accountChanged
        }
        let rows: [SharedAppointmentRow] = try await client.rpc(
            "cancel_shared_appointment",
            params: CancelSharedAppointmentParameters(
                targetRelationshipID: relationshipID,
                targetAppointmentClientID: id,
                targetOperationID: operationID
            )
        ).execute().value
        guard let row = rows.first else {
            throw SharedAppointmentServiceError.missingSavedAppointment
        }
        return try row.appointment()
    }

    private func fetchAppointment(id: UUID) async throws -> SharedAppointment? {
        let rows: [SharedAppointmentRow] = try await client
            .from("shared_appointments")
            .select("client_id,creator_user_id,title,starts_at,location,note,reminder_at,status,source_shared_item_client_id,created_at,updated_at")
            .eq("relationship_id", value: relationshipID)
            .eq("client_id", value: id)
            .limit(1)
            .execute()
            .value
        return try rows.first.map { try $0.appointment() }
    }

    static func isTerminalOperationError(_ message: String) -> Bool {
        [
            "appointment_cancelled",
            "appointment_not_found",
            "relationship_not_active",
            "relationship_not_accessible",
            "appointment_operation_identity_collision",
        ].contains(message)
    }

    private static func terminalOperationMessage(serverMessage: String) -> String {
        switch serverMessage {
        case "appointment_cancelled":
            "這筆約定已取消，未再套用待送編輯。"
        case "appointment_not_found":
            "這筆約定已不存在，已停止待送操作。"
        case "relationship_not_active":
            "伴侶關係已停止共同寫入，未再套用待送操作。"
        case "relationship_not_accessible":
            "這段伴侶關係已結束，已停止並清除待送操作。"
        default:
            "這筆待送操作已失效，未再次改寫共同約定。"
        }
    }

    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws {
        await stopObservingChanges()
        let channel = client.channel("shared-appointments-\(UUID().uuidString.lowercased())")
        let stream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "shared_appointments",
            filter: .eq("relationship_id", value: relationshipID.uuidString.lowercased())
        )
        let discussionStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "shared_items",
            filter: .eq("relationship_id", value: relationshipID.uuidString.lowercased())
        )
        realtimeChannel = channel
        realtimeTasks = [Task {
            for await _ in stream {
                guard !Task.isCancelled else { return }
                await onChange()
            }
        }, Task {
            for await _ in discussionStream {
                guard !Task.isCancelled else { return }
                await onChange()
            }
        }]
        do {
            try await channel.subscribeWithError()
        } catch {
            realtimeTasks.forEach { $0.cancel() }
            realtimeTasks = []
            realtimeChannel = nil
            await client.removeChannel(channel)
            throw error
        }
    }

    func stopObservingChanges() async {
        realtimeTasks.forEach { $0.cancel() }
        realtimeTasks = []
        if let realtimeChannel {
            await client.removeChannel(realtimeChannel)
            self.realtimeChannel = nil
        }
    }
}

private enum SharedAppointmentServiceError: Error {
    case accountChanged
    case invalidDraft
    case invalidOutboxIdentity
    case invalidServerState
    case missingSavedAppointment
}

@MainActor
final class InMemorySharedAppointmentService: SharedAppointmentRemoteServing {
    private var appointments: [SharedAppointment]
    private var events: [SharedAppointmentEvent]
    private var discussionSummaries: [SharedAppointmentDiscussionSummary]
    private var pendingEntries: [SharedAppointmentOutboxEntry] = []
    private var pendingOperations: [SharedAppointmentOperationOutboxEntry] = []
    private var onChange: (@MainActor () async -> Void)?

    init(
        appointments: [SharedAppointment] = [],
        events: [SharedAppointmentEvent] = [],
        discussionSummaries: [SharedAppointmentDiscussionSummary] = []
    ) {
        self.appointments = appointments
        self.events = events
        self.discussionSummaries = discussionSummaries
    }

    func fetchAppointments() async throws -> [SharedAppointment] { appointments }

    func fetchAppointmentEvents() async throws -> [SharedAppointmentEvent] { events }

    func fetchRecentDiscussionSummaries() async throws -> [SharedAppointmentDiscussionSummary] {
        discussionSummaries
    }

    func fetchPendingAppointments() async throws -> [SharedAppointment] {
        let failed = (pendingEntries.first?.attemptCount ?? 0) > 0
        return pendingEntries.map { entry in
            var appointment = entry.appointment
            appointment.deliveryState = failed ? .failed : .sending
            return appointment
        }
    }

    func enqueueAppointment(
        _ draft: SharedAppointmentDraft,
        clientID: UUID,
        localCreatedAt: Date
    ) async throws {
        pendingEntries.append(SharedAppointmentOutboxEntry(
            userID: UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!,
            relationshipID: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            clientID: clientID,
            draft: draft,
            localCreatedAt: localCreatedAt,
            attemptCount: 0
        ))
    }

    func beginNextPendingAppointment() async throws -> SharedAppointmentOutboxEntry? {
        guard !pendingEntries.isEmpty else { return nil }
        pendingEntries[0].attemptCount += 1
        return pendingEntries[0]
    }

    func deliverPendingAppointment(
        _ entry: SharedAppointmentOutboxEntry
    ) async throws -> SharedAppointment {
        if let existing = appointments.first(where: { $0.id == entry.clientID }) {
            return existing
        }
        let appointment = SharedAppointment(
            id: entry.clientID,
            creatorUserID: UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!,
            title: entry.draft.title,
            startsAt: entry.draft.startsAt,
            location: entry.draft.location,
            note: entry.draft.note,
            reminderAt: entry.draft.reminderAt,
            status: .scheduled,
            sourceMessageID: entry.draft.sourceMessageID,
            createdAt: .now,
            updatedAt: .now
        )
        appointments.append(appointment)
        return appointment
    }

    func acknowledgePendingAppointment(clientID: UUID) async throws {
        guard pendingEntries.first?.clientID == clientID else {
            throw SharedAppointmentOutboxError.unexpectedAcknowledgement
        }
        pendingEntries.removeFirst()
    }

    func fetchPendingAppointmentOperations() async throws -> [SharedAppointmentOperationOutboxEntry] {
        pendingOperations
    }

    func enqueueAppointmentOperation(
        appointmentID: UUID,
        operationID: UUID,
        operation: SharedAppointmentOperation,
        localCreatedAt: Date
    ) async throws {
        pendingOperations.append(SharedAppointmentOperationOutboxEntry(
            userID: UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!,
            relationshipID: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            operationID: operationID,
            appointmentID: appointmentID,
            operation: operation,
            localCreatedAt: localCreatedAt,
            attemptCount: 0
        ))
    }

    func beginNextPendingAppointmentOperation() async throws -> SharedAppointmentOperationOutboxEntry? {
        guard !pendingOperations.isEmpty else { return nil }
        pendingOperations[0].attemptCount += 1
        return pendingOperations[0]
    }

    func deliverPendingAppointmentOperation(
        _ entry: SharedAppointmentOperationOutboxEntry
    ) async throws -> SharedAppointmentOperationDeliveryResult {
        switch entry.operation {
        case let .update(draft):
            return .accepted(try await performUpdateAppointment(
                id: entry.appointmentID,
                operationID: entry.operationID,
                actorUserID: entry.userID,
                draft: draft
            ))
        case .cancel:
            return .accepted(try await performCancelAppointment(
                id: entry.appointmentID,
                operationID: entry.operationID,
                actorUserID: entry.userID
            ))
        }
    }

    func acknowledgePendingAppointmentOperation(operationID: UUID) async throws {
        guard pendingOperations.first?.operationID == operationID else {
            throw SharedAppointmentOperationOutboxError.unexpectedAcknowledgement
        }
        pendingOperations.removeFirst()
    }

    private func performUpdateAppointment(
        id: UUID,
        operationID: UUID,
        actorUserID: UUID,
        draft: SharedAppointmentDraft
    ) async throws -> SharedAppointment {
        guard let index = appointments.firstIndex(where: { $0.id == id }),
              appointments[index].status == .scheduled,
              let normalized = SharedAppointmentPolicy.normalizedDraft(draft) else {
            throw SharedAppointmentServiceError.invalidDraft
        }
        let current = appointments[index]
        let updated = SharedAppointment(
            id: current.id,
            creatorUserID: current.creatorUserID,
            title: normalized.title,
            startsAt: normalized.startsAt,
            location: normalized.location,
            note: normalized.note,
            reminderAt: normalized.reminderAt,
            status: .scheduled,
            sourceMessageID: current.sourceMessageID,
            createdAt: current.createdAt,
            updatedAt: .now
        )
        appointments[index] = updated
        if current.startsAt != updated.startsAt,
           !events.contains(where: { $0.id == operationID }) {
            events.append(SharedAppointmentEvent(
                id: operationID,
                appointmentID: id,
                actorUserID: actorUserID,
                kind: .rescheduled,
                previousStartsAt: current.startsAt,
                startsAt: updated.startsAt,
                createdAt: .now
            ))
        }
        await onChange?()
        return updated
    }

    private func performCancelAppointment(
        id: UUID,
        operationID: UUID,
        actorUserID: UUID
    ) async throws -> SharedAppointment {
        guard let index = appointments.firstIndex(where: { $0.id == id }) else {
            throw SharedAppointmentServiceError.missingSavedAppointment
        }
        let current = appointments[index]
        guard current.status == .scheduled else { return current }
        let cancelled = SharedAppointment(
            id: current.id,
            creatorUserID: current.creatorUserID,
            title: current.title,
            startsAt: current.startsAt,
            location: current.location,
            note: current.note,
            reminderAt: current.reminderAt,
            status: .cancelled,
            sourceMessageID: current.sourceMessageID,
            createdAt: current.createdAt,
            updatedAt: .now
        )
        appointments[index] = cancelled
        if !events.contains(where: { $0.id == operationID }) {
            events.append(SharedAppointmentEvent(
                id: operationID,
                appointmentID: id,
                actorUserID: actorUserID,
                kind: .cancelled,
                previousStartsAt: nil,
                startsAt: nil,
                createdAt: .now
            ))
        }
        await onChange?()
        return cancelled
    }

    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws {
        self.onChange = onChange
    }

    func stopObservingChanges() async { onChange = nil }
}
