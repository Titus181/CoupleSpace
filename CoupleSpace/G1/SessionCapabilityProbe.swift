#if DEBUG
import Combine
import CryptoKit
import Foundation
import Supabase
import SwiftUI

enum SessionCapabilityProbeAvailability {
    static let launchArgument = "--session-capability-probe"

    static func isEnabled(arguments: [String]) -> Bool {
        arguments.contains(launchArgument)
    }
}

struct SessionCapabilityProbeIdentity: Equatable {
    let fingerprint: String
    let expiresAt: Date

    init(sessionID: String, expiresAt: TimeInterval) {
        fingerprint = Self.fingerprint(for: sessionID)
        self.expiresAt = Date(timeIntervalSince1970: expiresAt)
    }

    static func fingerprint(for sessionID: String) -> String {
        SHA256.hash(data: Data(sessionID.utf8))
            .prefix(6)
            .map { String(format: "%02X", $0) }
            .joined()
    }
}

enum SessionProtectedDataRead<Value: Equatable>: Equatable {
    case notRun
    case succeeded(Value)
    case failed
}

struct SessionProtectedRelationshipEvidence: Equatable {
    let fingerprint: String
    let status: String
}

struct SessionProtectedArchiveEvidence: Equatable {
    let fingerprint: String
    let relationshipFingerprint: String
}

struct SessionProtectedDataSnapshot: Equatable {
    var hasAuthSession: Bool?
    var relationship: SessionProtectedDataRead<SessionProtectedRelationshipEvidence?>
    var activeMemberCount: SessionProtectedDataRead<Int>
    var sharedItemCount: SessionProtectedDataRead<Int>
    var personalArchive: SessionProtectedDataRead<SessionProtectedArchiveEvidence?>
    var personalArchiveItemCount: SessionProtectedDataRead<Int>

    static let notRun = SessionProtectedDataSnapshot(
        hasAuthSession: nil,
        relationship: .notRun,
        activeMemberCount: .notRun,
        sharedItemCount: .notRun,
        personalArchive: .notRun,
        personalArchiveItemCount: .notRun
    )
}

@MainActor
protocol SessionProtectedDataInspecting {
    func inspect() async -> SessionProtectedDataSnapshot
}

private struct SessionProtectedRelationshipRow: Decodable {
    let id: UUID
    let status: String
}

private struct SessionProtectedMembershipRow: Decodable {
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
    }
}

private struct SessionProtectedSharedItemRow: Decodable {
    let clientID: UUID

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
    }
}

private struct SessionProtectedArchiveRow: Decodable {
    let id: UUID
    let relationshipID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case relationshipID = "relationship_id"
    }
}

private struct SessionProtectedArchiveItemRow: Decodable {
    let clientID: UUID

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
    }
}

@MainActor
final class SupabaseSessionProtectedDataInspector: SessionProtectedDataInspecting {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func inspect() async -> SessionProtectedDataSnapshot {
        var snapshot = SessionProtectedDataSnapshot.notRun
        snapshot.hasAuthSession = (try? await client.auth.session) != nil

        do {
            let rows: [SessionProtectedRelationshipRow] = try await client
                .from("relationships")
                .select("id,status")
                .limit(1)
                .execute()
                .value
            snapshot.relationship = .succeeded(rows.first.map {
                SessionProtectedRelationshipEvidence(
                    fingerprint: SessionCapabilityProbeIdentity.fingerprint(
                        for: $0.id.uuidString
                    ),
                    status: $0.status
                )
            })
        } catch {
            snapshot.relationship = .failed
        }

        do {
            let members: [SessionProtectedMembershipRow] = try await client
                .from("relationship_members")
                .select("user_id")
                .eq("membership_status", value: "active")
                .execute()
                .value
            snapshot.activeMemberCount = .succeeded(members.count)
        } catch {
            snapshot.activeMemberCount = .failed
        }

        do {
            let items: [SessionProtectedSharedItemRow] = try await client
                .from("shared_items")
                .select("client_id")
                .execute()
                .value
            snapshot.sharedItemCount = .succeeded(items.count)
        } catch {
            snapshot.sharedItemCount = .failed
        }

