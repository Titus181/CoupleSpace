import Combine
import Foundation

@MainActor
final class ConversationModel: ObservableObject {
    private struct LifecycleRequest {
        let generation: Int
        let requiresActiveModel: Bool
    }

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var unreadCount = 0
    @Published private(set) var currentUserID: UUID?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMoreMessages = false
    @Published private(set) var isSending = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var photoDataByMessageID: [UUID: Data] = [:]
    @Published private(set) var activeReactionMessageIDs: Set<UUID> = []
    @Published private(set) var savedMomentMessageIDs: Set<UUID> = []
    @Published private(set) var focusedSourceMessageID: UUID?
    @Published private(set) var unreadRefreshGeneration = 0

    private struct ReactionAttempt {
        let emojiValue: String?
        let clientID: UUID?
        let previous: ChatMessageReaction?
    }

    private let service: ConversationRemoteServing
    private var hasStarted = false
    private var lifecycleGeneration = 0
    private var activeLifecycleWorkByGeneration: [Int: Int] = [:]
    private var lifecycleWorkWaitersByGeneration: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var observationTransitionTask: Task<Bool, Never>?
    private var isConversationVisible = false
    private var conversationVisibilityGeneration = 0
    private var scheduledDrain: Task<Void, Never>?
    private var scheduledDrainID: UUID?
    private var pendingReactionAttempts: [UUID: ReactionAttempt] = [:]
    private var pendingMomentIDs: [UUID: UUID] = [:]
    private var terminalDeliveryMessage: String?
    private var didLoadOlderMessages = false
    private let pageSize = 50

    init(service: ConversationRemoteServing) {
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
        await loadCachedMessages(for: request)
        guard isCurrent(request) else { return }
        await loadPendingMessages(for: request)
        guard isCurrent(request) else { return }
        loadCachedPhotos()
        await refresh(for: request)
        guard isCurrent(request) else { return }
        let isObserving = await startObservation(for: request)
        guard isCurrent(request) else { return }
        let terminalRejectionMessage = await drainPendingMessages(
            maximumAttemptsPerMessage: ConversationRecoveryRetryPolicy.maximumAttempts,
            request: request
        )
        guard isCurrent(request) else { return }
        await refresh(for: request)
        guard isCurrent(request) else { return }
        if let terminalRejectionMessage {
            terminalDeliveryMessage = terminalRejectionMessage
            statusMessage = terminalRejectionMessage
        } else if !isObserving {
            statusMessage = "即時同步暫時無法連線；恢復網路後會再連線。"
        }
    }

    func stop() async {
        let endingGeneration = lifecycleGeneration
        setConversationVisible(false)
        hasStarted = false
        lifecycleGeneration &+= 1
        scheduledDrain?.cancel()
        scheduledDrain = nil
        scheduledDrainID = nil
        await stopObservation()
        await waitForLifecycleWork(generation: endingGeneration)
    }

    func setConversationVisible(_ isVisible: Bool) {
        guard isConversationVisible != isVisible else { return }
        isConversationVisible = isVisible
        conversationVisibilityGeneration &+= 1
    }

    func markVisibleMessagesRead() async {
        await markVisibleMessagesReadIfNeeded()
    }

    func clearAllRelationshipUnreadForDebug() async {
        do {
            try await service.markAllRelationshipInteractionsRead()
            unreadRefreshGeneration &+= 1
        } catch {
            statusMessage = "無法清除未讀，請確認連線後再試。"
        }
    }

    func refresh() async {
        guard let request = lifecycleRequestAllowingInitialExplicitWork() else { return }
        await refresh(for: request)
    }

