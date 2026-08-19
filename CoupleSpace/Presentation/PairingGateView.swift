import SwiftUI
import Supabase
import UniformTypeIdentifiers

struct PairingGateView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: PairingModel
#if DEBUG
    @State private var isShowingSessionCapabilityProbe = false
#endif
    let supabaseClient: SupabaseClient
    let accountUserID: UUID?
    let accountUserToken: String?
    let accountStatusMessage: String?
    let onSignOut: () -> Void

    var body: some View {
        Group {
            switch model.state {
            case .checking:
                ProgressView("正在確認伴侶關係…")
                    .accessibilityIdentifier("pairing-checking")

            case .unpaired:
                PairingSetupView(
                    model: model,
                    accountUserToken: accountUserToken,
                    onSignOut: onSignOut
                )

            case let .waiting(relationship, invitation):
                PairingSetupView(
                    model: model,
                    relationship: relationship,
                    invitation: invitation,
                    accountUserToken: accountUserToken,
                    onSignOut: onSignOut
                )

            case let .paired(relationship):
                RootTabView(
                    accountUserID: accountUserID,
                    accountUserToken: accountUserToken,
                    accountStatusMessage: accountStatusMessage,
                    relationshipID: relationship.id,
                    relationshipToken: relationship.displayToken,
                    technicalValidationClient: supabaseClient,
                    pairingModel: model,
                    onSignOut: onSignOut,
                    onRelationshipLifecycleChanged: { await model.refresh() }
                )

            case .closing:
                ClosingRelationshipRecoveryView(
                    model: model,
                    accountUserToken: accountUserToken,
                    onSignOut: onSignOut
                )

            case .archived:
                ArchivedPersonalArchiveView(
                    model: model,
                    accountUserToken: accountUserToken,
                    onSignOut: onSignOut
                )
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.refresh() }
        }
#if DEBUG
        .overlay(alignment: .topTrailing) {
            if showsSessionCapabilityProbeEntry,
               SessionCapabilityProbeAvailability.isEnabled(
                   arguments: ProcessInfo.processInfo.arguments
               ) {
                Button {
                    isShowingSessionCapabilityProbe = true
                } label: {
                    Label("W13 session 測試", systemImage: "checkmark.shield")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("session-capability-probe-gate-entry")
                .padding()
            }
        }
        .sheet(isPresented: $isShowingSessionCapabilityProbe) {
            NavigationStack {
                SessionCapabilityProbeScreen(client: supabaseClient)
                    .navigationTitle("W13 session 測試")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") {
                                isShowingSessionCapabilityProbe = false
                            }
                        }
                    }
            }
        }
#endif
    }

#if DEBUG
    private var showsSessionCapabilityProbeEntry: Bool {
        if case .paired = model.state { return false }
        return true
    }
#endif
}

private struct ArchivedPersonalArchiveView: View {
    @ObservedObject var model: PairingModel
    let accountUserToken: String?
    let onSignOut: () -> Void
    @State private var isExporting = false
    @State private var isConfirmingSignOut = false
    @State private var hasDeferredFollowUp = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("個人封存已完成")
                            .font(.title2.weight(.semibold))
                        Text("這份封存只屬於你。你可以匯出副本；另一方無法讀取或管理它。")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("個人封存") {
                    Button("匯出我的個人封存") {
                        Task {
                            await model.preparePersonalArchiveExport()
                            isExporting = model.archiveExportDocument != nil
                        }
                    }
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("export-personal-archive")
                }

