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

    private let service: ConversationRemoteServing
    private var hasStarted = false
    private var isConversationVisible = false
    private var refreshRequested = false
    private var scheduledDrain: Task<Void, Never>?

    init(service: ConversationRemoteServing) {
        self.service = service
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await loadCachedMessages()
        await loadPendingMessages()
        await refresh()
        let isObserving = await restartObservation()
        _ = await drainPendingMessages(
            maximumAttemptsPerMessage: ConversationRecoveryRetryPolicy.maximumAttempts
        )
        await refresh()
        if !isObserving {
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
        if isVisible {
            await markVisibleMessagesReadIfNeeded()
        }
    }

    func refresh() async {
        if isLoading {
            refreshRequested = true
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
                unreadCount = snapshot.unreadCount
                statusMessage = nil
                if isConversationVisible {
                    await markVisibleMessagesReadIfNeeded()
                }
            } catch {
                statusMessage = "無法更新對話，請稍後再試。"
            }
            isLoading = false
        } while refreshRequested && hasStarted
    }

    @discardableResult
    func send(_ value: String) async -> Bool {
        guard let body = ChatTextPolicy.normalizedBody(value) else { return false }
        guard let currentUserID else { return false }
        let clientID = UUID()
        let localCreatedAt = Date.now
        do {
            try await service.enqueueMessage(
                body: body,
                clientID: clientID,
                localCreatedAt: localCreatedAt
            )
        } catch {
            statusMessage = "無法保留待送訊息，請再試一次。"
            return false
        }
        mergeMessages([ChatMessage(
            id: clientID,
            senderUserID: currentUserID,
            body: body,
            createdAt: localCreatedAt,
            deliveryState: .sending
        )])
        if scheduledDrain == nil {
            scheduledDrain = Task { [weak self] in
                guard let self else { return }
                _ = await self.drainPendingMessages(maximumAttemptsPerMessage: 1)
                self.scheduledDrain = nil
            }
        }
        return true
    }

    func waitForScheduledDelivery() async {
        await scheduledDrain?.value
    }

    func retryMessage(id: UUID) async {
        guard messages.contains(where: { $0.id == id && $0.deliveryState == .failed }) else { return }
        await drainPendingMessages(maximumAttemptsPerMessage: 1)
    }

    func recoverPendingMessages() async {
        await loadPendingMessages()
        let isObserving = await restartObservation()
        _ = await drainPendingMessages(
            maximumAttemptsPerMessage: ConversationRecoveryRetryPolicy.maximumAttempts
        )
        await refresh()
        if !isObserving {
            statusMessage = "即時同步暫時無法連線；恢復網路後會再連線。"
        }
    }

    private func markVisibleMessagesReadIfNeeded() async {
        guard unreadCount > 0, let lastMessageID = messages.last?.id else { return }
        do {
            try await service.markRead(through: lastMessageID)
            unreadCount = 0
            await persistCurrentSnapshot()
        } catch {
            statusMessage = "未讀數尚未更新，請稍後再試。"
        }
    }

    private func updateMessage(
        id: UUID,
        createdAt: Date? = nil,
        deliveryState: ChatMessageDeliveryState
    ) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index] = ChatMessage(
            id: messages[index].id,
            senderUserID: messages[index].senderUserID,
            body: messages[index].body,
            createdAt: createdAt ?? messages[index].createdAt,
            deliveryState: deliveryState
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
    private func drainPendingMessages(maximumAttemptsPerMessage: Int) async -> Bool {
        guard !isSending else { return true }
        isSending = true
        defer { isSending = false }

        while hasStarted {
            var attempt = 0
            var sentCurrentMessage = false

            while attempt < maximumAttemptsPerMessage {
                let pendingMessage: ChatMessage
                do {
                    guard let next = try await service.beginNextPendingMessage() else {
                        return true
                    }
                    pendingMessage = next
                    mergeMessages([pendingMessage])
                } catch {
                    statusMessage = "無法讀取待送訊息，請稍後再試。"
                    return false
                }

                do {
                    let acceptedAt = try await service.sendMessage(
                        body: pendingMessage.body,
                        clientID: pendingMessage.id
                    )
                    try await service.acknowledgePendingMessage(clientID: pendingMessage.id)
                    updateMessage(
                        id: pendingMessage.id,
                        createdAt: acceptedAt,
                        deliveryState: .synced
                    )
                    await persistCurrentSnapshot()
                    sentCurrentMessage = true
                    break
                } catch {
                    attempt += 1
                    markUnresolvedMessagesFailed()
                    guard attempt < maximumAttemptsPerMessage,
                          let delay = ConversationRecoveryRetryPolicy.delayNanoseconds(
                              afterAttempt: attempt
                          )
                    else {
                        return false
                    }
                    do {
                        try await Task.sleep(nanoseconds: delay)
                    } catch {
                        return false
                    }
                    guard hasStarted else { return false }
                }
            }

            if !sentCurrentMessage {
                return false
            }
        }
        return false
    }

    private func restartObservation() async -> Bool {
        do {
            try await service.startObservingChanges { [weak self] in
                await self?.refresh()
            }
            return true
        } catch {
            return false
        }
    }

    private func markUnresolvedMessagesFailed() {
        guard let currentUserID else { return }
        messages = messages.map { message in
            guard message.senderUserID == currentUserID,
                  message.deliveryState != .synced
            else { return message }
            return ChatMessage(
                id: message.id,
                senderUserID: message.senderUserID,
                body: message.body,
                createdAt: message.createdAt,
                deliveryState: .failed
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
