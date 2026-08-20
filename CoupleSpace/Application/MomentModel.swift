import Combine
import Foundation

@MainActor
final class MomentModel: ObservableObject {
    private struct LifecycleRequest {
        let generation: Int
        let requiresActiveModel: Bool
    }

    @Published private(set) var moments: [Moment] = []
    @Published private(set) var photoDataByMomentID: [UUID: Data] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMoreMoments = false
    @Published private(set) var isSaving = false
    @Published private(set) var activeInteractionMomentIDs: Set<UUID> = []
    @Published private(set) var activeLifecycleMomentIDs: Set<UUID> = []
    @Published private(set) var recentlyDeletedMoments: [RecentlyDeletedMoment] = []
    @Published private(set) var isLoadingRecentlyDeleted = false
    @Published private(set) var hiddenMomentSourceMessageIDs: Set<UUID> = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var currentUserID: UUID?

    private let service: MomentRemoteServing
    private var hasStarted = false
    private var lifecycleGeneration = 0
    private var activeLifecycleWorkByGeneration: [Int: Int] = [:]
    private var lifecycleWorkWaitersByGeneration: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var observationTransitionTask: Task<Bool, Never>?
    private var pendingResponseAttempts: [UUID: (draft: MomentResponseDraft, clientID: UUID)] = [:]
    private var optimisticResponses: [UUID: MomentResponse] = [:]
    private var pendingAnswerAttempts: [UUID: (answer: String, clientID: UUID)] = [:]
    private var pendingQuestionAttempt: (draft: MomentQuestionDraft, momentID: UUID, answerID: UUID)?
    private var pendingOperationIDs: [MomentOperationIdentity: UUID] = [:]
    private var activePhotoMomentIDs: Set<UUID> = []
    private var hasLoadedOlderPages = false
    private var paginationCursor: MomentPageCursor?
    private var convergenceGeneration = 0
    private var explicitlyHiddenMomentIDs: Set<UUID> = []
    private var isFetchingRecentlyDeleted = false
    private let pageSize = 50

    init(service: MomentRemoteServing) {
        self.service = service
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        lifecycleGeneration &+= 1
        let request = LifecycleRequest(
            generation: lifecycleGeneration,
            requiresActiveModel: true
        )
        do {
            let userID = try await service.currentUserID()
            guard isCurrent(request) else { return }
            currentUserID = userID
        } catch {
            guard isCurrent(request) else { return }
            statusMessage = "無法確認 Moment 留下者，請稍後再試。"
        }
        guard isCurrent(request) else { return }
        if let cached = service.cachedMoments() {
            moments = cached
            loadCachedPhotos()
        }
        let isObserving = await startObservation(for: request)
        guard isCurrent(request) else { return }
        await refresh(for: request)
        if !isObserving, isCurrent(request), statusMessage == nil {
            statusMessage = "即時同步暫時無法連線；重新開啟畫面時會再讀取。"
        }
    }

    func authorLabel(for moment: Moment, names: TogetherNowSnapshot?) -> String {
        guard let currentUserID else { return "留下者未確認" }
        let label = names?.participantLabel(for: moment.creatorUserID)
            ?? (moment.creatorUserID == currentUserID ? "我" : "伴侶")
        return "\(label)留下的"
    }

    func response(for moment: Moment) -> MomentResponse? {
        moment.responses.first
    }

    func responseLabel(for response: MomentResponse, names: TogetherNowSnapshot?) -> String {
        guard let currentUserID else { return "回應者未確認" }
        let label = names?.participantPossessiveLabel(for: response.responderUserID)
            ?? (response.responderUserID == currentUserID ? "我的" : "伴侶的")
        return "\(label)回應"
    }

    func currentUserHasAnswered(_ moment: Moment) -> Bool {
        guard let currentUserID else { return false }
        return moment.questionAnswers.contains { $0.answererUserID == currentUserID }
    }

