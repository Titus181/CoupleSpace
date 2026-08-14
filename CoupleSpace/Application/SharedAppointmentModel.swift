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
    private var hasStarted = false
    private var isDraining = false
    private var deliveryStatusMessage: String?

    init(
        service: SharedAppointmentRemoteServing,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.now = now
    }

    var nextAppointment: SharedAppointment? {
        appointments.first {
            $0.status == .scheduled && $0.startsAt >= now()
        }
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

    private static func appointmentOrder(
        _ lhs: SharedAppointment,
        _ rhs: SharedAppointment
    ) -> Bool {
        (lhs.startsAt, lhs.id.uuidString) < (rhs.startsAt, rhs.id.uuidString)
    }
}
