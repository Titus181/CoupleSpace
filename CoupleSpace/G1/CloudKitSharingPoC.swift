#if os(iOS)
import CloudKit
import Combine
import SwiftUI
import UIKit

@MainActor
final class CloudKitSharingPoC: ObservableObject {
    static let shared = CloudKitSharingPoC()

    @Published private(set) var status = "尚未檢查 iCloud 帳號"
    @Published private(set) var lastWriterToken = "尚無驗證標記"
    @Published private(set) var share: CKShare?
    @Published var isShowingSharingController = false

    private let container = CKContainer.default()
    private var location: RelationshipLocation?

    private init() {
        location = RelationshipLocation.load()
    }

    func checkAccount() async {
        do {
            let accountStatus = try await container.accountStatus()
            switch accountStatus {
            case .available:
                status = "iCloud 帳號可用"
            case .noAccount:
                status = "此裝置未登入 iCloud"
            case .restricted:
                status = "此 iCloud 帳號受限制"
            case .couldNotDetermine:
                status = "無法判斷 iCloud 帳號狀態"
            case .temporarilyUnavailable:
                status = "iCloud 暫時無法使用"
            @unknown default:
                status = "未知的 iCloud 帳號狀態"
            }
        } catch {
            status = "帳號檢查失敗：\(error.localizedDescription)"
        }
    }

    func createOwnerRelationship() async {
        status = "正在建立開發環境共享資料…"

        do {
            let zone = CKRecordZone(zoneName: "CoupleSpaceG1PoC")
            _ = try await container.privateCloudDatabase.modifyRecordZones(
                saving: [zone],
                deleting: []
            )

            let rootID = CKRecord.ID(
                recordName: "relationship_\(UUID().uuidString.lowercased())",
                zoneID: zone.zoneID
            )
            let root = CKRecord(recordType: "RelationshipPoC", recordID: rootID)
            root["status"] = "active"
            root["createdAt"] = Date()

            let share = CKShare(rootRecord: root)
            share[CKShare.SystemFieldKey.title] = "CoupleSpace W1 技術驗證"
            share.publicPermission = .none

            let result = try await container.privateCloudDatabase.modifyRecords(
                saving: [root, share],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            guard case let .success(savedShare)? = result.saveResults[share.recordID],
                  let savedShare = savedShare as? CKShare
            else {
                throw PoCError.shareWasNotSaved
            }

            let newLocation = RelationshipLocation(
                databaseScope: .private,
                recordName: rootID.recordName,
                zoneName: rootID.zoneID.zoneName,
                ownerName: rootID.zoneID.ownerName
            )
            newLocation.save()
            location = newLocation
            self.share = savedShare
            status = "共享根記錄已建立；下一步傳送私人邀請"
        } catch {
            status = "建立失敗：\(error.localizedDescription)"
        }
    }

    func prepareExistingShare() async {
        guard let location else {
            status = "此裝置尚無共享關係位置"
            return
        }

        do {
            let root = try await database(for: location).record(for: location.recordID)
            guard let shareReference = root.share else {
                status = "此根記錄尚未建立 CKShare"
                return
            }
            let record = try await database(for: location).record(for: shareReference.recordID)
            guard let share = record as? CKShare else {
                throw PoCError.shareWasNotSaved
            }
            self.share = share
            isShowingSharingController = true
            status = "分享控制器已就緒"
        } catch {
            status = "讀取分享失敗：\(error.localizedDescription)"
        }
    }

    func accept(_ metadata: CKShare.Metadata) async {
        status = "正在接受 CloudKit 分享…"

        do {
            try await withCheckedThrowingContinuation { continuation in
                let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
                operation.acceptSharesResultBlock = { result in
                    continuation.resume(with: result)
                }
                container.add(operation)
            }

            guard let rootID = metadata.hierarchicalRootRecordID else {
                throw PoCError.missingRootRecord
            }
            let newLocation = RelationshipLocation(
                databaseScope: .shared,
                recordName: rootID.recordName,
                zoneName: rootID.zoneID.zoneName,
                ownerName: rootID.zoneID.ownerName
            )
            newLocation.save()
            location = newLocation
            status = "分享已接受；可讀寫同一筆共享記錄"
            await refresh()
        } catch {
            status = "接受分享失敗：\(error.localizedDescription)"
        }
    }

    func writeValidationMarker() async {
        guard let location else {
            status = "請先建立或接受一段共享關係"
            return
        }

        do {
            let database = database(for: location)
            let root = try await database.record(for: location.recordID)
            let token = UUID().uuidString.prefix(8).lowercased()
            root["lastWriterToken"] = String(token)
            root["lastWriteAt"] = Date()
            _ = try await database.save(root)
            lastWriterToken = String(token)
            status = "已寫入標記 \(token)；請在另一支手機重新整理"
        } catch {
            status = "寫入失敗：\(error.localizedDescription)"
        }
    }

    func refresh() async {
        guard let location else {
            status = "請先建立或接受一段共享關係"
            return
        }

        do {
            let root = try await database(for: location).record(for: location.recordID)
            lastWriterToken = root["lastWriterToken"] as? String ?? "尚無驗證標記"
            status = "已重新整理共享根記錄"
        } catch {
            status = "重新整理失敗：\(error.localizedDescription)"
        }
    }

    private func database(for location: RelationshipLocation) -> CKDatabase {
        switch location.databaseScope {
        case .private:
            container.privateCloudDatabase
        case .shared:
            container.sharedCloudDatabase
        }
    }
}

private enum PoCError: LocalizedError {
    case missingRootRecord
    case shareWasNotSaved

    var errorDescription: String? {
        switch self {
        case .missingRootRecord:
            "CloudKit 分享缺少根記錄"
        case .shareWasNotSaved:
            "CloudKit 未回傳已儲存的分享"
        }
    }
}

private struct RelationshipLocation: Codable {
    enum DatabaseScope: String, Codable {
        case `private`
        case shared
    }

    static let defaultsKey = "g1.cloudKit.relationshipLocation"

    let databaseScope: DatabaseScope
    let recordName: String
    let zoneName: String
    let ownerName: String

    var recordID: CKRecord.ID {
        CKRecord.ID(
            recordName: recordName,
            zoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        )
    }

    func save() {
        let data = try? JSONEncoder().encode(self)
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    static func load() -> Self? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

struct CloudSharingController: UIViewControllerRepresentable {
    let share: CKShare

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: CKContainer.default())
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}
}

final class CloudKitShareSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else {
            return
        }
        Task {
            await CloudKitSharingPoC.shared.accept(metadata)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        Task {
            await CloudKitSharingPoC.shared.accept(metadata)
        }
    }
}

final class CloudKitShareAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = CloudKitShareSceneDelegate.self
        return configuration
    }
}
#endif