        do {
            let archives: [SessionProtectedArchiveRow] = try await client
                .from("personal_archives")
                .select("id,relationship_id")
                .order("sealed_at", ascending: false)
                .limit(1)
                .execute()
                .value
            let archive = archives.first
            snapshot.personalArchive = .succeeded(archive.map {
                SessionProtectedArchiveEvidence(
                    fingerprint: SessionCapabilityProbeIdentity.fingerprint(
                        for: $0.id.uuidString
                    ),
                    relationshipFingerprint: SessionCapabilityProbeIdentity.fingerprint(
                        for: $0.relationshipID.uuidString
                    )
                )
            })

            if let archive {
                do {
                    let items: [SessionProtectedArchiveItemRow] = try await client
                        .from("personal_archive_items")
                        .select("client_id")
                        .eq("archive_id", value: archive.id)
                        .execute()
                        .value
                    snapshot.personalArchiveItemCount = .succeeded(items.count)
                } catch {
                    snapshot.personalArchiveItemCount = .failed
                }
            }
        } catch {
            snapshot.personalArchive = .failed
        }

        return snapshot
    }
}

@MainActor
final class SessionProtectedDataProbeModel: ObservableObject {
    @Published private(set) var snapshot = SessionProtectedDataSnapshot.notRun
    @Published private(set) var isWorking = false

    private let inspector: SessionProtectedDataInspecting

    init(client: SupabaseClient) {
        inspector = SupabaseSessionProtectedDataInspector(client: client)
    }

    init(inspector: SessionProtectedDataInspecting) {
        self.inspector = inspector
    }

    func inspect() async {
        isWorking = true
        defer { isWorking = false }
        snapshot = await inspector.inspect()
    }
}

@MainActor
final class SessionCapabilityProbeModel: ObservableObject {
    @Published private(set) var identity: SessionCapabilityProbeIdentity?
    @Published private(set) var expiresAt: Date?
    @Published private(set) var hasCurrentSession = false
    @Published private(set) var status = "尚未讀取目前 session。"
    @Published private(set) var isWorking = false

    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func inspectCurrentSession() async {
        isWorking = true
        defer { isWorking = false }

        do {
            let session = try await client.auth.session
            expiresAt = Date(timeIntervalSince1970: session.expiresAt)
            hasCurrentSession = true
            let response = try await client.auth.getClaims()
            guard let sessionID = response.claims.sessionId else {
                identity = nil
                status = "目前 JWT 沒有 session_id；不能提供穩定 session identity。"
                return
            }

            identity = SessionCapabilityProbeIdentity(
                sessionID: sessionID,
                expiresAt: response.claims.exp ?? session.expiresAt
            )
            status = "已取得目前 session identity。"
        } catch {
            identity = nil
            expiresAt = nil
            hasCurrentSession = false
            status = "無法取得目前 session identity；請確認登入與網路。"
        }
    }

    func refreshCurrentSession() async {
        isWorking = true
        defer { isWorking = false }

        do {
            _ = try await client.auth.refreshSession()
            status = "目前 session refresh 成功。"
            await inspectCurrentSession()
        } catch {
            identity = nil
            expiresAt = nil
            hasCurrentSession = false
            status = "目前 session refresh 被拒絕或失敗。"
        }
    }

    func revokeAllOtherSessions() async {
        isWorking = true
        defer { isWorking = false }

        do {
            try await client.auth.signOut(scope: .others)
            status = "已送出登出所有其他 session；這不是目標裝置已失效的證據。"
        } catch {
            status = "無法送出登出所有其他 session。"
        }
    }
}

struct SessionCapabilityProbeView: View {
    @StateObject private var model: SessionCapabilityProbeModel
    @StateObject private var protectedDataModel: SessionProtectedDataProbeModel
    @State private var isConfirmingRevoke = false

    init(client: SupabaseClient) {
        _model = StateObject(wrappedValue: SessionCapabilityProbeModel(client: client))
        _protectedDataModel = StateObject(
            wrappedValue: SessionProtectedDataProbeModel(client: client)
        )
    }

