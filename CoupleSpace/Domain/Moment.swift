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
    var sourceMessageID: UUID? = nil
    var sourceAppointmentID: UUID? = nil
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

    var source: MomentSource? {
        sourceMessageID.map {
            MomentSource(messageID: $0, appointmentID: sourceAppointmentID)
        }
    }
}

struct MomentSource: Codable, Equatable, Sendable {
    let messageID: UUID
    let appointmentID: UUID?
}

struct MomentMonthSection: Identifiable, Equatable, Sendable {
    let monthStart: Date
    let moments: [Moment]

    var id: Date { monthStart }
}

struct MomentPageCursor: Equatable, Sendable {
    let createdAt: Date
    let clientID: UUID
}

struct MomentPage: Equatable, Sendable {
    let moments: [Moment]
    let hasMore: Bool
}

enum MomentContentFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case mood
    case text
    case photo
    case question

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "全部"
        case .mood: "心情"
        case .text: "文字"
        case .photo: "照片"
        case .question: "我們的一題"
        }
    }

    func includes(_ moment: Moment) -> Bool {
        switch (self, moment.content) {
        case (.all, _), (.mood, .mood), (.text, .text), (.photo, .photo),
             (.question, .question):
            true
        default:
            false
        }
    }
}

enum MomentTimelinePolicy {
    static func monthSections(
        from moments: [Moment],
        calendar: Calendar = .current
    ) -> [MomentMonthSection] {
        let orderedMoments = moments.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        let grouped = Dictionary(grouping: orderedMoments) { moment in
            calendar.dateInterval(of: .month, for: moment.createdAt)?.start
        }

        return grouped.compactMap { monthStart, moments in
            monthStart.map { MomentMonthSection(monthStart: $0, moments: moments) }
        }
        .sorted { $0.monthStart > $1.monthStart }
    }

    static func photoMonthSections(
        from moments: [Moment],
        calendar: Calendar = .current
    ) -> [MomentMonthSection] {
        monthSections(
            from: moments.filter {
                if case .photo = $0.content { return true }
                return false
            },
            calendar: calendar
        )
        .reversed()
        .map { section in
            MomentMonthSection(
                monthStart: section.monthStart,
                moments: Array(section.moments.reversed())
            )
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
