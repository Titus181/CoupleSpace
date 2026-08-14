import Supabase
import SwiftUI

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = PrimarySection.defaultSelection
    @State private var conversationFocusMessageID: UUID?
    @StateObject private var networkRecoveryMonitor = NetworkRecoveryMonitor()
    @StateObject private var momentModel: MomentModel
    @StateObject private var togetherNowModel: TogetherNowModel
    @StateObject private var sharedAppointmentModel: SharedAppointmentModel
    @StateObject private var conversationModel: ConversationModel

    private var isOffline: Bool {
        networkRecoveryMonitor.state == .unavailable
            || ProcessInfo.processInfo.arguments.contains("--ui-testing-offline")
    }

    let accountUserToken: String?
    let accountStatusMessage: String?
    let relationshipToken: String?
    let technicalValidationClient: SupabaseClient?
    let onSignOut: () -> Void

    init(
        accountUserID: UUID? = nil,
        accountUserToken: String? = nil,
        accountStatusMessage: String? = nil,
        relationshipID: UUID? = nil,
        relationshipToken: String? = nil,
        technicalValidationClient: SupabaseClient? = nil,
        onSignOut: @escaping () -> Void = {}
    ) {
        self.accountUserToken = accountUserToken
        self.accountStatusMessage = accountStatusMessage
        self.relationshipToken = relationshipToken
        self.technicalValidationClient = technicalValidationClient
        self.onSignOut = onSignOut
        if let accountUserID, let relationshipID, let technicalValidationClient {
            _momentModel = StateObject(
                wrappedValue: MomentModel(
                    service: SupabaseMomentService(
                        client: technicalValidationClient,
                        currentUserID: accountUserID,
                        relationshipID: relationshipID
                    )
                )
            )
            _togetherNowModel = StateObject(
                wrappedValue: TogetherNowModel(
                    service: SupabaseTogetherNowService(
                        client: technicalValidationClient,
                        currentUserID: accountUserID,
                        relationshipID: relationshipID
                    )
                )
            )
            _sharedAppointmentModel = StateObject(
                wrappedValue: SharedAppointmentModel(
                    service: SupabaseSharedAppointmentService(
                        client: technicalValidationClient,
                        currentUserID: accountUserID,
                        relationshipID: relationshipID
                    ),
                    discussionModelFactory: { appointmentID in
                        ConversationModel(
                            service: SupabaseConversationService(
                                client: technicalValidationClient,
                                currentUserID: accountUserID,
                                relationshipID: relationshipID,
                                scope: .appointment(appointmentID)
                            )
                        )
                    }
                )
            )
            _conversationModel = StateObject(
                wrappedValue: ConversationModel(
                    service: SupabaseConversationService(
                        client: technicalValidationClient,
                        currentUserID: accountUserID,
                        relationshipID: relationshipID
                    )
                )
            )
        } else {
            let service: InMemoryMomentService
            let arguments = ProcessInfo.processInfo.arguments
            let uiTestUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
            let uiTestPartnerID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D2")!
            if arguments.contains("--ui-testing-w10-chat") {
                let sourceMessageID = UUID(uuidString: "D4000000-0000-0000-0000-000000000010")!
                service = InMemoryMomentService(
                    userID: uiTestUserID,
                    moments: [Moment(
                        id: UUID(uuidString: "D1000000-0000-0000-0000-000000000010")!,
                        creatorUserID: uiTestUserID,
                        content: .text("值得留下的晚餐約定"),
                        createdAt: .now,
                        sourceMessageID: sourceMessageID
                    )]
                )
            } else if arguments.contains("--ui-testing-photo-moment"),
               let photoData = Data(base64Encoded:
                   "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
               ) {
                let momentID = UUID(uuidString: "B1000000-0000-0000-0000-000000000099")!
                service = InMemoryMomentService(
                    moments: [Moment(
                        id: momentID,
                        creatorUserID: UUID(),
                        content: .photo,
                        createdAt: .now
                    )],
                    photoDataByMomentID: [momentID: photoData]
                )
            } else if arguments.contains("--ui-testing-partner-moment") {
                service = InMemoryMomentService(
                    userID: uiTestUserID,
                    moments: [Moment(
                        id: UUID(uuidString: "D1000000-0000-0000-0000-000000000001")!,
                        creatorUserID: uiTestPartnerID,
                        content: .text("今天也辛苦了"),
                        createdAt: .now
                    )]
                )
            } else if arguments.contains("--ui-testing-partner-question") {
                service = InMemoryMomentService(
                    userID: uiTestUserID,
                    moments: [Moment(
                        id: UUID(uuidString: "D1000000-0000-0000-0000-000000000002")!,
                        creatorUserID: uiTestPartnerID,
                        content: .question(MomentQuestion(
                            key: "recent_small_happiness",
                            prompt: "最近有哪件小事讓你感到幸福？"
                        )),
                        createdAt: .now,
                        questionAnswers: [MomentQuestionAnswer(
                            id: UUID(uuidString: "D3000000-0000-0000-0000-000000000001")!,
                            answererUserID: uiTestPartnerID,
                            content: "下班一起吃飯",
                            createdAt: .now
                        )]
                    )]
                )
            } else {
                service = InMemoryMomentService()
            }
            _momentModel = StateObject(
                wrappedValue: MomentModel(service: service)
            )
            _togetherNowModel = StateObject(
                wrappedValue: TogetherNowModel(service: InMemoryTogetherNowService())
            )
            let seededAppointments: [SharedAppointment]
            if arguments.contains("--ui-testing-w11-appointments") {
                seededAppointments = [
                    SharedAppointment(
                        id: UUID(uuidString: "A4000000-0000-0000-0000-000000000001")!,
                        creatorUserID: uiTestUserID,
                        title: "週末一起吃晚餐",
                        startsAt: .now.addingTimeInterval(86_400),
                        location: "中山站",
                        note: "記得先訂位",
                        reminderAt: .now.addingTimeInterval(82_800),
                        status: .scheduled,
                        sourceMessageID: nil,
                        createdAt: .now,
                        updatedAt: .now
                    ),
                    SharedAppointment(
                        id: UUID(uuidString: "A4000000-0000-0000-0000-000000000002")!,
                        creatorUserID: uiTestPartnerID,
                        title: "上週一起散步",
                        startsAt: .now.addingTimeInterval(-86_400),
                        location: nil,
                        note: nil,
                        reminderAt: nil,
                        status: .scheduled,
                        sourceMessageID: nil,
                        createdAt: .now.addingTimeInterval(-172_800),
                        updatedAt: .now.addingTimeInterval(-86_400)
                    ),
                ]
            } else if arguments.contains("--ui-testing-w11-calendar") {
                let startsAt = Calendar.autoupdatingCurrent.date(
                    bySettingHour: 18,
                    minute: 0,
                    second: 0,
                    of: .now
                ) ?? .now
                seededAppointments = [SharedAppointment(
                    id: UUID(uuidString: "A4000000-0000-0000-0000-000000000003")!,
                    creatorUserID: uiTestPartnerID,
                    title: "今天一起喝咖啡",
                    startsAt: startsAt,
                    location: "常去的咖啡店",
                    note: nil,
                    reminderAt: nil,
                    status: .scheduled,
                    sourceMessageID: nil,
                    createdAt: .now,
                    updatedAt: .now
                )]
            } else if arguments.contains("--ui-testing-w11-discussion") {
                seededAppointments = [SharedAppointment(
                    id: UUID(uuidString: "A4000000-0000-0000-0000-000000000004")!,
                    creatorUserID: uiTestUserID,
                    title: "週末去看展",
                    startsAt: .now.addingTimeInterval(86_400),
                    location: "美術館",
                    note: nil,
                    reminderAt: nil,
                    status: .scheduled,
                    sourceMessageID: nil,
                    createdAt: .now,
                    updatedAt: .now
                )]
            } else {
                seededAppointments = []
            }
            let discussionAppointmentID = UUID(
                uuidString: "A4000000-0000-0000-0000-000000000004"
            )!
            let seededDiscussionSummaries: [SharedAppointmentDiscussionSummary]
            if arguments.contains("--ui-testing-w11-discussion") {
                seededDiscussionSummaries = [SharedAppointmentDiscussionSummary(
                    appointmentID: discussionAppointmentID,
                    latestActivityAt: .now,
                    unreadCount: 2
                )]
            } else {
                seededDiscussionSummaries = []
            }
            _sharedAppointmentModel = StateObject(
                wrappedValue: SharedAppointmentModel(
                    service: InMemorySharedAppointmentService(
                        appointments: seededAppointments,
                        discussionSummaries: seededDiscussionSummaries
                    ),
                    discussionModelFactory: { appointmentID in
                        let messages: [ChatMessage]
                        let photoDataByMessageID: [UUID: Data]
                        if arguments.contains("--ui-testing-w11-discussion"),
                           appointmentID == discussionAppointmentID {
                            let photoMessageID = UUID(
                                uuidString: "D4000000-0000-0000-0000-000000000021"
                            )!
                            let pixel = Data(base64Encoded:
                                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
                            )!
                            messages = [
                                ChatMessage(
                                    id: photoMessageID,
                                    senderUserID: uiTestPartnerID,
                                    content: .photo,
                                    createdAt: .now.addingTimeInterval(-1)
                                ),
                                ChatMessage(
                                    id: UUID(uuidString: "D4000000-0000-0000-0000-000000000020")!,
                                    senderUserID: uiTestPartnerID,
                                    body: "要不要先約下午兩點？",
                                    createdAt: .now
                                ),
                            ]
                            photoDataByMessageID = [photoMessageID: pixel]
                        } else {
                            messages = []
                            photoDataByMessageID = [:]
                        }
                        return ConversationModel(
                            service: InMemoryConversationService(
                                currentUserID: uiTestUserID,
                                messages: messages,
                                unreadCount: messages.count,
                                photoDataByMessageID: photoDataByMessageID
                            )
                        )
                    }
                )
            )
            let seededMessages: [ChatMessage]
            let seededPhotoDataByMessageID: [UUID: Data]
            if arguments.contains("--ui-testing-w10-chat") {
                let sourceMessageID = UUID(uuidString: "D4000000-0000-0000-0000-000000000010")!
                let photoMessageID = UUID(uuidString: "D4000000-0000-0000-0000-000000000011")!
                seededMessages = [
                    ChatMessage(
                        id: sourceMessageID,
                        senderUserID: uiTestPartnerID,
                        body: "晚餐後一起散步",
                        createdAt: .now.addingTimeInterval(-1)
                    ),
                    ChatMessage(
                        id: photoMessageID,
                        senderUserID: uiTestPartnerID,
                        content: .photo,
                        createdAt: .now
                    ),
                ]
                let pixel = Data(base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
                )!
                seededPhotoDataByMessageID = [photoMessageID: pixel]
            } else if arguments.contains("--ui-testing-failed-message") {
                seededMessages = ["第一則待重試", "第二則待重試", "第三則待重試"]
                    .enumerated()
                    .map { index, body in
                        ChatMessage(
                            id: UUID(uuidString: "D4000000-0000-0000-0000-00000000000\(index + 2)")!,
                            senderUserID: uiTestUserID,
                            body: body,
                            createdAt: .now.addingTimeInterval(TimeInterval(index)),
                            deliveryState: .failed
                        )
                    }
                seededPhotoDataByMessageID = [:]
            } else if arguments.contains("--ui-testing-partner-message") {
                seededMessages = [ChatMessage(
                    id: UUID(uuidString: "D4000000-0000-0000-0000-000000000001")!,
                    senderUserID: uiTestPartnerID,
                    body: "晚點一起吃飯嗎？",
                    createdAt: .now
                )]
                seededPhotoDataByMessageID = [:]
            } else {
                seededMessages = []
                seededPhotoDataByMessageID = [:]
            }
            _conversationModel = StateObject(
                wrappedValue: ConversationModel(
                    service: InMemoryConversationService(
                        currentUserID: uiTestUserID,
                        messages: seededMessages,
                        unreadCount: seededMessages.count,
                        sendFailuresRemaining: arguments.contains("--ui-testing-offline") ? .max : 0,
                        photoDataByMessageID: seededPhotoDataByMessageID
                    )
                )
            )
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("今天", systemImage: "sun.max", value: PrimarySection.today) {
                TodayMomentView(
                    model: momentModel,
                    togetherNowModel: togetherNowModel,
                    sharedAppointmentModel: sharedAppointmentModel,
                    onOpenSourceMessage: openSourceMessage
                )
            }

            Tab("對話", systemImage: "bubble.left.and.bubble.right", value: PrimarySection.conversation) {
                ConversationView(
                    model: conversationModel,
                    sharedAppointmentModel: sharedAppointmentModel,
                    focusMessageID: $conversationFocusMessageID,
                    savedMomentSourceIDs: Set(momentModel.moments.compactMap(\.sourceMessageID)),
                    onMomentSaved: { await momentModel.refresh() }
                )
            }
            .badge(conversationModel.unreadCount + sharedAppointmentModel.discussionUnreadCount)

            Tab("我們", systemImage: "person.2", value: PrimarySection.us) {
                UsView(
                    momentModel: momentModel,
                    togetherNowModel: togetherNowModel,
                    sharedAppointmentModel: sharedAppointmentModel,
                    accountUserToken: accountUserToken,
                    accountStatusMessage: accountStatusMessage,
                    relationshipToken: relationshipToken,
                    technicalValidationClient: technicalValidationClient,
                    onOpenSourceMessage: openSourceMessage,
                    onSignOut: onSignOut
                )
            }
        }
        .tint(.accentColor)
        .safeAreaInset(edge: .top, spacing: 0) {
            if isOffline {
                Label("目前為離線模式，待送內容會在恢復網路後重試。", systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.thinMaterial)
                    .accessibilityIdentifier("offline-status")
            }
        }
        .task {
            networkRecoveryMonitor.start()
            async let momentStart: Void = momentModel.start()
            async let togetherNowStart: Void = togetherNowModel.start()
            async let sharedAppointmentStart: Void = sharedAppointmentModel.start()
            async let conversationStart: Void = conversationModel.start()
            _ = await (
                momentStart,
                togetherNowStart,
                sharedAppointmentStart,
                conversationStart
            )
        }
        .onChange(of: selection) { _, selection in
            Task {
                await conversationModel.setConversationVisible(selection == .conversation)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                async let momentRefresh: Void = momentModel.refresh()
                async let togetherNowRefresh: Void = togetherNowModel.refresh()
                async let sharedAppointmentRefresh: Void = sharedAppointmentModel
                    .recoverPendingAppointments()
                async let conversationRecovery: Void = conversationModel.recoverPendingMessages()
                _ = await (
                    momentRefresh,
                    togetherNowRefresh,
                    sharedAppointmentRefresh,
                    conversationRecovery
                )
            }
        }
        .onChange(of: networkRecoveryMonitor.state) { previous, current in
            guard scenePhase == .active,
                  NetworkRecoveryTriggerPolicy.shouldRecover(
                      previous: previous,
                      current: current
                  )
            else { return }
            Task {
                async let momentRefresh: Void = momentModel.refresh()
                async let togetherNowRefresh: Void = togetherNowModel.refresh()
                async let sharedAppointmentRefresh: Void = sharedAppointmentModel
                    .recoverPendingAppointments()
                async let conversationRecovery: Void = conversationModel.recoverPendingMessages()
                _ = await (
                    momentRefresh,
                    togetherNowRefresh,
                    sharedAppointmentRefresh,
                    conversationRecovery
                )
            }
        }
        .onDisappear {
            Task {
                await momentModel.stop()
                await togetherNowModel.stop()
                await sharedAppointmentModel.stop()
                await conversationModel.stop()
            }
        }
    }

    private func openSourceMessage(_ messageID: UUID) {
        selection = .conversation
        Task { @MainActor in
            await Task.yield()
            conversationFocusMessageID = messageID
        }
    }
}

