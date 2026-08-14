import PhotosUI
import SwiftUI
import UIKit

private struct AppointmentComposerSeed: Identifiable {
    let id = UUID()
    let title: String
    let sourceMessageID: UUID?

    init(title: String = "", sourceMessageID: UUID? = nil) {
        self.title = title
        self.sourceMessageID = sourceMessageID
    }
}

private struct RecentAppointmentDiscussionEntry: Identifiable {
    let appointment: SharedAppointment
    let summary: SharedAppointmentDiscussionSummary

    var id: UUID { summary.id }
}

private enum ConversationTimelineItemID: Hashable {
    case message(UUID)
    case appointment(UUID)
}

private enum ConversationTimelineItem: Identifiable {
    case message(ChatMessage)
    case appointment(SharedAppointment)

    var id: ConversationTimelineItemID {
        switch self {
        case let .message(message): .message(message.id)
        case let .appointment(appointment): .appointment(appointment.id)
        }
    }

    var createdAt: Date {
        switch self {
        case let .message(message): message.createdAt
        case let .appointment(appointment): appointment.createdAt
        }
    }

    private var stableOrderKey: String {
        switch id {
        case let .message(id): "message-\(id.uuidString)"
        case let .appointment(id): "appointment-\(id.uuidString)"
        }
    }

    static func ordered(
        messages: [ChatMessage],
        appointments: [SharedAppointment]
    ) -> [ConversationTimelineItem] {
        (messages.map(Self.message) + appointments.map(Self.appointment))
            .sorted { lhs, rhs in
                (lhs.createdAt, lhs.stableOrderKey) < (rhs.createdAt, rhs.stableOrderKey)
            }
    }
}

enum ConversationPresentationMode: Equatable {
    case main
    case appointmentDiscussion

    var navigationTitle: String {
        switch self {
        case .main: "對話"
        case .appointmentDiscussion: "專屬討論"
        }
    }

    var showsAppointmentFeatures: Bool { self == .main }
    var allowsMomentSaving: Bool { self == .main }
}

struct ConversationView: View {
    @ObservedObject var model: ConversationModel
    @ObservedObject var sharedAppointmentModel: SharedAppointmentModel
    @Binding private var focusMessageID: UUID?
    private let savedMomentSourceIDs: Set<UUID>
    private let onMomentSaved: @MainActor () async -> Void
    private let mode: ConversationPresentationMode
    private let embedsNavigationStack: Bool
    private let allowsSending: Bool
    @State private var draft = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var previewedPhoto: ConversationPhotoPreview?
    @State private var actionMessageID: UUID?
    @State private var customEmojiMessage: ChatMessage?
    @State private var highlightedMessageID: UUID?
    @State private var appointmentComposerSeed: AppointmentComposerSeed?
    @FocusState private var isComposerFocused: Bool

    init(
        model: ConversationModel,
        sharedAppointmentModel: SharedAppointmentModel,
        focusMessageID: Binding<UUID?> = .constant(nil),
        savedMomentSourceIDs: Set<UUID> = [],
        mode: ConversationPresentationMode = .main,
        embedsNavigationStack: Bool = true,
        allowsSending: Bool = true,
        onMomentSaved: @escaping @MainActor () async -> Void = {}
    ) {
        self.model = model
        self.sharedAppointmentModel = sharedAppointmentModel
        _focusMessageID = focusMessageID
        self.savedMomentSourceIDs = savedMomentSourceIDs
        self.mode = mode
        self.embedsNavigationStack = embedsNavigationStack
        self.allowsSending = allowsSending
        self.onMomentSaved = onMomentSaved
    }

