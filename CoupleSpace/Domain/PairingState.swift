import Foundation

struct PairingRelationship: Equatable {
    let id: UUID
    let memberCount: Int

    var displayToken: String {
        String(id.uuidString.lowercased().prefix(8))
    }
}

struct PairingInvitation: Equatable {
    let relationshipID: UUID
    let token: UUID
    let expiresAt: Date

    var code: String {
        token.uuidString.lowercased()
    }
}

enum PairingState: Equatable {
    case checking
    case unpaired
    case waiting(PairingRelationship, invitation: PairingInvitation?)
    case paired(PairingRelationship)
}

enum PairingInputPolicy {
    static func invitationToken(from rawValue: String) -> UUID? {
        UUID(uuidString: rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

enum PairingErrorMessage {
    static func message(serverMessage: String) -> String {
        switch serverMessage {
        case "invitation_not_available":
            "這份邀請已失效、被拒絕或已使用，請向伴侶索取新的邀請碼。"
        case "cannot_accept_own_invitation", "cannot_decline_own_invitation":
            "這是你建立的邀請，請交給伴侶使用。"
        case "participant_already_paired":
            "這個帳號已有進行中的配對或伴侶關係。"
        case "invitation_not_cancellable":
            "這份邀請目前無法取消，請重新確認配對狀態。"
        case "relationship_not_empty":
            "這段關係已有共同內容，無法直接取消邀請。"
        default:
            "目前無法完成配對，請確認網路後再試一次。"
        }
    }
}
