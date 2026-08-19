import Combine
import Foundation

@MainActor
final class SharedAppointmentModel: ObservableObject {
    private struct LifecycleRequest {
        let generation: Int
        let requiresActiveModel: Bool
    }

    @Published private(set) var appointments: [SharedAppointment] = []
    @Published private(set) var appointmentEvents: [SharedAppointmentEvent] = []
    @Published private(set) var recentDiscussionSummaries: [SharedAppointmentDiscussionSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var reminderStatusMessage: String?
    @Published private(set) var reminderAuthorization: SharedAppointmentReminderAuthorization = .notDetermined
    @Published private(set) var refreshGeneration = 0

    private let service: SharedAppointmentRemoteServing
    private let reminderScheduler: SharedAppointmentReminderScheduling
    private let now: () -> Date
    private let discussionModelFactory: ((UUID) -> ConversationModel)?
    private var hasStarted = false
    private var lifecycleGeneration = 0
    private var activeLifecycleWorkByGeneration: [Int: Int] = [:]
    private var lifecycleWorkWaitersByGeneration: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var observationTransitionTask: Task<Bool, Never>?
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

    func markInteractionRead(
        for appointmentID: UUID,
        visibleSourceIdentity: UUID?
    ) async {
        guard appointment(id: appointmentID) != nil else { return }
        do {
            try await service.markAppointmentInteractionsRead(
                appointmentID: appointmentID,
                visibleSourceIdentity: visibleSourceIdentity
            )
            await refresh()
        } catch {
            statusMessage = "無法更新約定未讀，請確認連線後再試。"
        }
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        lifecycleGeneration &+= 1
        let request = LifecycleRequest(
            generation: lifecycleGeneration,
            requiresActiveModel: true
        )
        guard isCurrent(request) else { return }
        beginLifecycleWork(for: request)
        await reminderScheduler.activate()
        endLifecycleWork(for: request)
        guard isCurrent(request) else { return }
        await loadCachedAppointments(for: request)
        guard isCurrent(request) else { return }
        await loadPendingAppointments(for: request)
        guard isCurrent(request) else { return }
        await loadPendingAppointmentOperations(for: request)
        guard isCurrent(request) else { return }
        await refresh(for: request)
        guard isCurrent(request) else { return }
        let isObserving = await startObservation(for: request)
        guard isCurrent(request) else { return }
        if !isObserving {
            statusMessage = "共同約定的即時同步暫時無法連線。"
        }
        await drainPendingAppointments(
            maximumAttemptsPerAppointment: ConversationRecoveryRetryPolicy.maximumAttempts,
            request: request
        )
        guard isCurrent(request) else { return }
        await drainPendingAppointmentOperations(
            maximumAttemptsPerOperation: ConversationRecoveryRetryPolicy.maximumAttempts,
            request: request
        )
        guard isCurrent(request) else { return }
        await refresh(for: request)
    }

    func stop() async {
        let endingGeneration = lifecycleGeneration
        hasStarted = false
        lifecycleGeneration &+= 1
        let stoppedGeneration = lifecycleGeneration
        await stopObservation()
        await waitForLifecycleWork(generation: endingGeneration)
        for discussionModel in discussionModels.values {
            guard !hasStarted, lifecycleGeneration == stoppedGeneration else { return }
            await discussionModel.stop()
        }
    }

    func prepareReminderAuthorization() async {
        let status = await reminderScheduler.requestAuthorization()
        updateReminderStatus(for: status, userRequested: true)
        if status == .authorized,
           let request = lifecycleRequestAllowingInitialExplicitWork() {
            await reconcileReminders(for: request)
        }
    }

    func refresh() async {
        guard let request = lifecycleRequestAllowingInitialExplicitWork() else { return }
        await refresh(for: request)
    }

    private func refresh(for request: LifecycleRequest) async {
        while isLoading {
            guard isCurrent(request) else { return }
            await Task.yield()
        }
        guard isCurrent(request) else { return }
        beginLifecycleWork(for: request)
        isLoading = true
        defer {
            isLoading = false
            endLifecycleWork(for: request)
        }
        do {
            async let remoteAppointments = service.fetchAppointments()
            async let remoteEvents = service.fetchAppointmentEvents()
            async let remoteDiscussionSummaries = service.fetchRecentDiscussionSummaries()
            async let pendingOperations = service.fetchPendingAppointmentOperations()
            let remote = try await remoteAppointments
            let events = try await remoteEvents
            let summaries = try await remoteDiscussionSummaries
            let operations = try await pendingOperations
            guard isCurrent(request) else { return }
            let remoteIDs = Set(remote.map(\.id))
            let pending = appointments.filter {
                $0.deliveryState != .synced && !remoteIDs.contains($0.id)
            }
            appointments = Self.applying(
                operations,
                to: remote + pending
            ).sorted(by: Self.appointmentOrder)
            await reconcileReminders(for: request)
            guard isCurrent(request) else { return }
            replaceAppointmentEvents(events)
            recentDiscussionSummaries = summaries
                .filter { remoteIDs.contains($0.appointmentID) }
                .sorted {
                    ($0.latestActivityAt, $0.appointmentID.uuidString)
                        > ($1.latestActivityAt, $1.appointmentID.uuidString)
                }
            refreshGeneration &+= 1
            statusMessage = terminalOperationMessage
                ?? operationDeliveryStatusMessage
                ?? deliveryStatusMessage
        } catch {
            guard isCurrent(request) else { return }
            statusMessage = operationDeliveryStatusMessage
                ?? deliveryStatusMessage
                ?? (appointments.isEmpty
                    ? "無法更新共同約定，請稍後再試。"
                    : "目前顯示上次已同步的共同約定；連線後會自動更新。")
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

        if let request = lifecycleRequestAllowingInitialExplicitWork() {
            await drainPendingAppointments(
                maximumAttemptsPerAppointment: 1,
                request: request
            )
        }
        return true
    }

    func retryAppointment(id: UUID) async {
        guard appointments.contains(where: {
            $0.id == id && $0.deliveryState == .failed
        }) else { return }
        if let request = lifecycleRequestAllowingInitialExplicitWork() {
            await drainPendingAppointments(
                maximumAttemptsPerAppointment: 1,
                request: request
            )
        }
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
        if let request = lifecycleRequestAllowingInitialExplicitWork() {
            await drainPendingAppointmentOperations(
                maximumAttemptsPerOperation: 1,
                request: request
            )
        }
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
        if let request = lifecycleRequestAllowingInitialExplicitWork() {
            await drainPendingAppointmentOperations(
                maximumAttemptsPerOperation: 1,
                request: request
            )
        }
        return true
    }

    func recoverPendingAppointments() async {
        guard let request = lifecycleRequestAllowingInitialExplicitWork() else { return }
        await loadCachedAppointments(for: request)
        guard isCurrent(request) else { return }
        await loadPendingAppointments(for: request)
        guard isCurrent(request) else { return }
        await loadPendingAppointmentOperations(for: request)
        guard isCurrent(request) else { return }
        await drainPendingAppointments(
            maximumAttemptsPerAppointment: ConversationRecoveryRetryPolicy.maximumAttempts,
            request: request
        )
        guard isCurrent(request) else { return }
        await drainPendingAppointmentOperations(
            maximumAttemptsPerOperation: ConversationRecoveryRetryPolicy.maximumAttempts,
            request: request
        )
        guard isCurrent(request) else { return }
        await refresh(for: request)
    }

    private func loadCachedAppointments(for request: LifecycleRequest) async {
        guard let cached = try? await service.fetchCachedAppointments() else { return }
        guard isCurrent(request) else { return }
        mergeAppointments(cached)
    }

    private func loadPendingAppointments(for request: LifecycleRequest) async {
        do {
            let pending = try await service.fetchPendingAppointments()
            guard isCurrent(request) else { return }
            mergeAppointments(pending)
        } catch {
            guard isCurrent(request) else { return }
            statusMessage = "無法讀取待同步共同約定，請稍後再試。"
        }
    }

    private func loadPendingAppointmentOperations(for request: LifecycleRequest) async {
        do {
            let operations = try await service.fetchPendingAppointmentOperations()
            guard isCurrent(request) else { return }
            guard !operations.isEmpty else { return }
            appointments = Self.applying(operations, to: appointments)
                .sorted(by: Self.appointmentOrder)
            let message = "約定變更已保存在這支裝置；請確認連線後重試。"
            operationDeliveryStatusMessage = message
            statusMessage = message
        } catch {
            guard isCurrent(request) else { return }
            statusMessage = "無法讀取待同步的約定操作，請稍後再試。"
        }
    }

    private func drainPendingAppointments(
        maximumAttemptsPerAppointment: Int,
        request: LifecycleRequest
    ) async {
        while isDraining {
            guard isCurrent(request) else { return }
            await Task.yield()
        }
        guard isCurrent(request) else { return }
        beginLifecycleWork(for: request)
        isDraining = true
        defer {
            isDraining = false
            endLifecycleWork(for: request)
        }
        while isCurrent(request) {
            var attempt = 0
            var resolved = false
            while attempt < maximumAttemptsPerAppointment {
                let entry: SharedAppointmentOutboxEntry
                do {
                    guard let next = try await service.beginNextPendingAppointment() else {
                        return
                    }
                    entry = next
                    guard isCurrent(request) else { return }
                    mergeAppointments([entry.appointment])
                } catch {
                    guard isCurrent(request) else { return }
                    statusMessage = "無法讀取待同步共同約定，請稍後再試。"
                    return
                }

                do {
                    let saved = try await service.deliverPendingAppointment(entry)
                    try await service.acknowledgePendingAppointment(clientID: entry.clientID)
                    guard isCurrent(request) else { return }
                    appointments.removeAll { $0.id == entry.clientID }
                    mergeAppointments([saved])
                    await reconcileReminders(for: request)
                    guard isCurrent(request) else { return }
                    deliveryStatusMessage = nil
                    statusMessage = "共同約定已同步。"
                    resolved = true
                    break
                } catch {
                    guard isCurrent(request) else { return }
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
                    guard isCurrent(request) else { return }
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

    private func drainPendingAppointmentOperations(
        maximumAttemptsPerOperation: Int,
        request: LifecycleRequest
    ) async {
        while isDrainingOperations {
            guard isCurrent(request) else { return }
            await Task.yield()
        }
        guard isCurrent(request) else { return }
        beginLifecycleWork(for: request)
        isDrainingOperations = true
        defer {
            isDrainingOperations = false
            endLifecycleWork(for: request)
        }
        while isCurrent(request) {
            var attempt = 0
            var resolved = false
            while attempt < maximumAttemptsPerOperation {
                let entry: SharedAppointmentOperationOutboxEntry
                do {
                    guard let next = try await service.beginNextPendingAppointmentOperation() else {
                        return
                    }
                    entry = next
                    guard isCurrent(request) else { return }
                    applyPendingOperation(entry)
                } catch {
                    guard isCurrent(request) else { return }
                    statusMessage = "無法讀取待同步的約定操作，請稍後再試。"
                    return
                }

                do {
                    let result = try await service.deliverPendingAppointmentOperation(entry)
                    try await service.acknowledgePendingAppointmentOperation(
                        operationID: entry.operationID
                    )
                    guard isCurrent(request) else { return }
                    switch result {
                    case let .accepted(saved):
                        replaceAppointment(saved)
                        await refreshAppointmentEvents(for: request)
                        guard isCurrent(request) else { return }
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
                    await reconcileReminders(for: request)
                    guard isCurrent(request) else { return }
                    resolved = true
                    break
                } catch {
                    guard isCurrent(request) else { return }
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
                    guard isCurrent(request) else { return }
                }
            }
            if !resolved { return }
        }
    }

    private func applyPendingOperation(_ entry: SharedAppointmentOperationOutboxEntry) {
        guard let current = appointment(id: entry.appointmentID) else { return }
        replaceAppointment(entry.applying(to: current))
    }

    private func refreshAppointmentEvents(for request: LifecycleRequest) async {
        guard let events = try? await service.fetchAppointmentEvents() else { return }
        guard isCurrent(request) else { return }
        replaceAppointmentEvents(events)
    }

    private func reconcileReminders(for request: LifecycleRequest) async {
        guard isCurrent(request) else { return }
        beginLifecycleWork(for: request)
        defer { endLifecycleWork(for: request) }
        do {
            try await reminderScheduler.reconcile(appointments)
            guard isCurrent(request) else { return }
            let authorization = await reminderScheduler.authorizationStatus()
            guard isCurrent(request) else { return }
            updateReminderStatus(for: authorization)
        } catch {
            guard isCurrent(request) else { return }
            reminderStatusMessage = "這支手機暫時無法更新約定提醒，稍後會再試。"
        }
    }

    private func activeLifecycleRequest() -> LifecycleRequest? {
        guard hasStarted else { return nil }
        return LifecycleRequest(
            generation: lifecycleGeneration,
            requiresActiveModel: true
        )
    }

    private func lifecycleRequestAllowingInitialExplicitWork() -> LifecycleRequest? {
        if let active = activeLifecycleRequest() { return active }
        guard lifecycleGeneration == 0 else { return nil }
        return LifecycleRequest(generation: 0, requiresActiveModel: false)
    }

    private func isCurrent(_ request: LifecycleRequest) -> Bool {
        request.generation == lifecycleGeneration
            && (!request.requiresActiveModel || hasStarted)
    }

    private func beginLifecycleWork(for request: LifecycleRequest) {
        activeLifecycleWorkByGeneration[request.generation, default: 0] += 1
    }

    private func endLifecycleWork(for request: LifecycleRequest) {
        let remaining = (activeLifecycleWorkByGeneration[request.generation] ?? 1) - 1
        if remaining > 0 {
            activeLifecycleWorkByGeneration[request.generation] = remaining
        } else {
            activeLifecycleWorkByGeneration[request.generation] = nil
            let waiters = lifecycleWorkWaitersByGeneration.removeValue(
                forKey: request.generation
            ) ?? []
            for waiter in waiters { waiter.resume() }
        }
    }

    private func waitForLifecycleWork(generation: Int) async {
        guard activeLifecycleWorkByGeneration[generation, default: 0] > 0 else { return }
        await withCheckedContinuation { continuation in
            guard activeLifecycleWorkByGeneration[generation, default: 0] > 0 else {
                continuation.resume()
                return
            }
            lifecycleWorkWaitersByGeneration[generation, default: []].append(continuation)
        }
    }

    private func startObservation(for request: LifecycleRequest) async -> Bool {
        let previous = observationTransitionTask
        let transition = Task { @MainActor [weak self] in
            _ = await previous?.value
            guard let self, self.isCurrent(request) else { return false }
            do {
                try await self.service.startObservingChanges { [weak self] in
                    guard let self, self.isCurrent(request) else { return }
                    await self.refresh(for: request)
                }
                return self.isCurrent(request)
            } catch {
                return false
            }
        }
        observationTransitionTask = transition
        return await transition.value
    }

    private func stopObservation() async {
        let previous = observationTransitionTask
        let transition = Task { @MainActor [weak self] in
            _ = await previous?.value
            guard let self else { return false }
            await self.service.stopObservingChanges()
            return false
        }
        observationTransitionTask = transition
        _ = await transition.value
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
