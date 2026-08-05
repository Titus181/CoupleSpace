import AuthenticationServices
import PhotosUI
import Supabase
import SwiftUI

struct G1TechnicalSpikeView: View {
    @StateObject private var authModel: SupabaseAppleAuthPoC
    @StateObject private var pairingModel: SupabasePairingPoC

#if os(iOS)
    @StateObject private var model = CloudKitSharingPoC.shared
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var supabaseSelectedPhoto: PhotosPickerItem?
    @State private var pairingInvitationInput = ""
#endif

    init(supabaseClient: SupabaseClient) {
        _authModel = StateObject(
            wrappedValue: SupabaseAppleAuthPoC(client: supabaseClient)
        )
        _pairingModel = StateObject(
            wrappedValue: SupabasePairingPoC(client: supabaseClient)
        )
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
                    Section("Supabase 雙身分 RLS") {
                        Text(pairingModel.status)
                        LabeledContent("關係代碼", value: pairingModel.relationshipToken)
                        LabeledContent("成員", value: "\(pairingModel.memberCount)/2")
                        LabeledContent("最新標記", value: pairingModel.latestMarkerToken)

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

                    Section("Supabase Storage 私有照片") {
                        Text(pairingModel.storageStatus)

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
                        Button("重新整理 Supabase Storage 照片") {
                            Task { await pairingModel.refreshStoragePhoto() }
                        }
                    }
                }

                Section("CloudKit Sharing 狀態") {
                    Text(model.status)
                    LabeledContent("最新標記", value: model.lastWriterToken)
                }

                Section("裝置 A：建立者") {
                    Button("1. 檢查 iCloud 帳號") {
                        Task { await model.checkAccount() }
                    }
                    Button("2. 建立共享關係 PoC") {
                        Task { await model.createOwnerRelationship() }
                    }
                    Button("3. 邀請另一個 Apple ID") {
                        Task { await model.prepareExistingShare() }
                    }
                }

                Section("雙向驗證") {
                    Button("寫入新的驗證標記") {
                        Task { await model.writeValidationMarker() }
                    }
                    Button("重新整理") {
                        Task { await model.refresh() }
                    }
                }

                Section("照片 CKAsset 驗證") {
                    Text(model.photoStatus)

                    if let photo = model.latestPhoto {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("選擇並上傳測試照片", systemImage: "photo")
                    }
                    Button("重新整理共享照片") {
                        Task { await model.refreshPhoto() }
                    }
                }

                Section("通過條件") {
                    Text("兩支 iPhone 使用不同 Apple ID。A 邀請 B；B 接受後，任一方寫入標記，另一方重新整理能看到相同值。")
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
                    Task { await pairingModel.clearSession() }
                }
            }
            .sheet(isPresented: $model.isShowingSharingController) {
                if let share = model.share {
                    CloudSharingController(share: share)
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    defer { selectedPhoto = nil }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            model.reportPhotoSelectionFailure(nil)
                            return
                        }
                        await model.uploadPhoto(data)
                    } catch {
                        model.reportPhotoSelectionFailure(error)
                    }
                }
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
        }
#else
        ContentUnavailableView(
            "僅供 iPhone 真機驗證",
            systemImage: "iphone",
            description: Text("W1 CloudKit Sharing PoC 不支援此平台。")
        )
#endif
    }
}

#Preview {
    G1TechnicalSpikeView(supabaseClient: CoupleSpaceSupabaseClient.preview)
}
