import Combine
import Foundation

@MainActor
final class ConversationModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var unreadCount = 0
    @Published private(set) var currentUserID: UUID?
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var photoDataByMessageID: [UUID: Data] = [:]
    @Published private(set) var activeReactionMessageIDs: Set<UUID> = []
    @Published private(set) var savedMomentMessageIDs: Set<UUID> = []

    private struct ReactionAttempt {
        let emojiValue: String?
        let clientID: UUID?
        let previous: ChatMessageReaction?
    }

    private let service: ConversationRemoteServing
    private var hasStarted = false
    private var isConversationVisible = false
    private var refreshRequested = false
    private var scheduledDrain: Task<Void, Never>?
    private var pendingReactionAttempts: [UUID: ReactionAttempt] = [:]
    private var pendingMomentIDs: [UUID: UUID] = [:]
    private var terminalDeliveryMessage: String?

    init(service: ConversationRemoteServing) {
        self.service = service
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await loadCachedMessages()
        await loadPendingMessages()
        loadCachedPhotos()
        await refresh()
        let isObserving = await restartObservation()
        let terminalRejectionMessage = await drainPendingMessages(
            maximumAttemptsPerMessage: ConversationRecoveryRetryPolicy.maximumAttempts
        )
        await refresh()
        if let terminalRejectionMessage {
            terminalDeliveryMessage = terminalRejectionMessage
            statusMessage = terminalRejectionMessage
        } else if !isObserving {
            statusMessage = "即時同步暫時無法連線；恢復網路後會再連線。"
        }
    }

    func stop() async {
        hasStarted = false
        scheduledDrain?.cancel()
        scheduledDrain = nil
        await service.stopObservingChanges()
    }

    func setConversationVisible(_ isVisible: Bool) async {
        isConversationVisible = isVisible
        if isVisible { await markVisibleMessagesReadIfNeeded() }
    }

    func refresh() async {
        if isLoading {
            refreshRequested = true
            while isLoading { await Task.yield() }
            return
        }
        repeat {
            refreshRequested = false
            isLoading = true
            do {
                let snapshot = try await service.fetchSnapshot()
                currentUserID = snapshot.currentUserID
                let unresolvedMessages = messages.filter { $0.deliveryState != .synced }
                let remoteIDs = Set(snapshot.messages.map(\.id))
                messages = (snapshot.messages + unresolvedMessages.filter { !remoteIDs.contains($0.id) })
                    .sorted(by: Self.messageOrder)
                applyPendingReactionAttempts()
                unreadCount = snapshot.unreadCount
                statusMessage = terminalDeliveryMessage
                loadCachedPhotos()
                if isConversationVisible { await markVisibleMessagesReadIfNeeded() }
            } catch {
                statusMessage = "無法更新對話，請稍後再試。"
            }
            isLoading = false
        } while refreshRequested && hasStarted
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
        await drainPendingMessages(maximumAttemptsPerMessage: 1)
    }

    func recoverPendingMessages() async {
        await loadPendingMessages()
        loadCachedPhotos()
        let isObserving = await restartObservation()
        let terminalRejectionMessage = await drainPendingMessages(
            maximumAttemptsPerMessage: ConversationRecoveryRetryPolicy.maximumAttempts
        )
        await refresh()
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
        statusMessage = "連線後可查看原對話。"
        return false
    }

    private func markVisibleMessagesReadIfNeeded() async {
        guard unreadCount > 0,
              let lastMessageID = messages.last(where: { $0.deliveryState == .synced })?.id else {
            return
        }
        do {
            try await service.markRead(through: lastMessageID)
            unreadCount = 0
            await persistCurrentSnapshot()
        } catch {
            statusMessage = "未讀數尚未更新，請稍後再試。"
        }
    }

    private func scheduleSingleDrainIfNeeded() {
        guard scheduledDrain == nil else { return }
        scheduledDrain = Task { [weak self] in
            guard let self else { return }
            _ = await self.drainPendingMessages(maximumAttemptsPerMessage: 1)
            self.scheduledDrain = nil
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

    private func loadPendingMessages() async {
        do {
            let pending = try await service.fetchPendingSnapshot()
            currentUserID = pending.currentUserID
            mergeMessages(pending.messages)
        } catch {
            statusMessage = "無法讀取待送訊息，請稍後再試。"
        }
    }

    private func loadCachedMessages() async {
        do {
            guard let cached = try await service.fetchCachedSnapshot() else { return }
            currentUserID = cached.currentUserID
            unreadCount = cached.unreadCount
            mergeMessages(cached.messages)
        } catch {
            statusMessage = "無法讀取最近對話，請稍後再試。"
        }
    }

    @discardableResult
    private func drainPendingMessages(maximumAttemptsPerMessage: Int) async -> String? {
        guard !isSending else { return nil }
        isSending = true
        defer { isSending = false }
        var terminalRejectionMessage: String?

        while hasStarted {
            var attempt = 0
            var resolvedCurrentMessage = false
            while attempt < maximumAttemptsPerMessage {
                let pendingMessage: ChatMessage
                do {
                    guard let next = try await service.beginNextPendingMessage() else {
                        return terminalRejectionMessage
                    }
                    pendingMessage = next
                    mergeMessages([pendingMessage])
                } catch {
                    statusMessage = "無法讀取待送訊息，請稍後再試。"
                    return terminalRejectionMessage
                }

                do {
                    let result = try await service.deliverPendingMessage(pendingMessage)
                    try await service.acknowledgePendingMessage(clientID: pendingMessage.id)
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
                    resolvedCurrentMessage = true
                    break
                } catch {
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
                    guard hasStarted else { return terminalRejectionMessage }
                }
            }
            if !resolvedCurrentMessage { return terminalRejectionMessage }
        }
        return terminalRejectionMessage
    }

    private func restartObservation() async -> Bool {
        do {
            try await service.startObservingChanges { [weak self] in await self?.refresh() }
            return true
        } catch {
            return false
        }
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
            unreadCount: unreadCount
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
