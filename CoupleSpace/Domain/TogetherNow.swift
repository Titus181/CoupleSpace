import Foundation

enum CurrentStatusKind: String, CaseIterable, Codable, Equatable, Sendable {
    case busy
    case availableToTalk = "available_to_talk"
    case quiet
    case tired
    case needCompany = "need_company"
    case needHug = "need_hug"
    case thinkingOfYou = "thinking_of_you"

    var title: String {
        switch self {
        case .busy: "忙一下，晚點聊"
        case .availableToTalk: "現在可以聊聊"
        case .quiet: "想安靜一下"
        case .tired: "有點累"
        case .needCompany: "想被陪陪"
        case .needHug: "想要抱抱"
        case .thinkingOfYou: "想到你"
        }
    }

    var symbol: String {
        switch self {
        case .busy: "clock"
        case .availableToTalk: "bubble.left.and.bubble.right"
        case .quiet: "moon"
        case .tired: "moon.zzz"
        case .needCompany: "person.2"
        case .needHug: "figure.2.arms.open"
        case .thinkingOfYou: "heart"
        }
    }
}

enum CurrentStatusContent: Codable, Equatable, Sendable {
    case fixed(CurrentStatusKind)
    case custom(String)

    var title: String {
        switch self {
        case let .fixed(kind): kind.title
        case let .custom(text): text
        }
    }
}

enum CurrentStatusExpiration: String, CaseIterable, Codable, Equatable, Sendable {
    case oneHour = "one_hour"
    case fourHours = "four_hours"
    case tonight
    case manual

    var title: String {
        switch self {
        case .oneHour: "1 小時"
        case .fourHours: "4 小時"
        case .tonight: "到今晚"
        case .manual: "手動清除"
        }
    }

    func tonightExpiresAt(from date: Date, calendar: Calendar) -> Date? {
        guard self == .tonight else { return nil }
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
    }
}

struct CurrentRelationshipStatus: Codable, Equatable, Sendable {
    let userID: UUID
    let content: CurrentStatusContent
    let expiration: CurrentStatusExpiration
    let expiresAt: Date?
    let updatedAt: Date

    func isActive(at date: Date) -> Bool {
        expiresAt.map { $0 > date } ?? true
    }
}

struct CurrentStatusDraft: Equatable, Sendable {
    let content: CurrentStatusContent
    let expiration: CurrentStatusExpiration
    let savesAsMoment: Bool
}

struct TogetherNowSnapshot: Codable, Equatable, Sendable {
    let currentUserID: UUID
    let partnerUserID: UUID
    let currentDisplayName: String?
    let partnerDisplayName: String?
    let privatePartnerName: String?
    let currentStatus: CurrentRelationshipStatus?
    let partnerStatus: CurrentRelationshipStatus?

    var currentUserLabel: String {
        currentDisplayName ?? "我"
    }

    var partnerLabel: String {
        privatePartnerName ?? partnerDisplayName ?? "伴侶"
    }

    func participantLabel(for userID: UUID) -> String {
        userID == currentUserID ? currentUserLabel : partnerLabel
    }

    func participantPossessiveLabel(for userID: UUID) -> String {
        let label = participantLabel(for: userID)
        return label == "我" ? "我的" : "\(label)的"
    }
}

enum TogetherNowTextPolicy {
    static let maximumNameLength = 20
    static let maximumCustomStatusLength = 40

    static func normalizedOptionalName(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.unicodeScalars.count <= maximumNameLength
        else { return nil }
        return normalized
    }

    static func isValidOptionalNameInput(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty || normalized.unicodeScalars.count <= maximumNameLength
    }

    static func normalizedCustomStatus(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.unicodeScalars.count <= maximumCustomStatusLength
        else { return nil }
        return normalized
    }
}
