import SwiftUI

struct G1TechnicalSpikeView: View {
#if os(iOS)
    @StateObject private var model = CloudKitSharingPoC.shared
#endif

    var body: some View {
#if os(iOS)
        NavigationStack {
            Form {
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

                Section("通過條件") {
                    Text("兩支 iPhone 使用不同 Apple ID。A 邀請 B；B 接受後，任一方寫入標記，另一方重新整理能看到相同值。")
                }
            }
            .navigationTitle("W1 技術驗證")
            .sheet(isPresented: $model.isShowingSharingController) {
                if let share = model.share {
                    CloudSharingController(share: share)
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
    G1TechnicalSpikeView()
}
