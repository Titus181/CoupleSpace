import Combine
import Foundation

@MainActor
final class SharedAppointmentModel: ObservableObject {
    @Published private(set) var appointments: [SharedAppointment] = []
    @Published private(set) var appointmentEvents: [SharedAppointmentEvent] = []
    @Published private(set) var recentDiscussionSummaries: [SharedAppointmentDiscussionSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var reminderStatusMessage: String?
    @Published private(set) var reminderAuthorization: SharedAppointmentReminderAuthorization = .notDetermined

    private let service: SharedAppointmentRemoteServing
    private let reminderScheduler: SharedAppointmentReminderScheduling
    private let now: () -> Date
    private let discussionModelFactory: ((UUID) -> ConversationModel)?
    private var hasStarted = false
    private var isDraining = false
    private var isDrainingOperations = false
    private var deliveryStatusMessage: String?
    private var operationDeliveryStatusMessage: String?
    private var terminalOperationMessage: String?
    private var discussionModels: [UUID: ConversationModel] = [:]

    init(
        service: SharedAppointmentRemoteServing,
        now: @escaping () -> Date = Date.init,
        reminderScheduler: SharedAppointmentReminderScheduling? = nil,
        discussionModelFactory: ((UUID) -> ConversationModel)? = nil
    ) {
        self.service = service
        self.now = now
        self.reminderScheduler = reminderScheduler ?? DisabledSharedAppointmentReminderScheduler()
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

    var discussionUnreadCount: Int {
        recentDiscussionSummaries.reduce(0) { $0 + $1.unreadCount }
    }

    func appointment(id: UUID) -> SharedAppointment? {
        appointments.first { $0.id == id }
    }

    func events(for appointmentID: UUID) -> [SharedAppointmentEvent] {
        appointmentEvents.filter { $0.appointmentID == appointmentID }
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
        await drainPendingAppointmentOperations(
            maximumAttemptsPerOperation: ConversationRecoveryRetryPolicy.maximumAttempts
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

    func prepareReminderAuthorization() async {
        let status = await reminderScheduler.requestAuthorization()
        updateReminderStatus(for: status, userRequested: true)
        if status == .authorized {
            await reconcileReminders()
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let remoteAppointments = service.fetchAppointments()
            async let remoteEvents = service.fetchAppointmentEvents()
            async let remoteDiscussionSummaries = service.fetchRecentDiscussionSummaries()
            async let pendingOperations = service.fetchPendingAppointmentOperations()
            let remote = try await remoteAppointments
            let events = try await remoteEvents
            let summaries = try await remoteDiscussionSummaries
            let operations = try await pendingOperations
            let remoteIDs = Set(remote.map(\.id))
            let pending = appointments.filter {
                $0.deliveryState != .synced && !remoteIDs.contains($0.id)
            }
            appointments = Self.applying(
                operations,
                to: remote + pending
            ).sorted(by: Self.appointmentOrder)
            await reconcileReminders()
            replaceAppointmentEvents(events)
            recentDiscussionSummaries = summaries
                .filter { remoteIDs.contains($0.appointmentID) }
                .sorted {
                    ($0.latestActivityAt, $0.appointmentID.uuidString)
                        > ($1.latestActivityAt, $1.appointmentID.uuidString)
                }
            statusMessage = terminalOperationMessage
                ?? operationDeliveryStatusMessage
                ?? deliveryStatusMessage
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
        if normalized.reminderAt != nil {
            await prepareReminderAuthorization()
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
        if preservedSourceDraft.reminderAt != nil {
            await prepareReminderAuthorization()
        }
        isSaving = true
        defer { isSaving = false }
        let operationID = UUID()
        let localCreatedAt = now()
        terminalOperationMessage = nil
        do {
            try await service.enqueueAppointmentOperation(
                appointmentID: id,
                operationID: operationID,
                operation: .update(preservedSourceDraft),
                localCreatedAt: localCreatedAt
            )
            replaceAppointment(SharedAppointmentOperationOutboxEntry(
                userID: UUID(),
                relationshipID: UUID(),
                operationID: operationID,
                appointmentID: id,
                operation: .update(preservedSourceDraft),
                localCreatedAt: localCreatedAt,
                attemptCount: 0
            ).applying(to: current))
        } catch {
            statusMessage = "共同約定未保存到這支裝置，請再試一次。"
            return false
        }
        await drainPendingAppointmentOperations(maximumAttemptsPerOperation: 1)
        return true
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
        let operationID = UUID()
        let localCreatedAt = now()
        terminalOperationMessage = nil
        do {
            try await service.enqueueAppointmentOperation(
                appointmentID: id,
                operationID: operationID,
                operation: .cancel,
                localCreatedAt: localCreatedAt
            )
            replaceAppointment(SharedAppointmentOperationOutboxEntry(
                userID: UUID(),
                relationshipID: UUID(),
                operationID: operationID,
                appointmentID: id,
                operation: .cancel,
                localCreatedAt: localCreatedAt,
                attemptCount: 0
            ).applying(to: current))
        } catch {
            statusMessage = "取消操作未保存到這支裝置，請再試一次。"
            return false
        }
        await drainPendingAppointmentOperations(maximumAttemptsPerOperation: 1)
        return true
    }

    func recoverPendingAppointments() async {
        await loadPendingAppointments()
        await drainPendingAppointments(
            maximumAttemptsPerAppointment: ConversationRecoveryRetryPolicy.maximumAttempts
        )
        await drainPendingAppointmentOperations(
            maximumAttemptsPerOperation: ConversationRecoveryRetryPolicy.maximumAttempts
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
                    await reconcileReminders()
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

    private func drainPendingAppointmentOperations(maximumAttemptsPerOperation: Int) async {
        guard !isDrainingOperations else { return }
        isDrainingOperations = true
        defer { isDrainingOperations = false }
        while true {
            var attempt = 0
            var resolved = false
            while attempt < maximumAttemptsPerOperation {
                let entry: SharedAppointmentOperationOutboxEntry
                do {
                    guard let next = try await service.beginNextPendingAppointmentOperation() else {
                        return
                    }
                    entry = next
                    applyPendingOperation(entry)
                } catch {
                    statusMessage = "無法讀取待同步的約定操作，請稍後再試。"
                    return
                }

                do {
                    let result = try await service.deliverPendingAppointmentOperation(entry)
                    try await service.acknowledgePendingAppointmentOperation(
                        operationID: entry.operationID
                    )
                    switch result {
                    case let .accepted(saved):
                        replaceAppointment(saved)
                        await refreshAppointmentEvents()
                        operationDeliveryStatusMessage = nil
                        switch entry.operation {
                        case .update:
                            statusMessage = terminalOperationMessage ?? "共同約定已更新。"
                        case .cancel:
                            statusMessage = terminalOperationMessage
                                ?? "共同約定已取消，原內容仍會保留。"
                        }
                    case let .rejected(remoteAppointment, message):
                        if let remoteAppointment {
                            replaceAppointment(remoteAppointment)
                        } else {
                            appointments.removeAll { $0.id == entry.appointmentID }
                        }
                        operationDeliveryStatusMessage = message
                        terminalOperationMessage = message
                        statusMessage = message
                    }
                    await reconcileReminders()
                    resolved = true
                    break
                } catch {
                    attempt += 1
                    applyPendingOperation(entry)
                    let message = "約定變更已保存在這支裝置；請確認連線後重試。"
                    operationDeliveryStatusMessage = message
                    statusMessage = message
                    guard attempt < maximumAttemptsPerOperation,
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

    private func applyPendingOperation(_ entry: SharedAppointmentOperationOutboxEntry) {
        guard let current = appointment(id: entry.appointmentID) else { return }
        replaceAppointment(entry.applying(to: current))
    }

    private func refreshAppointmentEvents() async {
        guard let events = try? await service.fetchAppointmentEvents() else { return }
        replaceAppointmentEvents(events)
    }

    private func reconcileReminders() async {
        do {
            try await reminderScheduler.reconcile(appointments)
            updateReminderStatus(for: await reminderScheduler.authorizationStatus())
        } catch {
            reminderStatusMessage = "這支手機暫時無法更新約定提醒，稍後會再試。"
        }
    }

    private func updateReminderStatus(
        for status: SharedAppointmentReminderAuthorization,
        userRequested: Bool = false
    ) {
        reminderAuthorization = status
        let hasFutureReminder = appointments.contains {
            $0.status == .scheduled && $0.reminderAt.map { $0 > now() } == true
        }
        switch status {
        case .authorized:
            reminderStatusMessage = nil
        case .notDetermined:
            reminderStatusMessage = (hasFutureReminder || userRequested)
                ? "允許通知後，這支手機才會在指定時間提醒。"
                : nil
        case .denied:
            reminderStatusMessage = (hasFutureReminder || userRequested)
                ? "這支手機尚未允許通知；約定仍會同步，但不會在指定時間提醒。"
                : nil
        }
    }

    private func replaceAppointmentEvents(_ events: [SharedAppointmentEvent]) {
        let appointmentIDs = Set(appointments.map(\.id))
        appointmentEvents = events
            .filter { appointmentIDs.contains($0.appointmentID) }
            .sorted {
                ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
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

    private static func applying(
        _ operations: [SharedAppointmentOperationOutboxEntry],
        to appointments: [SharedAppointment]
    ) -> [SharedAppointment] {
        operations.reduce(appointments) { current, operation in
            current.map { operation.applying(to: $0) }
        }
    }
}