private struct UsView: View {
    @State private var isShowingAccountSettings = false
    @State private var isShowingSharedSchedule = false
    @ObservedObject var momentModel: MomentModel
    @ObservedObject var togetherNowModel: TogetherNowModel
    @ObservedObject var sharedAppointmentModel: SharedAppointmentModel
    let accountUserToken: String?
    let accountStatusMessage: String?
    let relationshipToken: String?
    let technicalValidationClient: SupabaseClient?
    let onOpenSourceMessage: (UUID) -> Void
    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MomentTimelineView(
                    model: momentModel,
                    togetherNowModel: togetherNowModel,
                    onOpenSourceMessage: onOpenSourceMessage
                )
                if let accountStatusMessage {
                    Text(accountStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .accessibilityIdentifier("account-status")
                }
            }
            .navigationTitle("我們")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSharedSchedule = true
                    } label: {
                        Label("共同日程", systemImage: "calendar")
                    }
                    .accessibilityIdentifier("open-shared-appointment-schedule")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAccountSettings = true
                    } label: {
                        Label("帳號設定", systemImage: "person.crop.circle")
                    }
                    .accessibilityIdentifier("account-settings")
                }
            }
            .sheet(isPresented: $isShowingAccountSettings) {
                AccountSettingsView(
                    togetherNowModel: togetherNowModel,
                    userToken: accountUserToken,
                    statusMessage: accountStatusMessage,
                    relationshipToken: relationshipToken,
                    technicalValidationClient: technicalValidationClient,
                    onSignOut: onSignOut
                )
            }
            .sheet(isPresented: $isShowingSharedSchedule) {
                SharedAppointmentScheduleView(model: sharedAppointmentModel)
            }
        }
        .accessibilityIdentifier("us-screen")
        .onAppear {
            isShowingAccountSettings = false
            isShowingSharedSchedule = false
        }
        .onDisappear {
            isShowingAccountSettings = false
            isShowingSharedSchedule = false
        }
    }
}