                Section("新的關係") {
                    Button("建立新的配對邀請") {
                        Task { await model.createOrRetryInvitation() }
                    }
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("create-pairing-invitation-from-archive")

                    Text("這不會刪除或改動你的個人封存。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("稍後處理") {
                        hasDeferredFollowUp = true
                    }
                    .accessibilityIdentifier("defer-personal-archive-follow-up")
                    if hasDeferredFollowUp {
                        Text("個人封存已安全保存；你隨時可以回來匯出或建立新的配對。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.isWorking {
                    Section {
                        ProgressView("正在準備個人封存匯出…")
                    }
                }

                if let statusMessage = model.statusMessage {
                    Section("狀態") {
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("personal-archive-status")
                    }
                }

                if let accountUserToken {
                    Section("帳號") {
                        LabeledContent("帳號識別碼", value: accountUserToken)
                        Button("登出", role: .destructive) {
                            isConfirmingSignOut = true
                        }
                    }
                }
            }
            .navigationTitle("個人封存")
            .accessibilityIdentifier("archived-personal-archive-screen")
            .fileExporter(
                isPresented: $isExporting,
                document: model.archiveExportDocument,
                contentType: .folder,
                defaultFilename: model.archiveExportFileName,
                onCompletion: model.finishPersonalArchiveExport
            )
            .alert(
                "要登出 CoupleSpace 嗎？",
                isPresented: $isConfirmingSignOut
            ) {
                Button("登出", role: .destructive) {
                    onSignOut()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("你可以使用同一個 Apple 帳號再次登入並存取自己的個人封存。")
            }
        }
    }
}

private struct ClosingRelationshipRecoveryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: PairingModel
    let accountUserToken: String?
    let onSignOut: () -> Void
    @State private var isConfirmingSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("解除配對進行中")
                            .font(.title2.weight(.semibold))
                        Text(model.closingPersonalArchive == nil
                            ? "共同空間已停止新增內容。請建立自己的個人封存；雙方完成後，這段關係會結束。"
                            : "你的個人封存已安全保存，等待另一方完成。對方不能讀取、匯出或管理你的封存。")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("完成解除配對") {
                    if model.closingPersonalArchive == nil {
                        Button("建立我的個人封存") {
                            Task { await model.sealPersonalArchive() }
                        }
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("seal-closing-personal-archive")
                    } else {
                        LabeledContent("本人封存", value: "已安全保存")
                    }

                    Button("重新確認解除配對狀態") {
                        Task { await model.refresh() }
                    }
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("refresh-closing-relationship")
                }

                if model.isWorking {
                    Section {
                        ProgressView("正在更新解除配對狀態…")
                    }
                }

                if let statusMessage = model.statusMessage {
                    Section("狀態") {
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("pairing-status")
                    }
                }

                if let accountUserToken {
                    Section("帳號") {
                        LabeledContent("帳號識別碼", value: accountUserToken)
                        Button("登出", role: .destructive) {
                            isConfirmingSignOut = true
                        }
                        .accessibilityIdentifier("pairing-sign-out")
                    }
                }
            }
            .navigationTitle("解除配對")
            .accessibilityIdentifier("closing-relationship-screen")
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(20))
                    guard scenePhase == .active else { continue }
                    await model.refresh()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await model.refresh() }
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
                Text("你可以使用同一個 Apple 帳號再次登入並完成解除配對。")
            }
        }
    }
}

private struct PairingSetupView: View {
    @ObservedObject var model: PairingModel
    var relationship: PairingRelationship?
    var invitation: PairingInvitation?
    var accountUserToken: String?
    let onSignOut: () -> Void
    @State private var invitationCode = ""
    @State private var isConfirmingDecline = false
    @State private var isConfirmingCancellation = false
    @State private var isConfirmingSwitchToPartnerInvitation = false
    @State private var isConfirmingSignOut = false

