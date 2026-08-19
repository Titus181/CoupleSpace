import Combine
import Foundation

@MainActor
final class TogetherNowModel: ObservableObject {
    private struct LifecycleRequest {
        let generation: Int
        let requiresActiveModel: Bool
    }

    @Published private(set) var snapshot: TogetherNowSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var statusMessage: String?

    private let service: TogetherNowRemoteServing
    private let now: () -> Date
    private let calendar: Calendar
    private var hasStarted = false
    private var lifecycleGeneration = 0
    private var activeLifecycleWorkByGeneration: [Int: Int] = [:]
    private var lifecycleWorkWaitersByGeneration: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var observationTransitionTask: Task<Bool, Never>?
    private var expirationTask: Task<Void, Never>?
    private var pendingStatusAttempt: (draft: CurrentStatusDraft, momentID: UUID?)?

    init(
        service: TogetherNowRemoteServing,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.service = service
        self.now = now
        self.calendar = calendar
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        lifecycleGeneration &+= 1
        let request = LifecycleRequest(
            generation: lifecycleGeneration,
            requiresActiveModel: true
        )
        if let cached = service.cachedSnapshot() {
            apply(cached, request: request)
        }
        await refresh(for: request)
        guard isCurrent(request) else { return }
        let isObserving = await startObservation(for: request)
        guard isCurrent(request) else { return }
        if !isObserving {
            statusMessage = "即時同步暫時無法連線；重新開啟畫面時會再讀取。"
        }
    }

    func stop() async {
        let endingGeneration = lifecycleGeneration
        hasStarted = false
        lifecycleGeneration &+= 1
        expirationTask?.cancel()
        expirationTask = nil
        await stopObservation()
        await waitForLifecycleWork(generation: endingGeneration)
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
            let fetched = try await service.fetchSnapshot()
            guard isCurrent(request) else { return }
            apply(fetched, request: request)
            statusMessage = nil
        } catch {
            guard isCurrent(request) else { return }
            statusMessage = "無法更新現在的我們，請稍後再試。"
        }
    }

    @discardableResult
    func saveNames(displayName: String, privatePartnerName: String) async -> Bool {
        guard !isSaving,
              TogetherNowTextPolicy.isValidOptionalNameInput(displayName),
              TogetherNowTextPolicy.isValidOptionalNameInput(privatePartnerName)
        else {
            statusMessage = "名稱最多 20 字。"
            return false
        }

        isSaving = true
        defer { isSaving = false }
        do {
            try await service.updateNames(
                displayName: TogetherNowTextPolicy.normalizedOptionalName(displayName),
                privatePartnerName: TogetherNowTextPolicy.normalizedOptionalName(privatePartnerName)
            )
            await refresh()
            statusMessage = "稱呼已更新。"
            return true
        } catch {
            statusMessage = "稱呼尚未更新，請確認連線後再試。"
            return false
        }
    }

    @discardableResult
    func saveStatus(_ draft: CurrentStatusDraft) async -> Bool {
        guard !isSaving else { return false }
        let normalizedDraft: CurrentStatusDraft
        switch draft.content {
        case .fixed:
            normalizedDraft = draft
        case let .custom(value):
            guard let value = TogetherNowTextPolicy.normalizedCustomStatus(value) else {
                statusMessage = "自訂狀態需為 1–40 字。"
                return false
            }
            normalizedDraft = CurrentStatusDraft(
                content: .custom(value),
                expiration: draft.expiration,
                savesAsMoment: draft.savesAsMoment
            )
        }

        let attempt: (draft: CurrentStatusDraft, momentID: UUID?)
        if let pendingStatusAttempt, pendingStatusAttempt.draft == normalizedDraft {
            attempt = pendingStatusAttempt
        } else {
            attempt = (normalizedDraft, normalizedDraft.savesAsMoment ? UUID() : nil)
            pendingStatusAttempt = attempt
        }

        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await service.setStatus(
                attempt.draft,
                tonightExpiresAt: attempt.draft.expiration.tonightExpiresAt(
                    from: now(),
                    calendar: calendar
                ),
                momentClientID: attempt.momentID
            )
            pendingStatusAttempt = nil
            await refresh()
            statusMessage = normalizedDraft.savesAsMoment
                ? "狀態已更新，也留成一個 Moment。"
                : "狀態已更新。"
            return true
        } catch {
            statusMessage = "狀態尚未更新，請確認連線後再試。"
            return false
        }
    }

    @discardableResult
    func clearStatus() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await service.clearStatus()
            pendingStatusAttempt = nil
            await refresh()
            statusMessage = "目前狀態已清除。"
            return true
        } catch {
            statusMessage = "狀態尚未清除，請確認連線後再試。"
            return false
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

    private func scheduleExpirationRefresh(for request: LifecycleRequest) {
        expirationTask?.cancel()
        let dates = [snapshot?.currentStatus?.expiresAt, snapshot?.partnerStatus?.expiresAt]
            .compactMap { $0 }
            .filter { $0 > now() }
        guard let nextExpiration = dates.min() else {
            expirationTask = nil
            return
        }
        let delay = max(0, nextExpiration.timeIntervalSince(now()))
        expirationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled,
                  let self,
                  self.isCurrent(request) else { return }
            await self.refresh(for: request)
        }
    }

    private func apply(_ fetched: TogetherNowSnapshot, request: LifecycleRequest) {
        guard isCurrent(request) else { return }
        snapshot = TogetherNowSnapshot(
            currentUserID: fetched.currentUserID,
            partnerUserID: fetched.partnerUserID,
            currentDisplayName: fetched.currentDisplayName,
            partnerDisplayName: fetched.partnerDisplayName,
            privatePartnerName: fetched.privatePartnerName,
            currentStatus: fetched.currentStatus?.isActive(at: now()) == true
                ? fetched.currentStatus
                : nil,
            partnerStatus: fetched.partnerStatus?.isActive(at: now()) == true
                ? fetched.partnerStatus
                : nil
        )
        scheduleExpirationRefresh(for: request)
    }
}
