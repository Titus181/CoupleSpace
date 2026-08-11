import Foundation

enum MomentMood: String, CaseIterable, Codable, Equatable, Sendable {
    case calm
    case happy
    case tired
    case thinkingOfYou = "thinking_of_you"
    case needHug = "need_hug"

    var title: String {
        switch self {
        case .calm: "平靜"
        case .happy: "開心"
        case .tired: "有點累"
        case .thinkingOfYou: "想到你"
        case .needHug: "想要抱抱"
        }
    }

    var symbol: String {
        switch self {
        case .calm: "leaf"
        case .happy: "sun.max"
        case .tired: "moon.zzz"
        case .thinkingOfYou: "heart"
        case .needHug: "figure.2.arms.open"
        }
    }
}

enum MomentContent: Equatable, Sendable {
    case mood(MomentMood)
    case text(String)
    case photo
}

struct Moment: Identifiable, Equatable, Sendable {
    let id: UUID
    let creatorUserID: UUID
    let content: MomentContent
    let createdAt: Date
}

enum MomentDraft: Equatable, Sendable {
    case mood(MomentMood)
    case text(String)
    case photo(Data)
}

enum MomentDraftPolicy {
    static let maximumTextLength = 280

    static func normalizedText(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= maximumTextLength else { return nil }
        return normalized
    }
}