    func answerLabel(for answer: MomentQuestionAnswer, names: TogetherNowSnapshot?) -> String {
        guard let currentUserID else { return "留下者未確認" }
        let label = names?.participantPossessiveLabel(for: answer.answererUserID)
            ?? (answer.answererUserID == currentUserID ? "我的" : "伴侶的")
        return "\(label)回答"
    }

    func stop() async {
        let endingGeneration = lifecycleGeneration
        hasStarted = false
        lifecycleGeneration &+= 1
        await stopObservation()
        await waitForLifecycleWork(generation: endingGeneration)
    }

    func refresh() async {
        guard let request = lifecycleRequestAllowingInitialExplicitWork() else { return }
        await refresh(for: request)
    }

    private func refresh(for request: LifecycleRequest) async {
        while isLoading || isLoadingMore {
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
            while isCurrent(request) {
                let startingConvergenceGeneration = convergenceGeneration
                async let pageRequest = service.fetchMomentsPage(before: nil, limit: pageSize)
                async let hintsRequest = service.fetchMomentSyncHints()
                let (page, hints) = try await (pageRequest, hintsRequest)
                let pageIDs = Set(page.moments.map(\.id))
                guard isCurrent(request) else { return }
                guard convergenceGeneration == startingConvergenceGeneration else {
                    evictExplicitlyHiddenMomentData()
                    continue
                }
                let explicitDeletedHints = hints.filter(\.isDeleted)
                pruneMoments(explicitDeletedHints.map {
                    (id: $0.momentID, sourceMessageID: $0.sourceMessageID)
                })
                guard pageIDs.isDisjoint(with: Set(explicitDeletedHints.map(\.momentID))) else {
                    continue
                }
                let hydrationConvergenceGeneration = convergenceGeneration
                var refreshedHintMoments: [Moment] = []
                var unavailableLiveHints: [MomentSyncHint] = []
                var liveHydrationError: Error?
                for hint in hints where !hint.isDeleted && !pageIDs.contains(hint.momentID) {
                    do {
                        if let moment = try await service.fetchMoment(id: hint.momentID) {
                            refreshedHintMoments.append(moment)
                        } else {
                            unavailableLiveHints.append(hint)
                        }
                    } catch {
                        liveHydrationError = error
                    }
                }
                guard isCurrent(request) else { return }
                guard convergenceGeneration == hydrationConvergenceGeneration else {
                    evictExplicitlyHiddenMomentData()
                    continue
                }
                pruneMoments(unavailableLiveHints.map {
                    (id: $0.momentID, sourceMessageID: $0.sourceMessageID)
                })
                if let liveHydrationError {
                    throw liveHydrationError
                }
                let deletedHints = explicitDeletedHints + unavailableLiveHints
                let deletedHintIDs = Set(deletedHints.map(\.momentID))
                let unavailableLiveHintIDs = Set(unavailableLiveHints.map(\.momentID))
                for hint in hints where !hint.isDeleted
                    && !unavailableLiveHintIDs.contains(hint.momentID)
                {
                    explicitlyHiddenMomentIDs.remove(hint.momentID)
                }
                explicitlyHiddenMomentIDs.formUnion(deletedHintIDs)
                let hiddenIDs = explicitlyHiddenMomentIDs
                let previousHasMore = hasMoreMoments
                let previousCursor = paginationCursor
                for hiddenMoment in moments where hiddenIDs.contains(hiddenMoment.id) {
                    if let sourceMessageID = hiddenMoment.sourceMessageID {
                        hiddenMomentSourceMessageIDs.insert(sourceMessageID)
                    }
                }
                for hint in deletedHints {
                    if let sourceMessageID = hint.sourceMessageID {
                        hiddenMomentSourceMessageIDs.insert(sourceMessageID)
                    }
                    service.removeCachedMomentData(for: hint.momentID)
                }
                let visiblePageMoments = page.moments.filter { !hiddenIDs.contains($0.id) }
                let visibleHintMoments = refreshedHintMoments.filter {
                    !hiddenIDs.contains($0.id)
                }
                for liveMoment in visiblePageMoments + visibleHintMoments {
                    if let sourceMessageID = liveMoment.sourceMessageID {
                        hiddenMomentSourceMessageIDs.remove(sourceMessageID)
                    }
                }
                let visibleMoments = moments.filter { !hiddenIDs.contains($0.id) }
                if hasLoadedOlderPages, page.hasMore {
                    moments = merge(visiblePageMoments, with: visibleMoments)
                    hasMoreMoments = previousHasMore
                    paginationCursor = previousCursor
                } else {
                    moments = visiblePageMoments
                    hasLoadedOlderPages = false
                    hasMoreMoments = page.hasMore
                    paginationCursor = page.moments.last.map {
                        MomentPageCursor(createdAt: $0.createdAt, clientID: $0.id)
                    }
                }
                for moment in visibleHintMoments {
                    upsert(
                        moment,
                        invalidatingInFlightReads: false,
                        committingAcceptedState: false
                    )
                }
                prunePhotoData(to: Set(moments.map(\.id)))
                mergeOptimisticResponses()
                commitAcceptedMoments()
                statusMessage = nil
                return
            }
        } catch {
            guard isCurrent(request) else { return }
            statusMessage = "無法更新 Moment，請稍後再試。"
        }
    }

