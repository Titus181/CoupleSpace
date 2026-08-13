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

enum MomentContent: Codable, Equatable, Sendable {
    case mood(MomentMood)
    case text(String)
    case photo
    case question(MomentQuestion)
}

struct MomentQuestion: Codable, Equatable, Sendable {
    let key: String
    let prompt: String
}

enum MomentEmoji: String, CaseIterable, Codable, Equatable, Sendable {
    case heart
    case hug
    case smile
    case cheer
    case laugh
    case support

    var symbol: String {
        switch self {
        case .heart: "❤️"
        case .hug: "🫂"
        case .smile: "😊"
        case .cheer: "👏"
        case .laugh: "😂"
        case .support: "💪"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .heart: "愛心"
        case .hug: "抱抱"
        case .smile: "微笑"
        case .cheer: "為你鼓掌"
        case .laugh: "一起笑"
        case .support: "替你加油"
        }
    }
}

enum MomentResponseContent: Codable, Equatable, Sendable {
    case emoji(MomentEmoji)
    case text(String)
}

struct MomentResponse: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let responderUserID: UUID
    let content: MomentResponseContent
    let createdAt: Date
}

struct MomentQuestionAnswer: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let answererUserID: UUID
    let content: String
    let createdAt: Date
}

struct Moment: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let creatorUserID: UUID
    let content: MomentContent
    let createdAt: Date
    var responses: [MomentResponse] = []
    var questionAnswers: [MomentQuestionAnswer] = []

    var isComplete: Bool {
        switch content {
        case .question:
            Set(questionAnswers.map(\.answererUserID)).count == 2
        case .mood, .text, .photo:
            !responses.isEmpty
        }
    }
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

enum MomentResponseDraft: Equatable, Sendable {
    case emoji(MomentEmoji)
    case text(String)
}

enum MomentResponsePolicy {
    static let maximumTextLength = 80

    static func normalizedText(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= maximumTextLength else { return nil }
        return normalized
    }

    static func normalizedEmoji(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count == 1,
              let character = normalized.first,
              character.unicodeScalars.contains(where: {
                  $0.properties.isEmojiPresentation || $0.value == 0xFE0F
              })
        else { return nil }
        return normalized
    }
}

struct MomentQuestionPrompt: Identifiable, Hashable, Sendable {
    let id: String
    let prompt: String

    static let accepted: [MomentQuestionPrompt] = [
        MomentQuestionPrompt(id: "understand_today", prompt: "今天最希望我理解你什麼？"),
        MomentQuestionPrompt(id: "recent_small_happiness", prompt: "最近有哪件小事讓你感到幸福？"),
        MomentQuestionPrompt(id: "together_this_week", prompt: "這週想一起完成什麼？"),
        MomentQuestionPrompt(id: "unsaid_recently", prompt: "最近有沒有想說、但一直沒找到時機的事？"),
    ]
}

struct MomentQuestionDraft: Equatable, Sendable {
    let questionKey: String
    let answer: String
}

enum MomentQuestionPolicy {
    static let maximumAnswerLength = 280

    static func normalizedAnswer(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= maximumAnswerLength else { return nil }
        return normalized
    }
}
