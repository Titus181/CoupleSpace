import SwiftUI

struct ConversationView: View {
    @ObservedObject var model: ConversationModel
    @State private var draft = ""
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                conversationContent
                    .contentShape(Rectangle())
                    .onTapGesture { isComposerFocused = false }
                Divider()
                composer
            }
            .navigationTitle("對話")
        }
        .accessibilityIdentifier("conversation-screen")
    }

    @ViewBuilder
    private var conversationContent: some View {
        if model.isLoading && model.messages.isEmpty {
            ProgressView("正在更新對話…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.messages.isEmpty {
            ContentUnavailableView(
                "兩人的對話",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("傳一則訊息，延續今天想說的話。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear { scrollToLatest(using: proxy) }
                .onChange(of: model.messages) { _, _ in scrollToLatest(using: proxy) }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let statusMessage = model.statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("conversation-status")
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("寫訊息…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .focused($isComposerFocused)
                    .accessibilityIdentifier("conversation-input")
                Button {
                    sendDraft()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(ChatTextPolicy.normalizedBody(draft) == nil)
                .accessibilityLabel("傳送")
                .accessibilityIdentifier("send-conversation-message")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func messageRow(_ message: ChatMessage) -> some View {
        let isCurrentUser = message.senderUserID == model.currentUserID
        return HStack {
            if isCurrentUser { Spacer(minLength: 52) }
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                Text(message.body)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .foregroundStyle(isCurrentUser ? Color.white : Color.primary)
                    .background(
                        isCurrentUser ? Color.accentColor : Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if isCurrentUser {
                    deliveryStatus(for: message)
                }
            }
            if !isCurrentUser { Spacer(minLength: 52) }
        }
        .accessibilityIdentifier("conversation-message-\(message.id.uuidString.lowercased())")
        .accessibilityValue(deliveryAccessibilityValue(for: message))
    }

    @ViewBuilder
    private func deliveryStatus(for message: ChatMessage) -> some View {
        switch message.deliveryState {
        case .sending:
            Text("傳送中")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .failed:
            Button("傳送失敗，點此重試") {
                Task { await model.retryMessage(id: message.id) }
            }
            .font(.caption2)
            .foregroundStyle(.red)
            .accessibilityIdentifier("retry-conversation-message")
        case .synced:
            EmptyView()
        }
    }

    private func deliveryAccessibilityValue(for message: ChatMessage) -> String {
        guard message.senderUserID == model.currentUserID else { return "" }
        switch message.deliveryState {
        case .sending:
            return "傳送中"
        case .failed:
            return "傳送失敗"
        case .synced:
            return "已同步"
        }
    }

    private func sendDraft() {
        guard let value = ChatTextPolicy.normalizedBody(draft) else { return }
        Task {
            guard await model.send(value) else { return }
            if ChatTextPolicy.normalizedBody(draft) == value {
                draft = ""
            }
        }
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let lastID = model.messages.last?.id else { return }
        proxy.scrollTo(lastID, anchor: .bottom)
    }
}
