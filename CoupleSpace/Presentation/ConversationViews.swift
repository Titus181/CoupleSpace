import PhotosUI
import SwiftUI
import UIKit

struct ConversationView: View {
    @ObservedObject var model: ConversationModel
    @Binding private var focusMessageID: UUID?
    private let onMomentSaved: @MainActor () async -> Void
    @State private var draft = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var highlightedMessageID: UUID?
    @FocusState private var isComposerFocused: Bool

    init(
        model: ConversationModel,
        focusMessageID: Binding<UUID?> = .constant(nil),
        onMomentSaved: @escaping @MainActor () async -> Void = {}
    ) {
        self.model = model
        _focusMessageID = focusMessageID
        self.onMomentSaved = onMomentSaved
    }

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
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task { await sendSelectedPhoto(item) }
        }
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
                .onAppear {
                    if focusMessageID == nil {
                        scrollToLatest(using: proxy)
                    }
                }
                .onChange(of: model.messages.last?.id) { _, _ in
                    guard focusMessageID == nil else { return }
                    scrollToLatest(using: proxy)
                }
                .task(id: focusMessageID) {
                    guard let focusMessageID else { return }
                    await focus(on: focusMessageID, using: proxy)
                }
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
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.title3)
                        .frame(minWidth: 32, minHeight: 32)
                }
                .accessibilityLabel("傳送照片")
                .accessibilityIdentifier("send-conversation-photo")

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
                if highlightedMessageID == message.id {
                    Text("來源訊息")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityIdentifier("source-message-highlight")
                }
                messageBubble(message, isCurrentUser: isCurrentUser)
                if let reaction = message.reaction {
                    Text(reaction.emoji.symbol)
                        .font(.title3)
                        .accessibilityLabel(reaction.emoji.accessibilityLabel)
                        .accessibilityIdentifier("conversation-reaction")
                }
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if isCurrentUser { deliveryStatus(for: message) }
            }
            if !isCurrentUser { Spacer(minLength: 52) }
        }
        .padding(4)
        .background(
            highlightedMessageID == message.id ? Color.accentColor.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 18)
        )
        .contextMenu {
            if model.canReact(to: message) {
                ForEach(MomentEmoji.allCases, id: \.self) { emoji in
                    Button {
                        Task { await model.react(to: message, with: emoji) }
                    } label: {
                        Label(emoji.accessibilityLabel, systemImage: "face.smiling")
                    }
                }
            }
            if model.canSaveAsMoment(message) {
                Button {
                    Task {
                        guard await model.saveAsMoment(message) else { return }
                        await onMomentSaved()
                    }
                } label: {
                    Label("收藏為 Moment", systemImage: "sparkles")
                }
            }
        }
        .accessibilityIdentifier("conversation-message-\(message.id.uuidString.lowercased())")
        .accessibilityValue(deliveryAccessibilityValue(for: message))
    }

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage, isCurrentUser: Bool) -> some View {
        switch message.content {
        case let .text(body):
            Text(body)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .foregroundStyle(isCurrentUser ? Color.white : Color.primary)
                .background(
                    isCurrentUser ? Color.accentColor : Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 16)
                )
        case .photo:
            Group {
                if let data = model.photoDataByMessageID[message.id],
                   let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .allowsHitTesting(false)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(.quaternary)
                        ProgressView()
                    }
                    .frame(height: 160)
                }
            }
            .frame(maxWidth: 260)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .task(id: message.id) { await model.loadPhoto(for: message) }
            .accessibilityLabel("聊天照片")
            .accessibilityIdentifier("conversation-photo")
        }
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
        if highlightedMessageID == message.id { return "來源訊息" }
        guard message.senderUserID == model.currentUserID else { return "" }
        switch message.deliveryState {
        case .sending: return "傳送中"
        case .failed: return "傳送失敗"
        case .synced: return "已同步"
        }
    }

    private func sendDraft() {
        guard let value = ChatTextPolicy.normalizedBody(draft) else { return }
        Task {
            guard await model.send(value) else { return }
            if ChatTextPolicy.normalizedBody(draft) == value { draft = "" }
        }
    }

    private func sendSelectedPhoto(_ item: PhotosPickerItem) async {
        defer { selectedPhotoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let prepared = try? PhotoAssetProcessor.prepare(data) else { return }
        _ = await model.sendPhoto(prepared.fullData)
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let lastID = model.messages.last?.id else { return }
        proxy.scrollTo(lastID, anchor: .bottom)
    }

    private func focus(on messageID: UUID, using proxy: ScrollViewProxy) async {
        guard await model.ensureMessageAvailable(id: messageID) else {
            focusMessageID = nil
            return
        }
        await Task.yield()
        withAnimation { proxy.scrollTo(messageID, anchor: .center) }
        highlightedMessageID = messageID
        focusMessageID = nil
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if highlightedMessageID == messageID { highlightedMessageID = nil }
        }
    }
}
