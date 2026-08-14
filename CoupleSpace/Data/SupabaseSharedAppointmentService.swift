import Foundation
import Supabase

@MainActor
protocol SharedAppointmentRemoteServing: AnyObject {
    func fetchPendingAppointments() async throws -> [SharedAppointment]
    func fetchAppointments() async throws -> [SharedAppointment]
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
    func updateAppointment(
        id: UUID,
        draft: SharedAppointmentDraft
    ) async throws -> SharedAppointment
    func cancelAppointment(id: UUID) async throws -> SharedAppointment
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
    let targetTitle: String
    let targetStartsAt: Date
    let targetLocation: String?
    let targetNote: String?
    let targetReminderAt: Date?

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetAppointmentClientID = "target_appointment_client_id"
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

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetAppointmentClientID = "target_appointment_client_id"
    }
}

@MainActor
final class SupabaseSharedAppointmentService: SharedAppointmentRemoteServing {
    private let client: SupabaseClient
    private let currentUserID: UUID
    private let relationshipID: UUID
    private let outboxStore: SharedAppointmentOutboxStore
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTask: Task<Void, Never>?

    init(
        client: SupabaseClient,
        currentUserID: UUID,
        relationshipID: UUID,
        outboxStore: SharedAppointmentOutboxStore
    ) {
        self.client = client
        self.currentUserID = currentUserID
        self.relationshipID = relationshipID
        self.outboxStore = outboxStore
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

    func updateAppointment(
        id: UUID,
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

    func cancelAppointment(id: UUID) async throws -> SharedAppointment {
        let session = try await client.auth.session
        guard session.user.id == currentUserID else {
            throw SharedAppointmentServiceError.accountChanged
        }
        let rows: [SharedAppointmentRow] = try await client.rpc(
            "cancel_shared_appointment",
            params: CancelSharedAppointmentParameters(
                targetRelationshipID: relationshipID,
                targetAppointmentClientID: id
            )
        ).execute().value
        guard let row = rows.first else {
            throw SharedAppointmentServiceError.missingSavedAppointment
        }
        return try row.appointment()
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
        realtimeChannel = channel
        realtimeTask = Task {
            for await _ in stream {
                guard !Task.isCancelled else { return }
                await onChange()
            }
        }
        do {
            try await channel.subscribeWithError()
        } catch {
            realtimeTask?.cancel()
            realtimeTask = nil
            realtimeChannel = nil
            await client.removeChannel(channel)
            throw error
        }
    }

    func stopObservingChanges() async {
        realtimeTask?.cancel()
        realtimeTask = nil
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
    private var pendingEntries: [SharedAppointmentOutboxEntry] = []
    private var onChange: (@MainActor () async -> Void)?

    init(appointments: [SharedAppointment] = []) {
        self.appointments = appointments
    }

    func fetchAppointments() async throws -> [SharedAppointment] { appointments }

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

    func updateAppointment(
        id: UUID,
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
        await onChange?()
        return updated
    }

    func cancelAppointment(id: UUID) async throws -> SharedAppointment {
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
        await onChange?()
        return cancelled
    }

    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws {
        self.onChange = onChange
    }

    func stopObservingChanges() async { onChange = nil }
}
