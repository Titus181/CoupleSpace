import Combine
import Foundation

@MainActor
final class SharedAppointmentModel: ObservableObject {
    @Published private(set) var appointments: [SharedAppointment] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var statusMessage: String?

    private let service: SharedAppointmentRemoteServing
    private let now: () -> Date
    private let discussionModelFactory: ((UUID) -> ConversationModel)?
    private var hasStarted = false
    private var isDraining = false
    private var deliveryStatusMessage: String?
    private var discussionModels: [UUID: ConversationModel] = [:]

    init(
        service: SharedAppointmentRemoteServing,
        now: @escaping () -> Date = Date.init,
        discussionModelFactory: ((UUID) -> ConversationModel)? = nil
    ) {
        self.service = service
        self.now = now
        self.discussionModelFactory = discussionModelFactory
    }

    var nextAppointment: SharedAppointment? {
        upcomingAppointments.first
    }

    var upcomingAppointments: [SharedAppointment] {
        appointments.filter {
            $0.status == .scheduled && $0.startsAt >= now()
        }
    }

    var pastOrCancelledAppointments: [SharedAppointment] {
        appointments.filter {
            $0.status == .cancelled || $0.startsAt < now()
        }
        .sorted { lhs, rhs in
            (lhs.startsAt, lhs.id.uuidString) > (rhs.startsAt, rhs.id.uuidString)
        }
    }

    func appointment(id: UUID) -> SharedAppointment? {
        appointments.first { $0.id == id }
    }

