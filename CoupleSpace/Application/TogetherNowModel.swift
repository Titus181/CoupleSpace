import Combine
import Foundation

@MainActor
final class TogetherNowModel: ObservableObject {
    @Published private(set) var snapshot: TogetherNowSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var statusMessage: String?

    private let service: TogetherNowRemoteServing
    private let now: () -> Date
    private let calendar: Calendar
    private var hasStarted = false
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
        if let cached = service.cachedSnapshot() {
            apply(cached)
        }
        await refresh()
        do {
            try await service.startObservingChanges { [weak self] in
                await self?.refresh()
            }
        } catch {
            statusMessage = "即時同步暫時無法連線；重新開啟畫面時會再讀取。"
        }
    }

    func stop() async {
        hasStarted = false
        expirationTask?.cancel()
        expirationTask = nil
        await service.stopObservingChanges()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await service.fetchSnapshot()
            apply(fetched)
            statusMessage = nil
        } catch {
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

    private func scheduleExpirationRefresh() {
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
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func apply(_ fetched: TogetherNowSnapshot) {
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
        scheduleExpirationRefresh()
    }
}