    var body: some View {
        Section("W13 Auth session 測試") {
            Text("僅限已明確設定測試專案的 Debug 啟動；不顯示 session ID、JWT 或 refresh token。")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("目前 session", value: model.hasCurrentSession ? "已取得" : "未取得")
            if let identity = model.identity {
                LabeledContent("測試指紋", value: identity.fingerprint)
            }
            if let expiresAt = model.expiresAt {
                LabeledContent(
                    "Access JWT 到期",
                    value: expiresAt.formatted(date: .omitted, time: .shortened)
                )
            }
            Text(model.status)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("讀取目前 session identity") {
                Task { await model.inspectCurrentSession() }
            }
            .disabled(model.isWorking)
            .accessibilityIdentifier("session-probe-inspect")

            Button("驗證目前 session refresh") {
                Task { await model.refreshCurrentSession() }
            }
            .disabled(model.isWorking)
            .accessibilityIdentifier("session-probe-refresh")

            Button("登出所有其他 session", role: .destructive) {
                isConfirmingRevoke = true
            }
            .disabled(model.isWorking || !model.hasCurrentSession)
            .accessibilityIdentifier("session-probe-revoke-others")
        }
        .task {
            await model.inspectCurrentSession()
        }
        .alert(
            "登出所有其他 session？",
            isPresented: $isConfirmingRevoke
        ) {
            Button("登出所有其他 session", role: .destructive) {
                Task { await model.revokeAllOtherSessions() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只在可清理的測試專案執行。它會保留目前手機的 session，並撤銷全部其他 session，不能指定一支裝置。")
        }

        Section("遠端受保護資料") {
            Text("只向測試專案讀取 metadata 與筆數；不讀取或顯示訊息、照片、約定、封存正文或 raw ID。所有結果都是本次遠端查詢，不使用本機快取。")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent(
                "Auth session",
                value: authSessionDescription(protectedDataModel.snapshot.hasAuthSession)
            )
            LabeledContent(
                "Relationship",
                value: relationshipDescription(protectedDataModel.snapshot.relationship)
            )
            LabeledContent(
                "Active members",
                value: countDescription(protectedDataModel.snapshot.activeMemberCount)
            )
            LabeledContent(
                "共同項目 shared_items",
                value: countDescription(protectedDataModel.snapshot.sharedItemCount)
            )
            LabeledContent(
                "本人個人封存",
                value: archiveDescription(protectedDataModel.snapshot.personalArchive)
            )
            LabeledContent(
                "本人封存項目",
                value: countDescription(protectedDataModel.snapshot.personalArchiveItemCount)
            )

            Button("讀取遠端受保護資料") {
                Task { await protectedDataModel.inspect() }
            }
            .disabled(protectedDataModel.isWorking)
            .accessibilityIdentifier("session-probe-protected-data")
        }
    }

    private func authSessionDescription(_ hasSession: Bool?) -> String {
        switch hasSession {
        case true: "存在"
        case false: "不存在／refresh 失敗"
        case nil: "尚未執行"
        }
    }

    private func relationshipDescription(
        _ read: SessionProtectedDataRead<SessionProtectedRelationshipEvidence?>
    ) -> String {
        switch read {
        case .notRun:
            "尚未執行"
        case .failed:
            "遠端讀取失敗"
        case .succeeded(nil):
            "成功 · 無可見資料"
        case let .succeeded(.some(evidence)):
            "成功 · \(evidence.status) · \(evidence.fingerprint)"
        }
    }

    private func archiveDescription(
        _ read: SessionProtectedDataRead<SessionProtectedArchiveEvidence?>
    ) -> String {
        switch read {
        case .notRun:
            "尚未執行"
        case .failed:
            "遠端讀取失敗"
        case .succeeded(nil):
            "成功 · 無本人封存"
        case let .succeeded(.some(evidence)):
            "成功 · \(evidence.fingerprint) · 關係 \(evidence.relationshipFingerprint)"
        }
    }

    private func countDescription(_ read: SessionProtectedDataRead<Int>) -> String {
        switch read {
        case .notRun: "未執行／不適用"
        case .failed: "遠端讀取失敗"
        case let .succeeded(count): "成功 · \(count)"
        }
    }
}

struct SessionCapabilityProbeScreen: View {
    let client: SupabaseClient

    var body: some View {
        Form {
            SessionCapabilityProbeView(client: client)
        }
    }
}
#endif
