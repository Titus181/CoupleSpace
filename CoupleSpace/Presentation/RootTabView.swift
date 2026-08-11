import SwiftUI

struct RootTabView: View {
    @State private var selection = PrimarySection.defaultSelection
    let accountUserToken: String?
    let accountStatusMessage: String?
    let relationshipToken: String?
    let onSignOut: () -> Void

    init(
        accountUserToken: String? = nil,
        accountStatusMessage: String? = nil,
        relationshipToken: String? = nil,
        onSignOut: @escaping () -> Void = {}
    ) {
        self.accountUserToken = accountUserToken
        self.accountStatusMessage = accountStatusMessage
        self.relationshipToken = relationshipToken
        self.onSignOut = onSignOut
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("今天", systemImage: "sun.max", value: PrimarySection.today) {
                TodayView()
            }

            Tab("對話", systemImage: "bubble.left.and.bubble.right", value: PrimarySection.conversation) {
                ConversationView()
            }

            Tab("我們", systemImage: "person.2", value: PrimarySection.us) {
                UsView(
                    accountUserToken: accountUserToken,
                    accountStatusMessage: accountStatusMessage,
                    relationshipToken: relationshipToken,
                    onSignOut: onSignOut
                )
            }
        }
        .tint(.accentColor)
    }
}

private struct TodayView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("再忙，也能每天留一點位置給彼此。")
                            .font(.title2.weight(.semibold))
                        Text("把零碎日常，慢慢變成我們的生活。")
                            .foregroundStyle(.secondary)
                    }

                    ContentUnavailableView {
                        Label("Moment・此刻", systemImage: "sparkles")
                    } description: {
                        Text("之後可以在這裡留下心情、照片或一句話。")
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                }
                .padding()
            }
            .navigationTitle("今天")
        }
        .accessibilityIdentifier("today-screen")
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
    let accountUserToken: String?
    let accountStatusMessage: String?
    let relationshipToken: String?
    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ContentUnavailableView(
                    "我們的生活",
                    systemImage: "person.2",
                    description: Text("共同時間線、日程與收藏會慢慢累積在這裡。")
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
    let userToken: String?
    let statusMessage: String?
    let relationshipToken: String?
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
            .confirmationDialog(
                "要登出 CoupleSpace 嗎？",
                isPresented: $isConfirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("登出", role: .destructive) {
                    onSignOut()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("之後可使用同一個 Apple 帳號重新登入。")
            }
        }
    }
}

#Preview {
    RootTabView()
}
