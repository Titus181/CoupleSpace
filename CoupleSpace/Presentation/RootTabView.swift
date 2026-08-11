import Supabase
import SwiftUI

struct RootTabView: View {
    @State private var selection = PrimarySection.defaultSelection
    @StateObject private var momentModel: MomentModel
    let accountUserToken: String?
    let accountStatusMessage: String?
    let relationshipToken: String?
    let technicalValidationClient: SupabaseClient?
    let onSignOut: () -> Void

    init(
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
        if let relationshipID, let technicalValidationClient {
            _momentModel = StateObject(
                wrappedValue: MomentModel(
                    service: SupabaseMomentService(
                        client: technicalValidationClient,
                        relationshipID: relationshipID
                    )
                )
            )
        } else {
            let service: InMemoryMomentService
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-photo-moment"),
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
            } else {
                service = InMemoryMomentService()
            }
            _momentModel = StateObject(
                wrappedValue: MomentModel(service: service)
            )
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("今天", systemImage: "sun.max", value: PrimarySection.today) {
                TodayMomentView(model: momentModel)
            }

            Tab("對話", systemImage: "bubble.left.and.bubble.right", value: PrimarySection.conversation) {
                ConversationView()
            }

            Tab("我們", systemImage: "person.2", value: PrimarySection.us) {
                UsView(
                    momentModel: momentModel,
                    accountUserToken: accountUserToken,
                    accountStatusMessage: accountStatusMessage,
                    relationshipToken: relationshipToken,
                    technicalValidationClient: technicalValidationClient,
                    onSignOut: onSignOut
                )
            }
        }
        .tint(.accentColor)
        .task { await momentModel.start() }
        .onDisappear {
            Task { await momentModel.stop() }
        }
    }
}

private struct ConversationView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "兩人的對話",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("配對後，日常對話會留在這裡。")
            )
            .navigationTitle("對話")
        }
        .accessibilityIdentifier("conversation-screen")
    }
}

private struct UsView: View {
    @State private var isShowingAccountSettings = false
    @ObservedObject var momentModel: MomentModel
    let accountUserToken: String?
    let accountStatusMessage: String?
    let relationshipToken: String?
    let technicalValidationClient: SupabaseClient?
    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MomentTimelineView(model: momentModel)
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
                    userToken: accountUserToken,
                    statusMessage: accountStatusMessage,
                    relationshipToken: relationshipToken,
                    technicalValidationClient: technicalValidationClient,
                    onSignOut: onSignOut
                )
            }
        }
        .accessibilityIdentifier("us-screen")
    }
}

private struct AccountSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingSignOut = false
    @State private var isShowingTechnicalValidation = false
    let userToken: String?
    let statusMessage: String?
    let relationshipToken: String?
    let technicalValidationClient: SupabaseClient?
    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            Form {
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
