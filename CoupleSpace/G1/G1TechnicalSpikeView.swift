import AuthenticationServices
import PhotosUI
import Supabase
import SwiftUI

struct G1TechnicalSpikeView: View {
    @StateObject private var authModel: SupabaseAppleAuthPoC
    @StateObject private var pairingModel: SupabasePairingPoC
#if os(iOS)
    @StateObject private var pushModel: SupabasePushPoC
#endif

#if os(iOS)
    @State private var supabaseSelectedPhoto: PhotosPickerItem?
    @State private var pairingInvitationInput = ""
    @State private var isConfirmingBeginUnpairing = false
    @State private var isConfirmingPersonalArchive = false
    @State private var isConfirmingArchiveDeletion = false
#endif

    init(supabaseClient: SupabaseClient) {
        _authModel = StateObject(
            wrappedValue: SupabaseAppleAuthPoC(client: supabaseClient)
        )
        _pairingModel = StateObject(
            wrappedValue: SupabasePairingPoC(client: supabaseClient)
        )
#if os(iOS)
        _pushModel = StateObject(
            wrappedValue: SupabasePushPoC(client: supabaseClient)
        )
#endif
    }

    var body: some View {
#if os(iOS)
        NavigationStack {
            Form {
                Section("Supabase Apple Auth") {
                    Text(authModel.status)
                    LabeledContent("使用者代碼", value: authModel.userToken)

                    if authModel.isSignedIn {
                        Button("登出 Supabase", role: .destructive) {
                            Task { await authModel.signOut() }
                        }
                    } else {
                        SignInWithAppleButton(
                            .signIn,
                            onRequest: authModel.prepare,
                            onCompletion: authModel.complete
                        )
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 44)
                    }
                }

                if authModel.isSignedIn {
                    Section("Supabase 私人推播邊界") {
                        Text(pushModel.status)
                        LabeledContent("Token 指紋", value: pushModel.tokenFingerprint)
                        Text("只顯示 token 雜湊前八碼；伺服器自行推導另一位 active 成員，通知不含私人內容。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("1. 允許通知並登記此裝置") {
                            Task { await pushModel.requestAuthorizationAndRegister() }
                        }
                        .disabled(pushModel.isWorking)

                        Button(
                            pushModel.hasPendingPush
                                ? "2. 重試泛化 W1 測試推播"
                                : "2. 傳送泛化 W1 測試推播"
                        ) {
                            Task {
                                await pushModel.sendOrRetryGenericTestPush(
                                    relationshipID: pairingModel.currentRelationshipID
                                )
                            }
                        }
                        .disabled(pushModel.isWorking)
                    }

                    Section("Supabase 雙身分 RLS") {
                        Text(pairingModel.status)
                        LabeledContent("關係代碼", value: pairingModel.relationshipToken)
                        LabeledContent("成員", value: "\(pairingModel.memberCount)/2")
                        LabeledContent("關係資料", value: pairingModel.relationshipSnapshotStatus)
                        LabeledContent("最新標記", value: pairingModel.latestMarkerToken)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("最近 3 個標記（舊 → 新）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(pairingModel.recentMarkerTokens)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        LabeledContent("Outbox", value: pairingModel.markerOutboxStatus)

                        Button("A. 建立或取回 pairing invitation") {
                            Task { await pairingModel.createInvitation() }
                        }

                        if let invitationToken = pairingModel.invitationToken {
                            Text(invitationToken)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            ShareLink(item: invitationToken) {
                                Label("分享 invitation token", systemImage: "square.and.arrow.up")
                            }
                        }

                        TextField("B. 貼上 invitation token", text: $pairingInvitationInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("B. 接受 pairing invitation") {
                            Task {
                                await pairingModel.acceptInvitation(pairingInvitationInput)
                            }
                        }

                        Button("寫入新的 RLS 驗證標記") {
                            Task { await pairingModel.writeMarker() }
                        }
                        .disabled(pairingModel.isMarkerOutboxSending)
                        if pairingModel.hasPendingMarker {
                            Button("重試待送標記") {
                                Task { await pairingModel.retryPendingMarker() }
                            }
                            .disabled(pairingModel.isMarkerOutboxSending)
                        }
                        Button("重新整理 RLS 狀態") {
                            Task { await pairingModel.refresh() }
                        }

                        LabeledContent("Realtime", value: pairingModel.realtimeStatus)
                        if pairingModel.isRealtimeActive {
                            Button("停止 Realtime") {
                                Task { await pairingModel.stopRealtime() }
                            }
                        } else {
                            Button("啟動 Realtime 驗證") {
                                Task { await pairingModel.startRealtime() }
                            }
                        }
                    }

                    Section("Supabase 文字訊息 Outbox") {
                        Text("只產生不含私人內容的 W1 測試訊息")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        LabeledContent("最近 3 則（舊 → 新）", value: pairingModel.recentTestMessages)
                        LabeledContent("Message Outbox", value: pairingModel.messageOutboxStatus)

                        Button("寫入新的 W1 測試訊息") {
                            Task { await pairingModel.writeTestMessage() }
                        }
                        .disabled(pairingModel.isMessageOutboxSending)

                        if pairingModel.hasPendingMessage {
                            Button("重試待送訊息") {
                                Task { await pairingModel.retryPendingMessages() }
                            }
                            .disabled(pairingModel.isMessageOutboxSending)
                        }

                        Button("重新整理測試訊息") {
                            Task { await pairingModel.refresh() }
                        }
                    }

                    Section("Supabase Storage 私有照片") {
                        Text(pairingModel.storageStatus)
                        LabeledContent("最近 3 張（舊 → 新）", value: pairingModel.recentPhotoTokens)
                        LabeledContent("Photo Outbox", value: pairingModel.photoOutboxStatus)

                        if let data = pairingModel.storagePhotoData,
                           let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        PhotosPicker(selection: $supabaseSelectedPhoto, matching: .images) {
                            Label("選擇並上傳私有測試照片", systemImage: "lock.photo")
                        }
                        .disabled(pairingModel.isPhotoOutboxSending)
                        if pairingModel.hasPendingPhoto {
                            Button("重試待送照片") {
                                Task { await pairingModel.retryPendingPhoto() }
                            }
                            .disabled(pairingModel.isPhotoOutboxSending)
                        }
                        Button("重新整理 Supabase Storage 照片") {
                            Task { await pairingModel.refreshStoragePhoto() }
                        }
                    }

                    Section("Supabase 資料生命週期 A1") {
                        Text(pairingModel.lifecycleStatus)
                        LabeledContent(
                            "個人封存項目",
                            value: "\(pairingModel.personalArchiveItemCount)"
                        )

                        Button("1. 開始解除配對（closing）", role: .destructive) {
                            isConfirmingBeginUnpairing = true
                        }
                        .disabled(
                            pairingModel.relationshipStatus != "active"
                                || !PhotoOutboxLifecyclePolicy.canBeginUnpairing(
                                    hasPendingPhoto: pairingModel.hasPendingPhoto,
                                    isSendingPhoto: pairingModel.isPhotoOutboxSending
                                )
                                || pairingModel.hasPendingMessage
                                || pairingModel.isMessageOutboxSending
                        )

                        Button("2. 建立個人唯讀封存") {
                            isConfirmingPersonalArchive = true
                        }
                        .disabled(
                            pairingModel.relationshipStatus != "closing"
                                || pairingModel.hasPersonalArchive
                        )

                        Button("重新整理資料生命週期狀態") {
                            Task { await pairingModel.refresh() }
                        }

                        Button("3. 刪除自己的個人封存", role: .destructive) {
                            isConfirmingArchiveDeletion = true
                        }
                        .disabled(
                            pairingModel.relationshipStatus != "archived"
                                || !pairingModel.hasPersonalArchive
                        )

                        if pairingModel.relationshipStatus == "archived" {
                            Button("重試照片清理佇列") {
                                Task { await pairingModel.retryStorageGC() }
                            }
                        }
                    }
                }

                Section("通過條件") {
                    Text("兩個 Apple 身分登入同一個 Supabase relationship；雙向寫入、離線重送、封存與刪除結果均符合 W1 驗證紀錄。")
                }
            }
            .navigationTitle("W1 技術驗證")
            .task {
                await authModel.observeAuthState()
            }
            .onChange(of: authModel.isSignedIn) { _, isSignedIn in
                if isSignedIn {
                    Task { await pairingModel.refresh() }
                } else {
                    Task {
                        await pairingModel.clearSession()
                        pushModel.clearSession()
                    }
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .coupleSpaceDidRegisterForRemoteNotifications
                )
            ) { notification in
                guard let data = notification.object as? Data else { return }
                Task { await pushModel.register(deviceToken: data) }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .coupleSpaceDidFailToRegisterForRemoteNotifications
                )
            ) { notification in
                guard let error = notification.object as? Error else { return }
                pushModel.reportRegistrationFailure(error)
            }
            .onChange(of: supabaseSelectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    defer { supabaseSelectedPhoto = nil }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            pairingModel.reportStoragePhotoSelectionFailure(nil)
                            return
                        }
                        let prepared = try PhotoAssetProcessor.prepare(data)
                        await pairingModel.uploadStoragePhoto(prepared.fullData)
                    } catch {
                        pairingModel.reportStoragePhotoSelectionFailure(error)
                    }
                }
            }
            .confirmationDialog(
                "開始解除配對？",
                isPresented: $isConfirmingBeginUnpairing,
                titleVisibility: .visible
            ) {
                Button("開始解除配對", role: .destructive) {
                    Task { await pairingModel.beginUnpairing() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("關係會進入 closing，雙方將不能再新增共同內容。此 W1 測試關係無法恢復為 active。")
            }
            .confirmationDialog(
                "建立個人封存？",
                isPresented: $isConfirmingPersonalArchive,
                titleVisibility: .visible
            ) {
                Button("建立個人唯讀封存") {
                    Task { await pairingModel.sealPersonalArchive() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("伺服器會複製目前共同項目到只屬於你的封存；雙方都完成後，關係會轉為 archived。")
            }
            .confirmationDialog(
                "永久刪除自己的個人封存？",
                isPresented: $isConfirmingArchiveDeletion,
                titleVisibility: .visible
            ) {
                Button("永久刪除個人封存", role: .destructive) {
                    Task { await pairingModel.deletePersonalArchive() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作無法復原。另一方的封存不受影響；若這是最後一份封存，伺服器會清理共同照片。")
            }
        }
#else
        ContentUnavailableView(
            "僅供 iPhone 真機驗證",
            systemImage: "iphone",
            description: Text("W1 Supabase 技術驗證不支援此平台。")
        )
#endif
    }
}

#Preview {
    G1TechnicalSpikeView(supabaseClient: CoupleSpaceSupabaseClient.preview)
}
