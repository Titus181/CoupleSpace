import Supabase
import SwiftUI

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = PrimarySection.defaultSelection
    @StateObject private var networkRecoveryMonitor = NetworkRecoveryMonitor()
    @StateObject private var momentModel: MomentModel
    @StateObject private var togetherNowModel: TogetherNowModel
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
            if arguments.contains("--ui-testing-photo-moment"),
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
            let seededMessages: [ChatMessage]
            if arguments.contains("--ui-testing-failed-message") {
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
            } else if arguments.contains("--ui-testing-partner-message") {
                seededMessages = [ChatMessage(
                    id: UUID(uuidString: "D4000000-0000-0000-0000-000000000001")!,
                    senderUserID: uiTestPartnerID,
                    body: "晚點一起吃飯嗎？",
                    createdAt: .now
                )]
            } else {
                seededMessages = []
            }
            _conversationModel = StateObject(
                wrappedValue: ConversationModel(
                    service: InMemoryConversationService(
                        currentUserID: uiTestUserID,
                        messages: seededMessages,
                        unreadCount: seededMessages.count,
                        sendFailuresRemaining: arguments.contains("--ui-testing-offline") ? .max : 0
                    )
                )
            )
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("今天", systemImage: "sun.max", value: PrimarySection.today) {
                TodayMomentView(model: momentModel, togetherNowModel: togetherNowModel)
            }

            Tab("對話", systemImage: "bubble.left.and.bubble.right", value: PrimarySection.conversation) {
                ConversationView(model: conversationModel)
            }
            .badge(conversationModel.unreadCount)

            Tab("我們", systemImage: "person.2", value: PrimarySection.us) {
                UsView(
                    momentModel: momentModel,
                    togetherNowModel: togetherNowModel,
                    accountUserToken: accountUserToken,
                    accountStatusMessage: accountStatusMessage,
                    relationshipToken: relationshipToken,
                    technicalValidationClient: technicalValidationClient,
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
            async let conversationStart: Void = conversationModel.start()
            _ = await (momentStart, togetherNowStart, conversationStart)
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
                async let conversationRecovery: Void = conversationModel.recoverPendingMessages()
                _ = await (momentRefresh, togetherNowRefresh, conversationRecovery)
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
                async let conversationRecovery: Void = conversationModel.recoverPendingMessages()
                _ = await (momentRefresh, togetherNowRefresh, conversationRecovery)
            }
        }
        .onDisappear {
            Task {
                await momentModel.stop()
                await togetherNowModel.stop()
                await conversationModel.stop()
            }
        }
    }
}

private struct UsView: View {
    @State private var isShowingAccountSettings = false
    @ObservedObject var momentModel: MomentModel
    @ObservedObject var togetherNowModel: TogetherNowModel
    let accountUserToken: String?
    let accountStatusMessage: String?
    let relationshipToken: String?
    let technicalValidationClient: SupabaseClient?
    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MomentTimelineView(model: momentModel, togetherNowModel: togetherNowModel)
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
        }
        .accessibilityIdentifier("us-screen")
        .onAppear {
            isShowingAccountSettings = false
        }
        .onDisappear {
            isShowingAccountSettings = false
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