    private var hasValidInput: Bool {
        PairingInputPolicy.invitationIdentifier(from: invitationCode) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("建立只屬於你們的空間")
                            .font(.title2.weight(.semibold))
                        Text("一人建立邀請，另一人接受後，兩邊會進入同一段伴侶關係。")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("邀請伴侶") {
                    if let invitation {
                        Text(invitation.code)
                            .font(.title3.monospaced().weight(.semibold))
                            .textSelection(.enabled)
                            .accessibilityIdentifier("pairing-invitation-code")

                        ShareLink(
                            item: "加入我在 CoupleSpace 的私人空間。\n邀請碼：\(invitation.code)"
                        ) {
                            Label("分享邀請", systemImage: "square.and.arrow.up")
                        }

                        Text("邀請將於 \(CoupleSpaceDateFormat.string(invitation.expiresAt, date: .omitted, time: .shortened)) 失效；失效或被拒絕後可產生新邀請。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button {
                            Task { await model.createOrRetryInvitation() }
                        } label: {
                            Label("檢查並重試邀請", systemImage: "arrow.clockwise")
                        }
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("retry-pairing-invitation")

                        Button("取消我的邀請", role: .destructive) {
                            isConfirmingCancellation = true
                        }
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("cancel-pairing-invitation")

                        Button("改為接收伴侶邀請") {
                            isConfirmingSwitchToPartnerInvitation = true
                        }
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("switch-to-partner-invitation")
                    } else {
                        Button {
                            Task { await model.createOrRetryInvitation() }
                        } label: {
                            Label(
                                relationship == nil ? "建立邀請" : "取得或重試邀請",
                                systemImage: "person.badge.plus"
                            )
                        }
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("create-pairing-invitation")
                    }

                    if relationship != nil {
                        Button("重新確認配對狀態") {
                            Task { await model.refresh() }
                        }
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("refresh-pairing-status")
                    }
                }

                if relationship == nil {
                    Section("接受伴侶邀請") {
                        TextField("輸入 XXXX-XXXX 或貼上邀請", text: $invitationCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                            .accessibilityIdentifier("pairing-invitation-input")

                        Button("接受並完成配對") {
                            Task { await model.acceptInvitation(rawToken: invitationCode) }
                        }
                        .disabled(!hasValidInput || model.isWorking)
                        .accessibilityIdentifier("accept-pairing-invitation")

                        Button("拒絕這份邀請", role: .destructive) {
                            isConfirmingDecline = true
                        }
                        .disabled(!hasValidInput || model.isWorking)
                        .accessibilityIdentifier("decline-pairing-invitation")
                    }
                }

                if model.isWorking {
                    Section {
                        ProgressView("正在更新配對狀態…")
                    }
                }

                if let statusMessage = model.statusMessage {
                    Section("狀態") {
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("pairing-status")
                    }
                }

                if let accountUserToken {
                    Section("帳號") {
                        LabeledContent("帳號識別碼", value: accountUserToken)
                        Button("登出", role: .destructive) {
                            isConfirmingSignOut = true
                        }
                        .accessibilityIdentifier("pairing-sign-out")
                    }
                }
            }
            .navigationTitle("邀請與配對")
            .accessibilityIdentifier("pairing-screen")
            .confirmationDialog(
                "要拒絕這份邀請嗎？",
                isPresented: $isConfirmingDecline,
                titleVisibility: .visible
            ) {
                Button("拒絕邀請", role: .destructive) {
                    Task { await model.declineInvitation(rawToken: invitationCode) }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("邀請者之後可以建立新的邀請。")
            }
            .alert(
                "要取消自己的邀請嗎？",
                isPresented: $isConfirmingCancellation
            ) {
                Button("取消邀請", role: .destructive) {
                    Task { await model.cancelInvitation() }
                }
                Button("保留邀請", role: .cancel) {}
            } message: {
                Text("取消後可以改為接受伴侶建立的邀請；尚未配對的空白關係會一併移除。")
            }
            .alert(
                "要改為接收伴侶的邀請嗎？",
                isPresented: $isConfirmingSwitchToPartnerInvitation
            ) {
                Button("取消我的邀請並繼續", role: .destructive) {
                    Task { await model.cancelInvitation() }
                }
                Button("保留我的邀請", role: .cancel) {}
            } message: {
                Text("你自己的未完成邀請會被取消，接著即可輸入伴侶的邀請碼。")
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
                Text("未完成的邀請會保留到失效，你可以使用同一個 Apple 帳號再登入。")
            }
        }
    }
}
