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

    init(service: ConversationRemoteServing) {
        self.service = service
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
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
        await service.stopObservingChanges()
    }

    func setConversationVisible(_ isVisible: Bool) async {
        isConversationVisible = isVisible
        if isVisible {
            await markVisibleMessagesReadIfNeeded()
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
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
    }

    @discardableResult
    func send(_ value: String) async -> Bool {
        guard !isSending, let body = ChatTextPolicy.normalizedBody(value) else { return false }
        guard let currentUserID else { return false }
        let clientID = UUID()
        messages.append(ChatMessage(
            id: clientID,
            senderUserID: currentUserID,
            body: body,
            createdAt: .now,
            deliveryState: .sending
        ))

        isSending = true
        defer { isSending = false }
        do {
            let acceptedAt = try await service.sendMessage(body: body, clientID: clientID)
            updateMessage(id: clientID, createdAt: acceptedAt, deliveryState: .synced)
            return true
        } catch {
            updateMessage(id: clientID, deliveryState: .failed)
            return false
        }
    }

    func retryMessage(id: UUID) async {
        guard !isSending,
              let message = messages.first(where: { $0.id == id && $0.deliveryState == .failed })
        else { return }

        updateMessage(id: id, deliveryState: .sending)
        isSending = true
        defer { isSending = false }
        do {
            let acceptedAt = try await service.sendMessage(body: message.body, clientID: id)
            updateMessage(id: id, createdAt: acceptedAt, deliveryState: .synced)
        } catch {
            updateMessage(id: id, deliveryState: .failed)
        }
    }

    private func markVisibleMessagesReadIfNeeded() async {
        guard unreadCount > 0, let lastMessageID = messages.last?.id else { return }
        do {
            try await service.markRead(through: lastMessageID)
            unreadCount = 0
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

    private static func messageOrder(_ lhs: ChatMessage, _ rhs: ChatMessage) -> Bool {
        (lhs.createdAt, lhs.id.uuidString) < (rhs.createdAt, rhs.id.uuidString)
    }
}