private struct AccountSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingSignOut = false
    @State private var isShowingTechnicalValidation = false
    @ObservedObject var togetherNowModel: TogetherNowModel
    let userToken: String?
    let statusMessage: String?
    let relationshipToken: String?
    let technicalValidationClient: SupabaseClient?
    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                RelationshipNamesSettingsView(model: togetherNowModel)

                Section("帳號") {
                    LabeledContent("登入方式", value: "Apple")
                    LabeledContent("帳號識別碼", value: userToken ?? "無法取得")
                        .accessibilityIdentifier("account-user-token")
                    Text("識別碼只顯示前 8 碼，可用來確認重新登入後是否仍是同一個 CoupleSpace 帳號。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let relationshipToken {
                    Section("伴侶關係") {
                        LabeledContent("關係識別碼", value: relationshipToken)
                            .accessibilityIdentifier("relationship-token")
                        Text("雙方應看到相同的前 8 碼；這不是邀請碼。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let statusMessage {
                    Section("狀態") {
                        Text(statusMessage)
                            .accessibilityIdentifier("account-status")
                    }
                }

                if let togetherNowStatus = togetherNowModel.statusMessage {
                    Section("現在的我們") {
                        Text(togetherNowStatus)
                            .accessibilityIdentifier("together-now-status")
                    }
                }

#if DEBUG
                if technicalValidationClient != nil {
                    Section("開發測試") {
                        Button {
                            isShowingTechnicalValidation = true
                        } label: {
                            Label("W1 技術驗證工具", systemImage: "wrench.and.screwdriver")
                        }
                        .accessibilityIdentifier("w1-technical-tools")

                        Text("可測試訊息、照片、配對、解除關係與個人封存；不屬於正式產品介面。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
#endif

                Section {
                    Button("登出", role: .destructive) {
                        isConfirmingSignOut = true
                    }
                }
            }
            .navigationTitle("帳號設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .alert(
                "要登出 CoupleSpace 嗎？",
                isPresented: $isConfirmingSignOut
            ) {
                Button("登出", role: .destructive) {
                    onSignOut()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("之後可使用同一個 Apple 帳號重新登入。")
            }
#if DEBUG
            .sheet(isPresented: $isShowingTechnicalValidation) {
                if let technicalValidationClient {
                    G1TechnicalSpikeView(supabaseClient: technicalValidationClient)
                }
            }
#endif
        }
    }
}

#Preview {
    RootTabView()
}