    var body: some View {
        Group {
            if embedsNavigationStack {
                NavigationStack { conversationLayout }
                    .accessibilityIdentifier("conversation-screen")
            } else {
                conversationLayout
            }
        }
        .overlayPreferenceValue(ConversationMessageBoundsKey.self) { bounds in
            GeometryReader { proxy in
                if let message = actionMessage,
                   let anchor = bounds[message.id] {
                    focusedMessageActions(
                        for: message,
                        messageFrame: proxy[anchor],
                        containerSize: proxy.size
                    )
                    .transition(.opacity)
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: actionMessageID)
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task { await sendSelectedPhoto(item) }
        }
        .fullScreenCover(item: $previewedPhoto) { preview in
            ConversationPhotoPreviewView(preview: preview)
        }
        .sheet(item: $customEmojiMessage) { message in
            EmojiPickerView(
                accessibilityIdentifier: "conversation-emoji-picker",
                emojiIdentifierPrefix: "custom-conversation-emoji"
            ) { emoji in
                Task { await model.react(to: message, withEmoji: emoji) }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $appointmentComposerSeed) { seed in
            SharedAppointmentComposerView(
                model: sharedAppointmentModel,
                initialTitle: seed.title,
                sourceMessageID: seed.sourceMessageID
            )
        }
    }

    private var conversationLayout: some View {
        VStack(spacing: 0) {
            if mode == .main, !recentDiscussionEntries.isEmpty {
                recentAppointmentDiscussions
                Divider()
            }
            conversationContent
                .contentShape(Rectangle())
                .onTapGesture { isComposerFocused = false }
            Divider()
            if allowsSending {
                composer
            } else {
                Text("這筆約定已取消，討論內容仍會保留。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(.bar)
                    .accessibilityIdentifier("appointment-discussion-read-only")
            }
        }
        .navigationTitle(mode.navigationTitle)
    }

    private var recentDiscussionEntries: [RecentAppointmentDiscussionEntry] {
        let entries = sharedAppointmentModel.recentDiscussionSummaries.compactMap {
            summary -> RecentAppointmentDiscussionEntry? in
            guard let appointment = sharedAppointmentModel.appointment(id: summary.appointmentID),
                  appointment.deliveryState == .synced else { return nil }
            return RecentAppointmentDiscussionEntry(
                appointment: appointment,
                summary: summary
            )
        }
        return Array(entries.prefix(5))
    }

    private var recentAppointmentDiscussions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("近期約定討論")
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(recentDiscussionEntries) { entry in
                        NavigationLink {
                            if let discussionModel = sharedAppointmentModel.discussionModel(
                                for: entry.appointment.id
                            ) {
                                AppointmentDiscussionView(
                                    discussionModel: discussionModel,
                                    sharedAppointmentModel: sharedAppointmentModel,
                                    appointmentTitle: entry.appointment.title,
                                    allowsSending: entry.appointment.status == .scheduled
                                )
                            }
                        } label: {
                            recentDiscussionCard(
                                appointment: entry.appointment,
                                summary: entry.summary
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "recent-appointment-discussion-"
                                + entry.appointment.id.uuidString.lowercased()
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func recentDiscussionCard(
        appointment: SharedAppointment,
        summary: SharedAppointmentDiscussionSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.tint)
                Text(appointment.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if summary.unreadCount > 0 {
                    Text(summary.unreadCount.formatted())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor, in: Capsule())
                        .accessibilityLabel("未讀 \(summary.unreadCount) 則")
                }
            }

            HStack(spacing: 5) {
                Text("最新更新")
                Text(summary.latestActivityAt.formatted(date: .abbreviated, time: .shortened))
                if appointment.status == .cancelled {
                    Text("· 已取消")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(12)
        .frame(width: 238, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    @ViewBuilder
    private var conversationContent: some View {
        if (model.isLoading || sharedAppointmentModel.isLoading) && timelineItems.isEmpty {
            ProgressView("正在更新對話…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if timelineItems.isEmpty {
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
                        ForEach(timelineItems) { item in
                            timelineRow(item)
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
                .onChange(of: timelineItems.last?.id) { _, _ in
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

    @ViewBuilder
    private func timelineRow(_ item: ConversationTimelineItem) -> some View {
        switch item {
        case let .message(message):
            messageRow(message)
        case let .appointment(appointment):
            appointmentRow(appointment)
        }
    }

    @ViewBuilder
    private func appointmentRow(_ appointment: SharedAppointment) -> some View {
        if appointment.deliveryState == .synced {
            NavigationLink {
                SharedAppointmentDetailView(
                    appointmentID: appointment.id,
                    model: sharedAppointmentModel
                )
            } label: {
                conversationAppointmentCard(appointment)
            }
            .buttonStyle(.plain)
        } else {
            conversationAppointmentCard(appointment)
        }
    }

    private func conversationAppointmentCard(_ appointment: SharedAppointment) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label("共同約定", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer()
                if appointment.status == .cancelled {
                    Text("已取消")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(
                            "conversation-appointment-status-\(appointment.id.uuidString.lowercased())"
                        )
                }
            }

            Text(appointment.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(appointment.status == .cancelled ? .secondary : .primary)
                .strikethrough(appointment.status == .cancelled)

            Label(
                appointment.startsAt.formatted(date: .abbreviated, time: .shortened),
                systemImage: "clock"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let location = appointment.location {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            switch appointment.deliveryState {
            case .sending:
                Text("等待同步")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed:
                Button("同步失敗，點此重試") {
                    Task { await sharedAppointmentModel.retryAppointment(id: appointment.id) }
                }
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("retry-conversation-appointment")
            case .synced:
                Label("查看約定詳情", systemImage: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "conversation-appointment-card-\(appointment.id.uuidString.lowercased())"
        )
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
                if mode.showsAppointmentFeatures {
                    Button {
                        appointmentComposerSeed = AppointmentComposerSeed()
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .frame(minWidth: 32, minHeight: 32)
                    }
                    .accessibilityLabel("建立共同約定")
                    .accessibilityIdentifier("create-appointment-from-composer")
                }

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
                VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                    if highlightedMessageID == message.id {
                        Text("來源訊息")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint)
                            .accessibilityIdentifier("source-message-highlight")
                    }
                    messageBubble(message, isCurrentUser: isCurrentUser)
                    if isSavedAsMoment(message) {
                        Label("已收藏為 Moment", systemImage: "sparkles")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("conversation-saved-moment")
                    }
                    if let reaction = message.reaction {
                        Text(reaction.symbol)
                            .font(.title3)
                            .accessibilityLabel(reaction.accessibilityLabel)
                            .accessibilityIdentifier("conversation-reaction")
                    }
                }
                .anchorPreference(key: ConversationMessageBoundsKey.self, value: .bounds) {
                    [message.id: $0]
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
        .onLongPressGesture(minimumDuration: 0.45) {
            guard model.canReact(to: message)
                    || (canSaveAsMoment(message) && !isSavedAsMoment(message))
                    || canCreateAppointment(from: message) else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)
            actionMessageID = message.id
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
                        .contentShape(Rectangle())
                        .onTapGesture {
                            previewedPhoto = ConversationPhotoPreview(
                                messageID: message.id,
                                image: image
                            )
                        }
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

    private func isSavedAsMoment(_ message: ChatMessage) -> Bool {
        savedMomentSourceIDs.contains(message.id) || model.savedMomentMessageIDs.contains(message.id)
    }

    private var actionMessage: ChatMessage? {
        guard let actionMessageID else { return nil }
        return model.messages.first { $0.id == actionMessageID }
    }

    private var timelineItems: [ConversationTimelineItem] {
        ConversationTimelineItem.ordered(
            messages: model.messages,
            appointments: mode.showsAppointmentFeatures
                ? sharedAppointmentModel.appointments
                : []
        )
    }

    @ViewBuilder
    private func focusedMessageActions(
        for message: ChatMessage,
        messageFrame: CGRect,
        containerSize: CGSize
    ) -> some View {
        let reactionInset: CGFloat = 6
        let actionInset: CGFloat = 16
        let reactionWidth = containerSize.width - (reactionInset * 2)
        let actionWidth = min(216, containerSize.width - (actionInset * 2))
        let reactionHeight: CGFloat = 54
        let actionCount = (canSaveAsMoment(message) && !isSavedAsMoment(message) ? 1 : 0)
            + (canCreateAppointment(from: message) ? 1 : 0)
        let actionHeight = CGFloat(actionCount * 46 + max(0, actionCount - 1) * 8)
        let itemSpacing: CGFloat = 8
        let showsReaction = model.canReact(to: message)
        let showsAction = actionCount > 0
        let elementCount = 1 + (showsReaction ? 1 : 0) + (showsAction ? 1 : 0)
        let stackHeight = messageFrame.height
            + (showsReaction ? reactionHeight : 0)
            + (showsAction ? actionHeight : 0)
            + (CGFloat(elementCount - 1) * itemSpacing)
        let topSpace = messageFrame.minY
        let bottomSpace = containerSize.height - messageFrame.maxY
        let topRequirement = showsReaction ? reactionHeight + itemSpacing : 0
        let bottomRequirement = showsAction ? actionHeight + itemSpacing : 0
        let splitHasRoom = topSpace >= topRequirement && bottomSpace >= bottomRequirement
        let placeBothAbove = !splitHasRoom && topSpace >= bottomSpace
        let stackTop = placeBothAbove
            ? messageFrame.maxY - stackHeight
            : splitHasRoom
                ? messageFrame.minY - topRequirement
                : messageFrame.minY

        ZStack(alignment: .topLeading) {
            Button {
                actionMessageID = nil
            } label: {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.08))
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("關閉訊息選單")
            .accessibilityIdentifier("conversation-action-backdrop")

            focusedActionStack(
                for: message,
                messageSize: messageFrame.size,
                reactionWidth: reactionWidth,
                actionWidth: actionWidth,
                actionInset: actionInset,
                actionHeight: actionHeight,
                messageOffsetX: messageFrame.midX - (containerSize.width / 2),
                placeBothAbove: placeBothAbove,
                splitHasRoom: splitHasRoom
            )
            .frame(width: containerSize.width, height: stackHeight, alignment: .top)
            .position(
                x: containerSize.width / 2,
                y: stackTop + (stackHeight / 2)
            )
        }
    }

    @ViewBuilder
    private func focusedActionStack(
        for message: ChatMessage,
        messageSize: CGSize,
        reactionWidth: CGFloat,
        actionWidth: CGFloat,
        actionInset: CGFloat,
        actionHeight: CGFloat,
        messageOffsetX: CGFloat,
        placeBothAbove: Bool,
        splitHasRoom: Bool
    ) -> some View {
        VStack(spacing: 8) {
            if placeBothAbove {
                reactionPicker(for: message, width: reactionWidth)
                alignedMessageActions(
                    for: message,
                    width: actionWidth,
                    inset: actionInset,
                    height: actionHeight
                )
                focusedMessage(message)
                    .frame(width: messageSize.width, height: messageSize.height)
                    .offset(x: messageOffsetX)
            } else if splitHasRoom {
                reactionPicker(for: message, width: reactionWidth)
                focusedMessage(message)
                    .frame(width: messageSize.width, height: messageSize.height)
                    .offset(x: messageOffsetX)
                alignedMessageActions(
                    for: message,
                    width: actionWidth,
                    inset: actionInset,
                    height: actionHeight
                )
            } else {
                focusedMessage(message)
                    .frame(width: messageSize.width, height: messageSize.height)
                    .offset(x: messageOffsetX)
                alignedMessageActions(
                    for: message,
                    width: actionWidth,
                    inset: actionInset,
                    height: actionHeight
                )
                reactionPicker(for: message, width: reactionWidth)
            }
        }
    }

    @ViewBuilder
    private func alignedMessageActions(
        for message: ChatMessage,
        width: CGFloat,
        inset: CGFloat,
        height: CGFloat
    ) -> some View {
        if (canSaveAsMoment(message) && !isSavedAsMoment(message))
            || canCreateAppointment(from: message) {
            HStack {
                if message.senderUserID == model.currentUserID { Spacer(minLength: 0) }
                VStack(spacing: 8) {
                    saveMomentAction(for: message)
                    createAppointmentAction(for: message)
                }
                    .frame(width: width, height: height)
                if message.senderUserID != model.currentUserID { Spacer(minLength: 0) }
            }
            .padding(.horizontal, inset)
            .frame(height: height)
        }
    }

    @ViewBuilder
    private func reactionPicker(for message: ChatMessage, width: CGFloat) -> some View {
        if model.canReact(to: message) {
            HStack(spacing: 0) {
                ForEach(MomentEmoji.allCases, id: \.self) { emoji in
                    Button {
                        actionMessageID = nil
                        Task { await model.react(to: message, with: emoji) }
                    } label: {
                        Text(emoji.symbol)
                            .font(.system(size: 29))
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .accessibilityLabel(emoji.accessibilityLabel)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    actionMessageID = nil
                    Task { @MainActor in
                        await Task.yield()
                        customEmojiMessage = message
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("更多 Emoji")
                .accessibilityIdentifier("more-conversation-emoji")
            }
            .padding(.horizontal, 4)
            .frame(width: width, height: 54)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
            .accessibilityIdentifier("conversation-reaction-picker")
        }
    }

    private func focusedMessage(_ message: ChatMessage) -> some View {
        let isCurrentUser = message.senderUserID == model.currentUserID
        return VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
            messageBubble(message, isCurrentUser: isCurrentUser)
            if isSavedAsMoment(message) {
                Label("已收藏為 Moment", systemImage: "sparkles")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let reaction = message.reaction {
                Text(reaction.symbol)
                    .font(.title3)
                    .accessibilityLabel(reaction.accessibilityLabel)
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversation-action-focused-message")
    }

    @ViewBuilder
    private func saveMomentAction(for message: ChatMessage) -> some View {
        if canSaveAsMoment(message) && !isSavedAsMoment(message) {
            Button {
                actionMessageID = nil
                Task {
                    guard await model.saveAsMoment(message) else { return }
                    await onMomentSaved()
                }
            } label: {
                Label("收藏為 Moment", systemImage: "sparkles")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
        }
    }

    @ViewBuilder
    private func createAppointmentAction(for message: ChatMessage) -> some View {
        if canCreateAppointment(from: message), let title = message.textBody {
            Button {
                actionMessageID = nil
                appointmentComposerSeed = AppointmentComposerSeed(
                    title: title,
                    sourceMessageID: message.id
                )
            } label: {
                Label("建立共同約定", systemImage: "calendar.badge.plus")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
            .accessibilityIdentifier("create-appointment-from-message")
        }
    }

    private func canCreateAppointment(from message: ChatMessage) -> Bool {
        mode.showsAppointmentFeatures
            && message.deliveryState == .synced
            && message.textBody != nil
    }

    private func canSaveAsMoment(_ message: ChatMessage) -> Bool {
        mode.allowsMomentSaving && model.canSaveAsMoment(message)
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
        guard let lastID = timelineItems.last?.id else { return }
        proxy.scrollTo(lastID, anchor: .bottom)
    }

    private func focus(on messageID: UUID, using proxy: ScrollViewProxy) async {
        guard await model.ensureMessageAvailable(id: messageID) else {
            focusMessageID = nil
            return
        }
        await Task.yield()
        withAnimation { proxy.scrollTo(ConversationTimelineItemID.message(messageID), anchor: .center) }
        highlightedMessageID = messageID
        focusMessageID = nil
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if highlightedMessageID == messageID { highlightedMessageID = nil }
        }
    }
}

private struct ConversationMessageBoundsKey: PreferenceKey {
    static var defaultValue: [UUID: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [UUID: Anchor<CGRect>],
        nextValue: () -> [UUID: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct ConversationPhotoPreview: Identifiable {
    let messageID: UUID
    let image: UIImage

    var id: UUID { messageID }
}

private struct ConversationPhotoPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let preview: ConversationPhotoPreview
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: preview.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("聊天照片預覽")
                .accessibilityIdentifier("conversation-photo-preview")

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .padding()
            }
            .accessibilityLabel("關閉照片")
        }
        .offset(y: dragOffset)
        .background(Color.black.opacity(backgroundOpacity).ignoresSafeArea())
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    dragOffset = max(0, value.translation.height)
                }
                .onEnded { value in
                    if value.translation.height > 100 || value.predictedEndTranslation.height > 180 {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .statusBarHidden()
    }

    private var backgroundOpacity: Double {
        max(0, 1 - Double(dragOffset / 500))
    }
}