    private func refresh(for request: LifecycleRequest) async {
        while isLoadingMore {
            guard isCurrent(request) else { return }
            await Task.yield()
        }
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
            let page = try await service.fetchPage(before: nil, limit: pageSize)
            guard isCurrent(request) else { return }
            let snapshot = page.snapshot
            currentUserID = snapshot.currentUserID
            let unresolvedMessages = messages.filter { $0.deliveryState != .synced }
            mergeRemoteMessages(snapshot.messages, unresolvedMessages: unresolvedMessages)
            if !didLoadOlderMessages { hasMoreMessages = page.hasMore }
            applyPendingReactionAttempts()
            unreadCount = snapshot.unreadCount
            let refreshedMessageIDs = Set(snapshot.messages.map(\.id))
            savedMomentMessageIDs.subtract(refreshedMessageIDs)
            savedMomentMessageIDs.formUnion(snapshot.savedMomentMessageIDs)
            statusMessage = terminalDeliveryMessage
            loadCachedPhotos()
            if isConversationVisible { await markVisibleMessagesReadIfNeeded() }
            guard isCurrent(request) else { return }
            await persistCurrentSnapshot()
        } catch {
            guard isCurrent(request) else { return }
            statusMessage = "無法更新對話，請稍後再試。"
        }
    }

    @discardableResult
    func loadMoreMessages() async -> Bool {
        guard !isLoading, !isLoadingMore, hasMoreMessages,
              let oldest = messages.first(where: { $0.deliveryState == .synced }) else {
            return false
        }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await service.fetchPage(
                before: ConversationPageCursor(
                    createdAt: oldest.createdAt,
                    clientID: oldest.id
                ),
                limit: pageSize
            )
            mergeRemoteMessages(page.snapshot.messages, unresolvedMessages: [])
            let refreshedMessageIDs = Set(page.snapshot.messages.map(\.id))
            savedMomentMessageIDs.subtract(refreshedMessageIDs)
            savedMomentMessageIDs.formUnion(page.snapshot.savedMomentMessageIDs)
            hasMoreMessages = page.hasMore
            didLoadOlderMessages = true
            statusMessage = terminalDeliveryMessage
            loadCachedPhotos()
            await persistCurrentSnapshot()
            return true
        } catch {
            statusMessage = "無法載入更早的訊息，請稍後再試。"
            return false
        }
    }

    @discardableResult
    func send(_ value: String) async -> Bool {
        guard let body = ChatTextPolicy.normalizedBody(value) else { return false }
        return await send(.text(body))
    }

    @discardableResult
    func sendPhoto(_ data: Data) async -> Bool {
        await send(.photo(data))
    }

    @discardableResult
    func send(_ draft: ChatMessageDraft) async -> Bool {
        guard let currentUserID else { return false }
        let clientID = UUID()
        let localCreatedAt = Date.now
        do {
            try await service.enqueueMessage(
                draft,
                clientID: clientID,
                localCreatedAt: localCreatedAt
            )
        } catch {
            statusMessage = draft.isPhoto
                ? "無法保留待送照片，請確認裝置空間後再試。"
                : "無法保留待送訊息，請再試一次。"
            return false
        }
        let content: ChatMessageContent
        switch draft {
        case let .text(body): content = .text(body)
        case .photo: content = .photo
        }
        mergeMessages([ChatMessage(
            id: clientID,
            senderUserID: currentUserID,
            content: content,
            createdAt: localCreatedAt,
            deliveryState: .sending
        )])
        if case .photo = content, let data = service.cachedPhotoData(for: clientID) {
            photoDataByMessageID[clientID] = data
        }
        scheduleSingleDrainIfNeeded()
        return true
    }

    func waitForScheduledDelivery() async {
        await scheduledDrain?.value
    }

    func retryMessage(id: UUID) async {
        guard messages.contains(where: { $0.id == id && $0.deliveryState == .failed }) else {
            return
        }
        guard let request = activeLifecycleRequest() else { return }
        await drainPendingMessages(maximumAttemptsPerMessage: 1, request: request)
    }

    func recoverPendingMessages() async {
        guard let request = activeLifecycleRequest() else { return }
        await loadPendingMessages(for: request)
        guard isCurrent(request) else { return }
        loadCachedPhotos()
        await refresh(for: request)
        guard isCurrent(request) else { return }
        let isObserving = await startObservation(for: request)
        guard isCurrent(request) else { return }
        let terminalRejectionMessage = await drainPendingMessages(
            maximumAttemptsPerMessage: ConversationRecoveryRetryPolicy.maximumAttempts,
            request: request
        )
        guard isCurrent(request) else { return }
        await refresh(for: request)
        guard isCurrent(request) else { return }
        if let terminalRejectionMessage {
            terminalDeliveryMessage = terminalRejectionMessage
            statusMessage = terminalRejectionMessage
        } else if !isObserving {
            statusMessage = "即時同步暫時無法連線；恢復網路後會再連線。"
        }
    }

    func loadPhoto(for message: ChatMessage) async {
        guard case .photo = message.content, photoDataByMessageID[message.id] == nil else { return }
        if let cached = service.cachedPhotoData(for: message.id) {
            photoDataByMessageID[message.id] = cached
            return
        }
        do {
            photoDataByMessageID[message.id] = try await service.photoData(for: message.id)
        } catch {
            statusMessage = "照片暫時無法載入，請稍後再試。"
        }
    }

    func react(to message: ChatMessage, with emoji: MomentEmoji) async {
        await react(to: message, withEmoji: emoji.rawValue)
    }

    func react(to message: ChatMessage, withEmoji value: String) async {
        guard let emojiValue = ChatReactionPolicy.normalizedEmojiValue(value) else { return }
        guard canReact(to: message),
              !activeReactionMessageIDs.contains(message.id),
              let currentUserID else { return }
        activeReactionMessageIDs.insert(message.id)
        defer { activeReactionMessageIDs.remove(message.id) }

        let previous = message.reaction
        let removesReaction = previous?.emojiValue == emojiValue
        let targetEmojiValue: String? = removesReaction ? nil : emojiValue
        let attempt: ReactionAttempt
        if let pending = pendingReactionAttempts[message.id], pending.emojiValue == targetEmojiValue {
            attempt = pending
        } else {
            attempt = ReactionAttempt(
                emojiValue: targetEmojiValue,
                clientID: targetEmojiValue == nil ? nil : UUID(),
                previous: previous
            )
            pendingReactionAttempts[message.id] = attempt
        }

        if let targetEmojiValue, let clientID = attempt.clientID {
            replaceReaction(
                messageID: message.id,
                reaction: ChatMessageReaction(
                    id: clientID,
                    reactorUserID: currentUserID,
                    emojiValue: targetEmojiValue,
                    updatedAt: .now
                )
            )
            do {
                let reaction = try await service.setReaction(
                    messageID: message.id,
                    emojiValue: targetEmojiValue,
                    clientID: clientID
                )
                pendingReactionAttempts[message.id] = nil
                replaceReaction(messageID: message.id, reaction: reaction)
                await persistCurrentSnapshot()
            } catch {
                replaceReaction(messageID: message.id, reaction: attempt.previous)
                statusMessage = "Emoji 回應尚未送出，請稍後再試。"
            }
        } else {
            replaceReaction(messageID: message.id, reaction: nil)
            do {
                try await service.removeReaction(messageID: message.id)
                pendingReactionAttempts[message.id] = nil
                await persistCurrentSnapshot()
            } catch {
                replaceReaction(messageID: message.id, reaction: attempt.previous)
                statusMessage = "Emoji 回應尚未移除，請稍後再試。"
            }
        }
    }

    func canReact(to message: ChatMessage) -> Bool {
        message.deliveryState == .synced && message.senderUserID != currentUserID
    }

    func canSaveAsMoment(_ message: ChatMessage) -> Bool {
        message.deliveryState == .synced && !savedMomentMessageIDs.contains(message.id)
    }

    @discardableResult
    func saveAsMoment(_ message: ChatMessage) async -> Bool {
        guard canSaveAsMoment(message) else { return false }
        let momentClientID = pendingMomentIDs[message.id] ?? UUID()
        pendingMomentIDs[message.id] = momentClientID
        do {
            _ = try await service.saveAsMoment(
                messageID: message.id,
                momentClientID: momentClientID
            )
            pendingMomentIDs[message.id] = nil
            savedMomentMessageIDs.insert(message.id)
            statusMessage = "已留在你們的共同時間線。"
            await persistCurrentSnapshot()
            return true
        } catch {
            statusMessage = "尚未收藏為 Moment，請確認連線後再試。"
            return false
        }
    }

    func ensureMessageAvailable(id: UUID) async -> Bool {
        if messages.contains(where: { $0.id == id }) { return true }
        await refresh()
        if messages.contains(where: { $0.id == id }) { return true }
        while hasMoreMessages {
            guard await loadMoreMessages() else { break }
            if messages.contains(where: { $0.id == id }) { return true }
        }
        statusMessage = "連線後可查看原對話。"
        return false
    }

    @discardableResult
    func focusSourceMessage(id: UUID) async -> Bool {
        guard await ensureMessageAvailable(id: id) else { return false }
        focusedSourceMessageID = id
        return true
    }

    private func markVisibleMessagesReadIfNeeded() async {
        guard isConversationVisible,
              unreadCount > 0,
              let lastMessageID = messages.last(where: { $0.deliveryState == .synced })?.id else {
            return
        }
        let visibilityGeneration = conversationVisibilityGeneration
        do {
            try await service.markRead(through: lastMessageID)
            guard isConversationVisible,
                  visibilityGeneration == conversationVisibilityGeneration,
                  messages.last(where: { $0.deliveryState == .synced })?.id == lastMessageID
            else { return }
            unreadCount = 0
            unreadRefreshGeneration &+= 1
            await persistCurrentSnapshot()
        } catch {
            guard isConversationVisible,
                  visibilityGeneration == conversationVisibilityGeneration else { return }
            statusMessage = "未讀數尚未更新，請稍後再試。"
        }
    }

    private func scheduleSingleDrainIfNeeded() {
        guard scheduledDrain == nil,
              let request = activeLifecycleRequest() else { return }
        let drainID = UUID()
        scheduledDrainID = drainID
        scheduledDrain = Task { [weak self] in
            guard let self else { return }
            _ = await self.drainPendingMessages(
                maximumAttemptsPerMessage: 1,
                request: request
            )
            guard self.scheduledDrainID == drainID else { return }
            self.scheduledDrain = nil
            self.scheduledDrainID = nil
        }
    }

    private func updateMessage(
        id: UUID,
        createdAt: Date? = nil,
        deliveryState: ChatMessageDeliveryState
    ) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let existing = messages[index]
        messages[index] = ChatMessage(
            id: existing.id,
            senderUserID: existing.senderUserID,
            content: existing.content,
            createdAt: createdAt ?? existing.createdAt,
            deliveryState: deliveryState,
            reaction: existing.reaction
        )
        messages.sort(by: Self.messageOrder)
    }

    private func loadPendingMessages(for request: LifecycleRequest) async {
        do {
            let pending = try await service.fetchPendingSnapshot()
            guard isCurrent(request) else { return }
            currentUserID = pending.currentUserID
            mergeMessages(pending.messages)
        } catch {
            guard isCurrent(request) else { return }
            statusMessage = "無法讀取待送訊息，請稍後再試。"
        }
    }

    private func loadCachedMessages(for request: LifecycleRequest) async {
        do {
            guard let cached = try await service.fetchCachedSnapshot() else { return }
            guard isCurrent(request) else { return }
            currentUserID = cached.currentUserID
            unreadCount = cached.unreadCount
            mergeMessages(cached.messages)
        } catch {
            guard isCurrent(request) else { return }
            statusMessage = "無法讀取最近對話，請稍後再試。"
        }
    }

    @discardableResult
    private func drainPendingMessages(
        maximumAttemptsPerMessage: Int,
        request: LifecycleRequest
    ) async -> String? {
        while isSending {
            guard isCurrent(request) else { return nil }
            await Task.yield()
        }
        guard isCurrent(request) else { return nil }
        beginLifecycleWork(for: request)
        isSending = true
        defer {
            isSending = false
            endLifecycleWork(for: request)
        }
        var terminalRejectionMessage: String?

        while isCurrent(request) {
            var attempt = 0
            var resolvedCurrentMessage = false
            while attempt < maximumAttemptsPerMessage {
                let pendingMessage: ChatMessage
                do {
                    guard let next = try await service.beginNextPendingMessage() else {
                        return terminalRejectionMessage
                    }
                    pendingMessage = next
                    guard isCurrent(request) else { return terminalRejectionMessage }
                    mergeMessages([pendingMessage])
                } catch {
                    guard isCurrent(request) else { return terminalRejectionMessage }
                    statusMessage = "無法讀取待送訊息，請稍後再試。"
                    return terminalRejectionMessage
                }

                do {
                    let result = try await service.deliverPendingMessage(pendingMessage)
                    try await service.acknowledgePendingMessage(clientID: pendingMessage.id)
                    guard isCurrent(request) else { return terminalRejectionMessage }
                    switch result {
                    case let .accepted(acceptedAt):
                        updateMessage(
                            id: pendingMessage.id,
                            createdAt: acceptedAt,
                            deliveryState: .synced
                        )
                    case let .rejected(message):
                        messages.removeAll { $0.id == pendingMessage.id }
                        photoDataByMessageID[pendingMessage.id] = nil
                        statusMessage = message
                        terminalDeliveryMessage = message
                        terminalRejectionMessage = message
                    }
                    await persistCurrentSnapshot()
                    guard isCurrent(request) else { return terminalRejectionMessage }
                    resolvedCurrentMessage = true
                    break
                } catch {
                    guard isCurrent(request) else { return terminalRejectionMessage }
                    attempt += 1
                    markUnresolvedMessagesFailed()
                    guard attempt < maximumAttemptsPerMessage,
                          let delay = ConversationRecoveryRetryPolicy.delayNanoseconds(
                              afterAttempt: attempt
                          ) else { return terminalRejectionMessage }
                    do {
                        try await Task.sleep(nanoseconds: delay)
                    } catch {
                        return terminalRejectionMessage
                    }
                    guard isCurrent(request) else { return terminalRejectionMessage }
                }
            }
            if !resolvedCurrentMessage { return terminalRejectionMessage }
        }
        return terminalRejectionMessage
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

    private func markUnresolvedMessagesFailed() {
        guard let currentUserID else { return }
        messages = messages.map { message in
            guard message.senderUserID == currentUserID,
                  message.deliveryState != .synced else { return message }
            return ChatMessage(
                id: message.id,
                senderUserID: message.senderUserID,
                content: message.content,
                createdAt: message.createdAt,
                deliveryState: .failed,
                reaction: message.reaction
            )
        }
    }

    private func mergeMessages(_ incoming: [ChatMessage]) {
        var messagesByID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for message in incoming {
            if let existing = messagesByID[message.id], existing.deliveryState == .synced {
                continue
            }
            messagesByID[message.id] = message
        }
        messages = messagesByID.values.sorted(by: Self.messageOrder)
    }

    private func mergeRemoteMessages(
        _ remoteMessages: [ChatMessage],
        unresolvedMessages: [ChatMessage]
    ) {
        var messagesByID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for message in remoteMessages { messagesByID[message.id] = message }
        let remoteIDs = Set(remoteMessages.map(\.id))
        for message in unresolvedMessages where !remoteIDs.contains(message.id) {
            messagesByID[message.id] = message
        }
        messages = messagesByID.values.sorted(by: Self.messageOrder)
    }

    private func replaceReaction(messageID: UUID, reaction: ChatMessageReaction?) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].reaction = reaction
    }

    private func applyPendingReactionAttempts() {
        guard let currentUserID else { return }
        for (messageID, attempt) in pendingReactionAttempts
        where activeReactionMessageIDs.contains(messageID) {
            let reaction = attempt.emojiValue.flatMap { emojiValue in
                attempt.clientID.map {
                    ChatMessageReaction(
                        id: $0,
                        reactorUserID: currentUserID,
                        emojiValue: emojiValue,
                        updatedAt: .now
                    )
                }
            }
            replaceReaction(messageID: messageID, reaction: reaction)
        }
    }

    private func loadCachedPhotos() {
        for message in messages where photoDataByMessageID[message.id] == nil {
            guard case .photo = message.content,
                  let data = service.cachedPhotoData(for: message.id) else { continue }
            photoDataByMessageID[message.id] = data
        }
    }

    private func persistCurrentSnapshot() async {
        guard let currentUserID else { return }
        await service.persistCachedSnapshot(ConversationSnapshot(
            currentUserID: currentUserID,
            messages: messages,
            unreadCount: unreadCount,
            savedMomentMessageIDs: savedMomentMessageIDs
        ))
    }

    private static func messageOrder(_ lhs: ChatMessage, _ rhs: ChatMessage) -> Bool {
        (lhs.createdAt, lhs.id.uuidString) < (rhs.createdAt, rhs.id.uuidString)
    }
}

private extension ChatMessageDraft {
    var isPhoto: Bool {
        if case .photo = self { return true }
        return false
    }
}