    func loadMoreMoments() async {
        guard !isLoading, !isLoadingMore, hasMoreMoments, paginationCursor != nil else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            while hasMoreMoments, let paginationCursor {
                let startingConvergenceGeneration = convergenceGeneration
                let page = try await service.fetchMomentsPage(
                    before: paginationCursor,
                    limit: pageSize
                )
                guard convergenceGeneration == startingConvergenceGeneration else {
                    evictExplicitlyHiddenMomentData()
                    continue
                }
                let visiblePageMoments = page.moments.filter {
                    !explicitlyHiddenMomentIDs.contains($0.id)
                }
                moments = merge(moments, with: visiblePageMoments)
                hasLoadedOlderPages = true
                hasMoreMoments = page.hasMore
                if let oldestLoadedMoment = page.moments.last {
                    self.paginationCursor = MomentPageCursor(
                        createdAt: oldestLoadedMoment.createdAt,
                        clientID: oldestLoadedMoment.id
                    )
                }
                commitAcceptedMoments()
                statusMessage = nil
                return
            }
        } catch {
            statusMessage = "無法載入更早的 Moment，請稍後再試。"
        }
    }

    @discardableResult
    func create(_ draft: MomentDraft) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let clientID = UUID()
            let startingConvergenceGeneration = convergenceGeneration
            let moment = try await service.createMoment(draft, clientID: clientID)
            guard convergenceGeneration == startingConvergenceGeneration else {
                await reconcileMomentWithDurableHint(clientID)
                commitCreatedPhotoIfVisible(draft, momentID: clientID)
                statusMessage = "Moment 狀態已在其他裝置更新。"
                return true
            }
            upsert(moment)
            commitCreatedPhotoIfVisible(draft, momentID: moment.id)
            statusMessage = "已留在你們的共同時間線。"
            return true
        } catch {
            statusMessage = "Moment 尚未送出，請確認連線後再試。"
            return false
        }
    }

    @discardableResult
    func createQuestion(_ draft: MomentQuestionDraft) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }

        let attempt: (draft: MomentQuestionDraft, momentID: UUID, answerID: UUID)
        if let pendingQuestionAttempt, pendingQuestionAttempt.draft == draft {
            attempt = pendingQuestionAttempt
        } else {
            attempt = (draft, UUID(), UUID())
            pendingQuestionAttempt = attempt
        }

        do {
            let startingConvergenceGeneration = convergenceGeneration
            let moment = try await service.createQuestion(
                draft,
                momentClientID: attempt.momentID,
                answerClientID: attempt.answerID
            )
            pendingQuestionAttempt = nil
            guard convergenceGeneration == startingConvergenceGeneration else {
                await reconcileMomentWithDurableHint(attempt.momentID)
                statusMessage = "題目狀態已在其他裝置更新。"
                return true
            }
            upsert(moment)
            statusMessage = "題目已留在你們的共同時間線。"
            return true
        } catch {
            statusMessage = "題目尚未送出，請確認連線後再試。"
            return false
        }
    }

    @discardableResult
    func respond(to moment: Moment, with draft: MomentResponseDraft) async -> Bool {
        guard !activeInteractionMomentIDs.contains(moment.id),
              let currentUserID,
              let content = responseContent(for: draft)
        else { return false }
        activeInteractionMomentIDs.insert(moment.id)
        defer { activeInteractionMomentIDs.remove(moment.id) }

        let attempt: (draft: MomentResponseDraft, clientID: UUID)
        if let pending = pendingResponseAttempts[moment.id], pending.draft == draft {
            attempt = pending
        } else {
            attempt = (draft, UUID())
            pendingResponseAttempts[moment.id] = attempt
        }
        let optimisticResponse = MomentResponse(
            id: attempt.clientID,
            responderUserID: currentUserID,
            content: content,
            createdAt: .now
        )
        optimisticResponses[moment.id] = optimisticResponse
        replaceResponse(in: moment.id, with: optimisticResponse)
        do {
            let startingConvergenceGeneration = convergenceGeneration
            let response = try await service.createResponse(
                to: moment.id,
                draft: draft,
                clientID: attempt.clientID
            )
            pendingResponseAttempts[moment.id] = nil
            optimisticResponses[moment.id] = nil
            guard convergenceGeneration == startingConvergenceGeneration else {
                convergenceGeneration &+= 1
                removeResponse(id: attempt.clientID, from: moment.id)
                commitAcceptedMoments()
                await reconcileMomentWithDurableHint(moment.id)
                statusMessage = "Moment 狀態已在其他裝置更新。"
                return true
            }
            convergenceGeneration &+= 1
            replaceResponse(in: moment.id, with: response)
            commitAcceptedMoments()
            statusMessage = "已回應這個 Moment。"
            return true
        } catch {
            optimisticResponses[moment.id] = nil
            removeResponse(id: attempt.clientID, from: moment.id)
            statusMessage = "回應尚未送出，請確認連線後再試。"
            return false
        }
    }

    @discardableResult
    func answer(_ moment: Moment, text: String) async -> Bool {
        guard !activeInteractionMomentIDs.contains(moment.id) else { return false }
        activeInteractionMomentIDs.insert(moment.id)
        defer { activeInteractionMomentIDs.remove(moment.id) }

        guard let normalizedAnswer = MomentQuestionPolicy.normalizedAnswer(text) else {
            statusMessage = "回答內容不完整。"
            return false
        }
        let attempt: (answer: String, clientID: UUID)
        if let pending = pendingAnswerAttempts[moment.id], pending.answer == normalizedAnswer {
            attempt = pending
        } else {
            attempt = (normalizedAnswer, UUID())
            pendingAnswerAttempts[moment.id] = attempt
        }
        do {
            let startingConvergenceGeneration = convergenceGeneration
            _ = try await service.answerQuestion(
                momentID: moment.id,
                answer: normalizedAnswer,
                clientID: attempt.clientID
            )
            pendingAnswerAttempts[moment.id] = nil
            if convergenceGeneration != startingConvergenceGeneration {
                await reconcileMomentWithDurableHint(moment.id)
                statusMessage = "Moment 狀態已在其他裝置更新。"
                return true
            }
            convergenceGeneration &+= 1
            await refresh()
            statusMessage = "回答已送出；雙方完成後會一起揭曉。"
            return true
        } catch {
            statusMessage = "回答尚未送出，請確認連線後再試。"
            return false
        }
    }

    func loadRecentlyDeletedMoments() async {
        guard !isFetchingRecentlyDeleted else { return }
        isFetchingRecentlyDeleted = true
        isLoadingRecentlyDeleted = true
        defer {
            isLoadingRecentlyDeleted = false
            isFetchingRecentlyDeleted = false
        }
        do {
            recentlyDeletedMoments = try await fetchConvergedRecentlyDeletedMoments()
            statusMessage = nil
        } catch {
            statusMessage = "無法讀取最近刪除，請稍後再試。"
        }
    }

    @discardableResult
    func delete(_ moment: Moment) async -> Bool {
        guard currentUserID == moment.creatorUserID,
              !activeLifecycleMomentIDs.contains(moment.id)
        else { return false }
        activeLifecycleMomentIDs.insert(moment.id)
        defer { activeLifecycleMomentIDs.remove(moment.id) }

        let key = MomentOperationIdentity.deleteMoment(moment.id)
        do {
            let operationID = try operationID(for: key)
            let startingConvergenceGeneration = convergenceGeneration
            let deleted = try await service.deleteMoment(id: moment.id, operationID: operationID)
            clearOperationID(for: key)
            guard convergenceGeneration == startingConvergenceGeneration else {
                pruneMoment(id: moment.id)
                await reconcileMomentWithDurableHint(
                    moment.id,
                    requiresExplicitLiveHint: true
                )
                statusMessage = "Moment 狀態已在其他裝置更新。"
                return true
            }
            pruneMoment(id: moment.id)
            recentlyDeletedMoments.removeAll { $0.id == deleted.id }
            recentlyDeletedMoments.insert(deleted, at: 0)
            statusMessage = "已移到最近刪除，可在 30 天內復原。"
            return true
        } catch MomentServiceError.operationSuperseded {
            clearOperationID(for: key)
            await refresh()
            await reloadRecentlyDeletedSilently()
            statusMessage = "Moment 狀態已在其他裝置更新。"
            return false
        } catch {
            statusMessage = "Moment 尚未刪除，請確認連線後再試。"
            return false
        }
    }

    @discardableResult
    func restore(_ deleted: RecentlyDeletedMoment) async -> Bool {
        guard !activeLifecycleMomentIDs.contains(deleted.id) else { return false }
        activeLifecycleMomentIDs.insert(deleted.id)
        defer { activeLifecycleMomentIDs.remove(deleted.id) }

        let key = MomentOperationIdentity.restoreMoment(deleted.id)
        do {
            let operationID = try operationID(for: key)
            let startingConvergenceGeneration = convergenceGeneration
            let moment = try await service.restoreMoment(
                id: deleted.id,
                operationID: operationID
            )
            clearOperationID(for: key)
            guard convergenceGeneration == startingConvergenceGeneration else {
                await reconcileMomentWithDurableHint(
                    deleted.id,
                    requiresExplicitLiveHint: true
                )
                statusMessage = "Moment 狀態已在其他裝置更新。"
                return true
            }
            recentlyDeletedMoments.removeAll { $0.id == deleted.id }
            upsert(moment)
            if case .photo = moment.content {
                await loadPhotoIfNeeded(moment)
            }
            statusMessage = "Moment 已復原。"
            return true
        } catch MomentServiceError.operationSuperseded {
            clearOperationID(for: key)
            await refresh()
            await reloadRecentlyDeletedSilently()
            statusMessage = "Moment 狀態已在其他裝置更新。"
            return false
        } catch {
            statusMessage = "無法復原這筆 Moment；可能已超過期限或關係狀態已變更。"
            return false
        }
    }

    @discardableResult
    func removeOwnResponse(from moment: Moment, response: MomentResponse) async -> Bool {
        guard response.responderUserID == currentUserID,
              !activeInteractionMomentIDs.contains(moment.id)
        else { return false }
        activeInteractionMomentIDs.insert(moment.id)
        defer { activeInteractionMomentIDs.remove(moment.id) }

        let key = MomentOperationIdentity.removeResponse(
            momentID: moment.id,
            responseID: response.id
        )
        do {
            let operationID = try operationID(for: key)
            let startingConvergenceGeneration = convergenceGeneration
            let updated = try await service.removeResponse(
                momentID: moment.id,
                responseID: response.id,
                operationID: operationID
            )
            clearOperationID(for: key)
            guard convergenceGeneration == startingConvergenceGeneration else {
                if updated != nil {
                    convergenceGeneration &+= 1
                    removeResponse(id: response.id, from: moment.id)
                    commitAcceptedMoments()
                } else {
                    pruneMoment(id: moment.id)
                }
                await reconcileMomentWithDurableHint(
                    moment.id,
                    requiresExplicitLiveHint: true
                )
                statusMessage = "Moment 狀態已在其他裝置更新。"
                return true
            }
            if let updated {
                upsert(updated)
            } else {
                pruneMoment(id: moment.id)
                await refresh()
                await reloadRecentlyDeletedSilently()
            }
            statusMessage = "已移除你的回應。"
            return true
        } catch {
            statusMessage = "回應尚未移除，請確認連線後再試。"
            return false
        }
    }

    @discardableResult
    func removeOwnAnswer(from moment: Moment, answer: MomentQuestionAnswer) async -> Bool {
        guard answer.answererUserID == currentUserID,
              !answer.isRemoved,
              !activeInteractionMomentIDs.contains(moment.id)
        else { return false }
        activeInteractionMomentIDs.insert(moment.id)
        defer { activeInteractionMomentIDs.remove(moment.id) }

        let key = MomentOperationIdentity.removeAnswer(
            momentID: moment.id,
            answerID: answer.id
        )
        do {
            let operationID = try operationID(for: key)
            let startingConvergenceGeneration = convergenceGeneration
            let updated = try await service.removeAnswer(
                momentID: moment.id,
                answerID: answer.id,
                operationID: operationID
            )
            clearOperationID(for: key)
            guard convergenceGeneration == startingConvergenceGeneration else {
                if let updated {
                    mergeRemovedAnswerMarker(
                        from: updated,
                        answerID: answer.id,
                        into: moment.id
                    )
                } else {
                    pruneMoment(id: moment.id)
                }
                await reconcileMomentWithDurableHint(
                    moment.id,
                    requiresExplicitLiveHint: true
                )
                statusMessage = "Moment 狀態已在其他裝置更新。"
                return true
            }
            if let updated {
                upsert(updated)
            } else {
                pruneMoment(id: moment.id)
                await refresh()
                await reloadRecentlyDeletedSilently()
            }
            statusMessage = "已移除你的回答內容。"
            return true
        } catch {
            statusMessage = "回答尚未移除，請確認連線後再試。"
            return false
        }
    }

    func loadPhotoIfNeeded(_ moment: Moment) async {
        guard case .photo = moment.content,
              photoDataByMomentID[moment.id] == nil,
              !activePhotoMomentIDs.contains(moment.id)
        else { return }

        activePhotoMomentIDs.insert(moment.id)
        defer { activePhotoMomentIDs.remove(moment.id) }
        let requestLifecycleGeneration = lifecycleGeneration
        if let data = try? await service.photoData(for: moment) {
            guard requestLifecycleGeneration == lifecycleGeneration,
                  moments.contains(where: { $0.id == moment.id }),
                  !explicitlyHiddenMomentIDs.contains(moment.id)
            else {
                service.removeCachedMomentData(for: moment.id)
                return
            }
            photoDataByMomentID[moment.id] = data
        }
    }

    private func loadCachedPhotos() {
        for moment in moments {
            guard case .photo = moment.content,
                  let data = service.cachedPhotoData(for: moment.id)
            else { continue }
            photoDataByMomentID[moment.id] = data
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
                try await self.service.startObservingChanges { [weak self] change in
                    guard let self, self.isCurrent(request) else { return }
                    await self.handleRemoteChange(change, for: request)
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

    private func responseContent(for draft: MomentResponseDraft) -> MomentResponseContent? {
        switch draft {
        case let .emoji(emoji):
            return .emoji(emoji)
        case let .text(value):
            guard let value = MomentResponsePolicy.normalizedText(value) else { return nil }
            return .text(value)
        }
    }

    private func handleRemoteChange(_ change: MomentRemoteChange, for request: LifecycleRequest) async {
        switch change {
        case .reloadFirstPage:
            convergenceGeneration &+= 1
            await refresh(for: request)
        case let .momentDeleted(momentID):
            pruneMoment(id: momentID)
            await reconcileMomentWithDurableHint(
                momentID,
                for: request,
                requiresExplicitLiveHint: true
            )
        case let .momentChanged(momentID):
            convergenceGeneration &+= 1
            await reconcileMomentWithDurableHint(momentID, for: request)
        }
    }

    private func reconcileMomentWithDurableHint(
        _ momentID: UUID,
        for request: LifecycleRequest? = nil,
        requiresExplicitLiveHint: Bool = false
    ) async {
        do {
            while request.map(isCurrent) ?? true {
                let startingConvergenceGeneration = convergenceGeneration
                let hint = try await service.fetchMomentSyncHints()
                    .first { $0.momentID == momentID }
                let latestMoment = hint?.isDeleted == true
                    || (requiresExplicitLiveHint && hint == nil)
                    ? nil
                    : try await service.fetchMoment(id: momentID)
                if let request, !isCurrent(request) { return }
                guard convergenceGeneration == startingConvergenceGeneration else {
                    continue
                }
                if let hint, hint.isDeleted {
                    pruneMoment(id: momentID, sourceMessageID: hint.sourceMessageID)
                } else if requiresExplicitLiveHint, hint == nil {
                    // A delete Broadcast hides fail-closed unless durable truth explicitly says live.
                } else if let latestMoment {
                    upsert(latestMoment)
                } else {
                    pruneMoment(id: momentID, sourceMessageID: hint?.sourceMessageID)
                }
                await reloadRecentlyDeletedSilently()
                return
            }
        } catch {
            if let request, !isCurrent(request) { return }
            statusMessage = "即時同步尚未完成；下次更新會再重試。"
        }
    }

    private func reloadRecentlyDeletedSilently() async {
        guard !isFetchingRecentlyDeleted else { return }
        isFetchingRecentlyDeleted = true
        defer { isFetchingRecentlyDeleted = false }
        do {
            recentlyDeletedMoments = try await fetchConvergedRecentlyDeletedMoments()
        } catch {
            // The active timeline remains authoritative even if this secondary list cannot reload.
        }
    }

    private func fetchConvergedRecentlyDeletedMoments() async throws
        -> [RecentlyDeletedMoment]
    {
        while true {
            let startingConvergenceGeneration = convergenceGeneration
            let deleted = try await service.fetchRecentlyDeletedMoments()
                .sorted { $0.deletedAt > $1.deletedAt }
            guard convergenceGeneration == startingConvergenceGeneration else { continue }
            return deleted
        }
    }

    private func operationID(for key: MomentOperationIdentity) throws -> UUID {
        if let existing = pendingOperationIDs[key] { return existing }
        let persisted = try service.operationID(for: key)
        pendingOperationIDs[key] = persisted
        return persisted
    }

    private func clearOperationID(for key: MomentOperationIdentity) {
        pendingOperationIDs[key] = nil
        service.clearOperationID(for: key)
    }

    private func upsert(
        _ moment: Moment,
        invalidatingInFlightReads: Bool = true,
        committingAcceptedState: Bool = true
    ) {
        if invalidatingInFlightReads {
            convergenceGeneration &+= 1
        }
        explicitlyHiddenMomentIDs.remove(moment.id)
        if let sourceMessageID = moment.sourceMessageID {
            hiddenMomentSourceMessageIDs.remove(sourceMessageID)
        }
        moments.removeAll { $0.id == moment.id }
        moments.append(moment)
        moments.sort {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString > $1.id.uuidString
        }
        if committingAcceptedState {
            commitAcceptedMoments()
        }
    }

    private func pruneMoment(id: UUID, sourceMessageID hintedSourceMessageID: UUID? = nil) {
        pruneMoments([(id: id, sourceMessageID: hintedSourceMessageID)])
    }

    private func pruneMoments(_ targets: [(id: UUID, sourceMessageID: UUID?)]) {
        guard !targets.isEmpty else { return }
        let targetIDs = Set(targets.map(\.id))
        var hintedSourceByID: [UUID: UUID] = [:]
        for target in targets {
            if let sourceMessageID = target.sourceMessageID {
                hintedSourceByID[target.id] = sourceMessageID
            }
        }
        convergenceGeneration &+= 1
        explicitlyHiddenMomentIDs.formUnion(targetIDs)
        for id in targetIDs {
            if let sourceMessageID = hintedSourceByID[id]
                ?? moments.first(where: { $0.id == id })?.sourceMessageID
            {
                hiddenMomentSourceMessageIDs.insert(sourceMessageID)
            }
            photoDataByMomentID[id] = nil
            optimisticResponses[id] = nil
            pendingResponseAttempts[id] = nil
            service.removeCachedMomentData(for: id)
        }
        moments.removeAll { targetIDs.contains($0.id) }
        commitAcceptedMoments()
    }

    private func evictExplicitlyHiddenMomentData() {
        for momentID in explicitlyHiddenMomentIDs {
            service.removeCachedMomentData(for: momentID)
        }
    }

    private func prunePhotoData(to visibleMomentIDs: Set<UUID>) {
        photoDataByMomentID = photoDataByMomentID.filter { visibleMomentIDs.contains($0.key) }
    }

    private func replaceResponse(in momentID: UUID, with response: MomentResponse) {
        guard let index = moments.firstIndex(where: { $0.id == momentID }) else { return }
        moments[index].responses.removeAll { $0.id == response.id }
        moments[index].responses.append(response)
    }

    private func removeResponse(id: UUID, from momentID: UUID) {
        guard let index = moments.firstIndex(where: { $0.id == momentID }) else { return }
        moments[index].responses.removeAll { $0.id == id }
    }

    private func mergeRemovedAnswerMarker(
        from updated: Moment,
        answerID: UUID,
        into momentID: UUID
    ) {
        guard let marker = updated.questionAnswers.first(where: {
            $0.id == answerID && $0.isRemoved
        }), let momentIndex = moments.firstIndex(where: { $0.id == momentID })
        else {
            pruneMoment(id: momentID)
            return
        }
        convergenceGeneration &+= 1
        moments[momentIndex].questionAnswers.removeAll { $0.id == answerID }
        moments[momentIndex].questionAnswers.append(marker)
        commitAcceptedMoments()
    }

    private func mergeOptimisticResponses() {
        for (momentID, response) in optimisticResponses {
            guard let index = moments.firstIndex(where: { $0.id == momentID }),
                  !moments[index].responses.contains(where: { $0.id == response.id })
            else { continue }
            moments[index].responses.append(response)
        }
    }

    private func commitAcceptedMoments() {
        var acceptedMoments = moments
        for (momentID, response) in optimisticResponses {
            guard let index = acceptedMoments.firstIndex(where: { $0.id == momentID }) else {
                continue
            }
            acceptedMoments[index].responses.removeAll { $0.id == response.id }
        }
        service.commitAcceptedMoments(acceptedMoments)
    }

    private func commitCreatedPhotoIfVisible(_ draft: MomentDraft, momentID: UUID) {
        guard case let .photo(data) = draft,
              moments.contains(where: { $0.id == momentID }),
              !explicitlyHiddenMomentIDs.contains(momentID)
        else { return }
        service.commitAcceptedPhotoData(data, for: momentID)
        photoDataByMomentID[momentID] = data
    }

    private func merge(_ first: [Moment], with second: [Moment]) -> [Moment] {
        var byID = Dictionary(uniqueKeysWithValues: second.map { ($0.id, $0) })
        for moment in first { byID[moment.id] = moment }
        return byID.values.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString > $1.id.uuidString
        }
    }

}