    func appointments(
        on date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [SharedAppointment] {
        appointments.filter { calendar.isDate($0.startsAt, inSameDayAs: date) }
            .sorted(by: Self.appointmentOrder)
    }

    func discussionModel(for appointmentID: UUID) -> ConversationModel? {
        guard appointment(id: appointmentID)?.deliveryState == .synced else { return nil }
        if let existing = discussionModels[appointmentID] { return existing }
        guard let created = discussionModelFactory?(appointmentID) else { return nil }
        discussionModels[appointmentID] = created
        return created
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await loadPendingAppointments()
        await refresh()
        do {
            try await service.startObservingChanges { [weak self] in
                await self?.refresh()
            }
        } catch {
            statusMessage = "共同約定的即時同步暫時無法連線。"
        }
        await drainPendingAppointments(
            maximumAttemptsPerAppointment: ConversationRecoveryRetryPolicy.maximumAttempts
        )
        await refresh()
    }

    func stop() async {
        hasStarted = false
        await service.stopObservingChanges()
        for discussionModel in discussionModels.values {
            await discussionModel.stop()
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let remote = try await service.fetchAppointments()
            let remoteIDs = Set(remote.map(\.id))
            let pending = appointments.filter {
                $0.deliveryState != .synced && !remoteIDs.contains($0.id)
            }
            appointments = (remote + pending).sorted(by: Self.appointmentOrder)
            statusMessage = deliveryStatusMessage
        } catch {
            statusMessage = "無法更新共同約定，請稍後再試。"
        }
    }

    @discardableResult
    func create(_ draft: SharedAppointmentDraft) async -> Bool {
        guard !isSaving, let normalized = SharedAppointmentPolicy.normalizedDraft(draft) else {
            statusMessage = "請確認標題、時間與提醒設定。"
            return false
        }
        let clientID = UUID()
        let localCreatedAt = now()
        isSaving = true
        defer { isSaving = false }
        do {
            try await service.enqueueAppointment(
                normalized,
                clientID: clientID,
                localCreatedAt: localCreatedAt
            )
            mergeAppointments([SharedAppointment(
                id: clientID,
                creatorUserID: UUID(),
                title: normalized.title,
                startsAt: normalized.startsAt,
                location: normalized.location,
                note: normalized.note,
                reminderAt: normalized.reminderAt,
                status: .scheduled,
                sourceMessageID: normalized.sourceMessageID,
                createdAt: localCreatedAt,
                updatedAt: localCreatedAt,
                deliveryState: .sending
            )])
        } catch {
            statusMessage = "共同約定未保存到這支裝置，請再試一次。"
            return false
        }

        await drainPendingAppointments(maximumAttemptsPerAppointment: 1)
        return true
    }

    func retryAppointment(id: UUID) async {
        guard appointments.contains(where: {
            $0.id == id && $0.deliveryState == .failed
        }) else { return }
        await drainPendingAppointments(maximumAttemptsPerAppointment: 1)
    }

    @discardableResult
    func update(id: UUID, draft: SharedAppointmentDraft) async -> Bool {
        guard !isSaving,
              let current = appointment(id: id),
              current.status == .scheduled,
              current.deliveryState == .synced,
              let normalized = SharedAppointmentPolicy.normalizedDraft(draft) else {
            statusMessage = "請確認約定仍可編輯，並檢查內容與提醒時間。"
            return false
        }
        let preservedSourceDraft = SharedAppointmentDraft(
            title: normalized.title,
            startsAt: normalized.startsAt,
            location: normalized.location,
            note: normalized.note,
            reminderAt: normalized.reminderAt,
            sourceMessageID: current.sourceMessageID
        )
        isSaving = true
        defer { isSaving = false }
        do {
            replaceAppointment(try await service.updateAppointment(
                id: id,
                draft: preservedSourceDraft
            ))
            statusMessage = "共同約定已更新。"
            return true
        } catch {
            statusMessage = "共同約定尚未更新；請確認連線後再試。"
            return false
        }
    }

    @discardableResult
    func cancel(id: UUID) async -> Bool {
        guard !isSaving,
              let current = appointment(id: id),
              current.status == .scheduled,
              current.deliveryState == .synced else {
            statusMessage = "這筆共同約定目前無法取消。"
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            replaceAppointment(try await service.cancelAppointment(id: id))
            statusMessage = "共同約定已取消，原內容仍會保留。"
            return true
        } catch {
            statusMessage = "共同約定尚未取消；請確認連線後再試。"
            return false
        }
    }

    func recoverPendingAppointments() async {
        await loadPendingAppointments()
        await drainPendingAppointments(
            maximumAttemptsPerAppointment: ConversationRecoveryRetryPolicy.maximumAttempts
        )
        await refresh()
    }

    private func loadPendingAppointments() async {
        do {
            mergeAppointments(try await service.fetchPendingAppointments())
        } catch {
            statusMessage = "無法讀取待同步共同約定，請稍後再試。"
        }
    }

    private func drainPendingAppointments(maximumAttemptsPerAppointment: Int) async {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }
        while true {
            var attempt = 0
            var resolved = false
            while attempt < maximumAttemptsPerAppointment {
                let entry: SharedAppointmentOutboxEntry
                do {
                    guard let next = try await service.beginNextPendingAppointment() else {
                        return
                    }
                    entry = next
                    mergeAppointments([entry.appointment])
                } catch {
                    statusMessage = "無法讀取待同步共同約定，請稍後再試。"
                    return
                }

                do {
                    let saved = try await service.deliverPendingAppointment(entry)
                    try await service.acknowledgePendingAppointment(clientID: entry.clientID)
                    appointments.removeAll { $0.id == entry.clientID }
                    mergeAppointments([saved])
                    deliveryStatusMessage = nil
                    statusMessage = "共同約定已同步。"
                    resolved = true
                    break
                } catch {
                    attempt += 1
                    markPendingAppointmentsFailed()
                    let message = "共同約定已保存在這支裝置；請確認連線後重試。"
                    deliveryStatusMessage = message
                    statusMessage = message
                    guard attempt < maximumAttemptsPerAppointment,
                          let delay = ConversationRecoveryRetryPolicy.delayNanoseconds(
                              afterAttempt: attempt
                          ) else { return }
                    do {
                        try await Task.sleep(nanoseconds: delay)
                    } catch {
                        return
                    }
                }
            }
            if !resolved { return }
        }
    }

    private func markPendingAppointmentsFailed() {
        appointments = appointments.map { appointment in
            guard appointment.deliveryState != .synced else { return appointment }
            var failed = appointment
            failed.deliveryState = .failed
            return failed
        }
    }

    private func mergeAppointments(_ incoming: [SharedAppointment]) {
        var byID = Dictionary(uniqueKeysWithValues: appointments.map { ($0.id, $0) })
        for appointment in incoming {
            if byID[appointment.id]?.deliveryState == .synced { continue }
            byID[appointment.id] = appointment
        }
        appointments = byID.values.sorted(by: Self.appointmentOrder)
    }

    private func replaceAppointment(_ appointment: SharedAppointment) {
        appointments.removeAll { $0.id == appointment.id }
        appointments.append(appointment)
        appointments.sort(by: Self.appointmentOrder)
    }

    private static func appointmentOrder(
        _ lhs: SharedAppointment,
        _ rhs: SharedAppointment
    ) -> Bool {
        (lhs.startsAt, lhs.id.uuidString) < (rhs.startsAt, rhs.id.uuidString)
    }
}
