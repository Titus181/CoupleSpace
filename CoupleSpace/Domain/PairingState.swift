import Foundation

struct PairingRelationship: Equatable {
    let id: UUID
    let memberCount: Int
    let status: String

    init(id: UUID, memberCount: Int, status: String = "active") {
        self.id = id
        self.memberCount = memberCount
        self.status = status
    }

    var displayToken: String {
        String(id.uuidString.lowercased().prefix(8))
    }
}

struct PersonalArchive: Equatable {
    let id: UUID
    let relationshipID: UUID
}

struct PairingInvitation: Equatable {
    let relationshipID: UUID
    let token: UUID
    let shortCode: String
    let expiresAt: Date

    var code: String {
        let midpoint = shortCode.index(shortCode.startIndex, offsetBy: 4)
        return String(shortCode[..<midpoint]) + "-" + String(shortCode[midpoint...])
    }
}

enum PairingState: Equatable {
    case checking
    case unpaired
    case waiting(PairingRelationship, invitation: PairingInvitation?)
    case paired(PairingRelationship)
    case closing(PairingRelationship)
    case archived(PersonalArchive)
}

enum UnpairingReadiness: Equatable {
    case ready
    case pendingContent(count: Int)
}

enum PairingInputPolicy {
    private static let shortCodeCharacters = CharacterSet(
        charactersIn: "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
    )

    static func invitationIdentifier(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let token = UUID(uuidString: trimmed) {
            return token.uuidString.lowercased()
        }
        if let shortCode = normalizedShortCode(trimmed) {
            return shortCode
        }

        let labels = ["邀請碼", "配對碼", "invitation code"]
        for label in labels {
            guard let range = trimmed.range(of: label, options: .caseInsensitive) else { continue }
            let suffix = trimmed[range.upperBound...]
                .trimmingCharacters(in: CharacterSet(charactersIn: "：: \t"))
            let candidate = suffix.split(whereSeparator: \Character.isNewline).first.map(String.init) ?? ""
            if let shortCode = normalizedShortCode(candidate) {
                return shortCode
            }
        }
        return nil
    }

    private static func normalizedShortCode(_ value: String) -> String? {
        let normalized = value
            .uppercased()
            .unicodeScalars
            .filter {
                !CharacterSet.whitespacesAndNewlines.contains($0) && String($0) != "-"
            }
            .map(String.init)
            .joined()
        guard normalized.unicodeScalars.count == 8,
              normalized.unicodeScalars.allSatisfy(shortCodeCharacters.contains)
        else { return nil }
        return normalized
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
