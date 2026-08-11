import SwiftUI

struct PairingGateView: View {
    @ObservedObject var model: PairingModel
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
                    accountUserToken: accountUserToken,
                    accountStatusMessage: accountStatusMessage,
                    relationshipToken: relationship.displayToken,
                    onSignOut: onSignOut
                )
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
    @State private var isConfirmingSignOut = false

    private var hasValidInput: Bool {
        PairingInputPolicy.invitationToken(from: invitationCode) != nil
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
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .accessibilityIdentifier("pairing-invitation-code")

                        ShareLink(
                            item: "加入我在 CoupleSpace 的私人空間。\n邀請碼：\(invitation.code)"
                        ) {
                            Label("分享邀請", systemImage: "square.and.arrow.up")
                        }

                        Text("邀請將於 \(invitation.expiresAt.formatted(date: .omitted, time: .shortened)) 失效；失效或被拒絕後可產生新邀請。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
                        TextField("完整貼上邀請碼", text: $invitationCode)
                            .textInputAutocapitalization(.never)
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
                Text("未完成的邀請會保留到失效，你可以使用同一個 Apple 帳號再登入。")
            }
        }
    }
}
