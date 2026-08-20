import Foundation
import Supabase

@MainActor
protocol MomentRemoteServing: AnyObject {
    func currentUserID() async throws -> UUID
    func cachedMoments() -> [Moment]?
    func cachedPhotoData(for momentID: UUID) -> Data?
    func commitAcceptedMoments(_ moments: [Moment])
    func commitAcceptedPhotoData(_ data: Data, for momentID: UUID)
    func removeCachedMomentData(for momentID: UUID)
    func fetchMoments() async throws -> [Moment]
    func fetchMomentsPage(before cursor: MomentPageCursor?, limit: Int) async throws -> MomentPage
    func fetchMoment(id: UUID) async throws -> Moment?
    func fetchHiddenMomentIDs() async throws -> Set<UUID>
    func fetchMomentSyncHints(after momentID: UUID?, limit: Int) async throws -> [MomentSyncHint]
    func fetchRecentlyDeletedMoments() async throws -> [RecentlyDeletedMoment]
    func createMoment(_ draft: MomentDraft, clientID: UUID) async throws -> Moment
    func createQuestion(
        _ draft: MomentQuestionDraft,
        momentClientID: UUID,
        answerClientID: UUID
    ) async throws -> Moment
    func createResponse(
        to momentID: UUID,
        draft: MomentResponseDraft,
        clientID: UUID
    ) async throws -> MomentResponse
    func answerQuestion(momentID: UUID, answer: String, clientID: UUID) async throws
        -> MomentQuestionAnswer
    func deleteMoment(id: UUID, operationID: UUID) async throws -> RecentlyDeletedMoment
    func restoreMoment(id: UUID, operationID: UUID) async throws -> Moment
    func removeResponse(momentID: UUID, responseID: UUID, operationID: UUID) async throws -> Moment?
    func removeAnswer(momentID: UUID, answerID: UUID, operationID: UUID) async throws -> Moment?
    func operationID(for identity: MomentOperationIdentity) throws -> UUID
    func clearOperationID(for identity: MomentOperationIdentity)
    func photoData(for moment: Moment) async throws -> Data
    func startObservingChanges(
        _ onChange: @escaping @MainActor (MomentRemoteChange) async -> Void
    ) async throws
    func stopObservingChanges() async
}

extension MomentRemoteServing {
    func cachedMoments() -> [Moment]? { nil }
    func cachedPhotoData(for momentID: UUID) -> Data? { nil }
    func commitAcceptedMoments(_ moments: [Moment]) {}
    func commitAcceptedPhotoData(_ data: Data, for momentID: UUID) {}
    func removeCachedMomentData(for momentID: UUID) {}

    func fetchMomentSyncHints() async throws -> [MomentSyncHint] {
        let pageSize = 500
        var cursor: UUID?
        var hints: [MomentSyncHint] = []
        while true {
            let page = try await fetchMomentSyncHints(after: cursor, limit: pageSize)
            hints.append(contentsOf: page)
            guard page.count == pageSize else { return hints }
            guard let nextCursor = page.last?.momentID,
                  nextCursor != cursor
            else {
                throw MomentServiceError.invalidServerMoment
            }
            cursor = nextCursor
        }
    }

    func fetchMomentsPage(before cursor: MomentPageCursor?, limit: Int) async throws -> MomentPage {
        let ordered = try await fetchMoments().sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString > $1.id.uuidString
        }
        let remaining = ordered.filter { moment in
            guard let cursor else { return true }
            return moment.createdAt < cursor.createdAt
                || (moment.createdAt == cursor.createdAt
                    && moment.id.uuidString < cursor.clientID.uuidString)
        }
        return MomentPage(
            moments: Array(remaining.prefix(limit)),
            hasMore: remaining.count > limit
        )
    }

    func operationID(for identity: MomentOperationIdentity) throws -> UUID { UUID() }
    func clearOperationID(for identity: MomentOperationIdentity) {}
}

private struct MomentRow: Decodable {
    let clientID: UUID
    let creatorUserID: UUID
    let kind: String
    let moodValue: String?
    let textContent: String?
    let questionKey: String?
    let questionPrompt: String?
    let sourceMessageID: UUID?
    let sourceAppointmentID: UUID?
    let createdAt: Date
    let deletedAt: Date?
    let purgeAfter: Date?

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case creatorUserID = "creator_user_id"
        case kind
        case moodValue = "mood_value"
        case textContent = "text_content"
        case questionKey = "question_key"
        case questionPrompt = "question_prompt"
        case sourceMessageID = "source_shared_item_client_id"
        case sourceAppointmentID = "source_appointment_client_id"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
        case purgeAfter = "purge_after"
    }

    func moment(
        responses: [MomentResponse] = [],
        questionAnswers: [MomentQuestionAnswer] = []
    ) throws -> Moment {
        let content: MomentContent
        switch kind {
        case "mood":
            guard let moodValue, let mood = MomentMood(rawValue: moodValue) else {
                throw MomentServiceError.invalidServerMoment
            }
            content = .mood(mood)
        case "text":
            guard let textContent else { throw MomentServiceError.invalidServerMoment }
            content = .text(textContent)
        case "photo":
            content = .photo
        case "question":
            guard let questionKey, let questionPrompt else {
                throw MomentServiceError.invalidServerMoment
            }
            content = .question(MomentQuestion(key: questionKey, prompt: questionPrompt))
        default:
            throw MomentServiceError.invalidServerMoment
        }

        return Moment(
            id: clientID,
            creatorUserID: creatorUserID,
            content: content,
            createdAt: createdAt,
            sourceMessageID: sourceMessageID,
            sourceAppointmentID: sourceAppointmentID,
            responses: responses,
            questionAnswers: questionAnswers
        )
    }
}

private struct MomentResponseRow: Decodable {
    let momentClientID: UUID
    let clientID: UUID
    let responderUserID: UUID
    let kind: String
    let emojiValue: String?
    let textContent: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case momentClientID = "moment_client_id"
        case clientID = "client_id"
        case responderUserID = "responder_user_id"
        case kind
        case emojiValue = "emoji_value"
        case textContent = "text_content"
        case createdAt = "created_at"
    }

    func response() throws -> MomentResponse {
        let content: MomentResponseContent
        switch kind {
        case "emoji":
            guard let emojiValue, let emoji = MomentEmoji(rawValue: emojiValue) else {
                throw MomentServiceError.invalidServerResponse
            }
            content = .emoji(emoji)
        case "text":
            guard let textContent else { throw MomentServiceError.invalidServerResponse }
            content = .text(textContent)
        default:
            throw MomentServiceError.invalidServerResponse
        }
        return MomentResponse(
            id: clientID,
            responderUserID: responderUserID,
            content: content,
            createdAt: createdAt
        )
    }
}

private struct MomentQuestionAnswerRow: Decodable {
    let momentClientID: UUID
    let clientID: UUID
    let answererUserID: UUID
    let answerContent: String?
    let createdAt: Date
    let removedAt: Date?

    enum CodingKeys: String, CodingKey {
        case momentClientID = "moment_client_id"
        case clientID = "client_id"
        case answererUserID = "answerer_user_id"
        case answerContent = "answer_content"
        case createdAt = "created_at"
        case removedAt = "removed_at"
    }

    func answer() -> MomentQuestionAnswer {
        MomentQuestionAnswer(
            id: clientID,
            answererUserID: answererUserID,
            content: answerContent,
            createdAt: createdAt,
            removedAt: removedAt
        )
    }
}

private struct CreateMomentParameters: Encodable {
    let targetRelationshipID: UUID
    let targetClientID: UUID
    let targetKind: String
    let targetMoodValue: String?
    let targetTextContent: String?
    let targetMediaByteSize: Int?

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetClientID = "target_client_id"
        case targetKind = "target_kind"
        case targetMoodValue = "target_mood_value"
        case targetTextContent = "target_text_content"
        case targetMediaByteSize = "target_media_byte_size"
    }
}

private struct CreateMomentResponseParameters: Encodable {
    let targetRelationshipID: UUID
    let targetMomentClientID: UUID
    let targetClientID: UUID
    let targetKind: String
    let targetEmojiValue: String?
    let targetTextContent: String?

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetMomentClientID = "target_moment_client_id"
        case targetClientID = "target_client_id"
        case targetKind = "target_kind"
        case targetEmojiValue = "target_emoji_value"
        case targetTextContent = "target_text_content"
    }
}

private struct CreateQuestionMomentParameters: Encodable {
    let targetRelationshipID: UUID
    let targetMomentClientID: UUID
    let targetQuestionKey: String
    let targetAnswerClientID: UUID
    let targetAnswerContent: String

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetMomentClientID = "target_moment_client_id"
        case targetQuestionKey = "target_question_key"
        case targetAnswerClientID = "target_answer_client_id"
        case targetAnswerContent = "target_answer_content"
    }
}

private struct AnswerMomentQuestionParameters: Encodable {
    let targetRelationshipID: UUID
    let targetMomentClientID: UUID
    let targetAnswerClientID: UUID
    let targetAnswerContent: String

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetMomentClientID = "target_moment_client_id"
        case targetAnswerClientID = "target_answer_client_id"
        case targetAnswerContent = "target_answer_content"
    }
}

private struct MomentOperationParameters: Encodable {
    let targetRelationshipID: UUID
    let targetMomentClientID: UUID
    let targetOperationID: UUID

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetMomentClientID = "target_moment_client_id"
        case targetOperationID = "target_operation_id"
    }
}

private struct MomentInteractionOperationParameters: Encodable {
    let targetRelationshipID: UUID
    let targetMomentClientID: UUID
    let targetInteractionClientID: UUID
    let targetOperationID: UUID

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case targetMomentClientID = "target_moment_client_id"
        case targetInteractionClientID = "target_interaction_client_id"
        case targetOperationID = "target_operation_id"
    }
}

private struct MomentLifecycleBroadcast: Decodable {
    let momentClientID: UUID
    let changeKind: String

    enum CodingKeys: String, CodingKey {
        case momentClientID = "moment_client_id"
        case changeKind = "change_kind"
    }
}

private struct RelationshipParameters: Encodable {
    let targetRelationshipID: UUID

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
    }
}

private struct MomentSyncHintPageParameters: Encodable {
    let targetRelationshipID: UUID
    let afterMomentClientID: UUID?
    let targetLimit: Int

    enum CodingKeys: String, CodingKey {
        case targetRelationshipID = "target_relationship_id"
        case afterMomentClientID = "after_moment_client_id"
        case targetLimit = "target_limit"
    }
}

private struct HiddenMomentIDRow: Decodable {
    let momentClientID: UUID

    enum CodingKeys: String, CodingKey {
        case momentClientID = "moment_client_id"
    }
}

private struct MomentSyncHintRow: Decodable {
    let momentClientID: UUID
    let isDeleted: Bool
    let sourceMessageClientID: UUID?
    let revision: Int64

    enum CodingKeys: String, CodingKey {
        case momentClientID = "moment_client_id"
        case isDeleted = "is_deleted"
        case sourceMessageClientID = "source_message_client_id"
        case revision
    }

    var hint: MomentSyncHint {
        MomentSyncHint(
            momentID: momentClientID,
            isDeleted: isDeleted,
            sourceMessageID: sourceMessageClientID,
            revision: revision
        )
    }
}

@MainActor
final class SupabaseMomentService: MomentRemoteServing {
    private static let photoBucket = "couplespace-moment-photos"
    private static let momentColumns = "client_id,creator_user_id,kind,mood_value,text_content,question_key,question_prompt,source_shared_item_client_id,source_appointment_client_id,created_at,deleted_at,purge_after"

    private let client: SupabaseClient
    private let currentUserIDValue: UUID
    private let relationshipID: UUID
    private let snapshotStore: TodaySnapshotStore
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTasks: [Task<Void, Never>] = []

    init(
        client: SupabaseClient,
        currentUserID: UUID,
        relationshipID: UUID,
        snapshotStore: TodaySnapshotStore? = nil
    ) {
        self.client = client
        currentUserIDValue = currentUserID
        self.relationshipID = relationshipID
        self.snapshotStore = snapshotStore ?? TodaySnapshotStore()
    }

    func currentUserID() async throws -> UUID {
        currentUserIDValue
    }

    func cachedMoments() -> [Moment]? {
        try? snapshotStore.loadMoments(
            userID: currentUserIDValue,
            relationshipID: relationshipID
        )
    }

    func cachedPhotoData(for momentID: UUID) -> Data? {
        try? snapshotStore.loadPhoto(
            userID: currentUserIDValue,
            relationshipID: relationshipID,
            momentID: momentID
        )
    }

    func commitAcceptedMoments(_ moments: [Moment]) {
        try? snapshotStore.saveMoments(
            moments,
            userID: currentUserIDValue,
            relationshipID: relationshipID
        )
    }

    func commitAcceptedPhotoData(_ data: Data, for momentID: UUID) {
        try? snapshotStore.savePhoto(
            data,
            userID: currentUserIDValue,
            relationshipID: relationshipID,
            momentID: momentID
        )
    }

    func removeCachedMomentData(for momentID: UUID) {
        evictCachedMoment(momentID)
    }

    func operationID(for identity: MomentOperationIdentity) throws -> UUID {
        try snapshotStore.loadOrCreateMomentOperationID(
            for: identity,
            userID: currentUserIDValue,
            relationshipID: relationshipID
        )
    }

    func clearOperationID(for identity: MomentOperationIdentity) {
        snapshotStore.clearMomentOperationID(
            for: identity,
            userID: currentUserIDValue,
            relationshipID: relationshipID
        )
    }

    func fetchMoments() async throws -> [Moment] {
        try await fetchRemoteMoments()
    }

    func fetchMomentsPage(before cursor: MomentPageCursor?, limit: Int) async throws -> MomentPage {
        let session = try await client.auth.session
        guard session.user.id == currentUserIDValue else {
            throw MomentServiceError.accountChanged
        }
        var query = client
            .from("moments")
            .select(Self.momentColumns)
            .eq("relationship_id", value: relationshipID)
            .is("deleted_at", value: nil)
        if let cursor {
            let timestamp = Self.cursorDateFormatter.string(from: cursor.createdAt)
            query = query.or(
                "created_at.lt.\(timestamp),and(created_at.eq.\(timestamp),client_id.lt.\(cursor.clientID.uuidString))"
            )
        }
        let rows: [MomentRow] = try await query
            .order("created_at", ascending: false)
            .order("client_id", ascending: false)
            .limit(limit + 1)
            .execute()
            .value
        let pageRows = Array(rows.prefix(limit))
        let moments = try await hydrate(pageRows)
        return MomentPage(moments: moments, hasMore: rows.count > limit)
    }

    private func fetchRemoteMoments() async throws -> [Moment] {
        let session = try await client.auth.session
        guard session.user.id == currentUserIDValue else {
            throw MomentServiceError.accountChanged
        }
        let rows: [MomentRow] = try await client
            .from("moments")
            .select(Self.momentColumns)
            .eq("relationship_id", value: relationshipID)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .order("client_id", ascending: false)
            .execute()
            .value
        return try await hydrate(rows)
    }

    func fetchMoment(id: UUID) async throws -> Moment? {
        let session = try await client.auth.session
        guard session.user.id == currentUserIDValue else {
            throw MomentServiceError.accountChanged
        }
        let rows: [MomentRow] = try await client
            .from("moments")
            .select(Self.momentColumns)
            .eq("relationship_id", value: relationshipID)
            .eq("client_id", value: id)
            .is("deleted_at", value: nil)
            .limit(1)
            .execute()
            .value
        return try await hydrate(rows).first
    }

    func fetchHiddenMomentIDs() async throws -> Set<UUID> {
        let session = try await client.auth.session
        guard session.user.id == currentUserIDValue else {
            throw MomentServiceError.accountChanged
        }
        let rows: [HiddenMomentIDRow] = try await client
            .rpc(
                "list_hidden_moment_ids",
                params: RelationshipParameters(targetRelationshipID: relationshipID)
            )
            .execute()
            .value
        return Set(rows.map(\.momentClientID))
    }

    func fetchMomentSyncHints(after momentID: UUID?, limit: Int) async throws
        -> [MomentSyncHint]
    {
        let session = try await client.auth.session
        guard session.user.id == currentUserIDValue else {
            throw MomentServiceError.accountChanged
        }
        let rows: [MomentSyncHintRow] = try await client
            .rpc(
                "list_moment_sync_hints",
                params: MomentSyncHintPageParameters(
                    targetRelationshipID: relationshipID,
                    afterMomentClientID: momentID,
                    targetLimit: limit
                )
            )
            .execute()
            .value
        return rows.map(\.hint)
    }

    func fetchRecentlyDeletedMoments() async throws -> [RecentlyDeletedMoment] {
        let session = try await client.auth.session
        guard session.user.id == currentUserIDValue else {
            throw MomentServiceError.accountChanged
        }
        let rows: [MomentRow] = try await client
            .rpc(
                "list_recently_deleted_moments",
                params: RelationshipParameters(targetRelationshipID: relationshipID)
            )
            .execute()
            .value
        let hydrated = try await hydrate(rows)
        let momentByID = Dictionary(uniqueKeysWithValues: hydrated.map { ($0.id, $0) })
        return try rows.map { row in
            guard let deletedAt = row.deletedAt,
                  let purgeAfter = row.purgeAfter,
                  let moment = momentByID[row.clientID]
            else {
                throw MomentServiceError.invalidServerMoment
            }
            return RecentlyDeletedMoment(
                moment: moment,
                deletedAt: deletedAt,
                purgeAfter: purgeAfter
            )
        }
    }

    private func hydrate(_ rows: [MomentRow]) async throws -> [Moment] {
        guard !rows.isEmpty else { return [] }
        let momentIDs = rows.map(\.clientID)
        let responseRows: [MomentResponseRow] = try await client
            .from("moment_responses")
            .select(
                "moment_client_id,client_id,responder_user_id,kind,emoji_value,text_content,created_at"
            )
            .eq("relationship_id", value: relationshipID)
            .in("moment_client_id", values: momentIDs)
            .order("created_at", ascending: true)
            .execute()
            .value
        let answerRows: [MomentQuestionAnswerRow] = try await client
            .from("moment_question_answers")
            .select(
                "moment_client_id,client_id,answerer_user_id,answer_content,created_at,removed_at"
            )
            .eq("relationship_id", value: relationshipID)
            .in("moment_client_id", values: momentIDs)
            .order("created_at", ascending: true)
            .execute()
            .value

        let responses = try Dictionary(grouping: responseRows, by: \.momentClientID)
            .mapValues { try $0.map { try $0.response() } }
        let answers = Dictionary(grouping: answerRows, by: \.momentClientID)
            .mapValues { $0.map { $0.answer() } }
        return try rows.map {
            try $0.moment(
                responses: responses[$0.clientID] ?? [],
                questionAnswers: answers[$0.clientID] ?? []
            )
        }
    }

    private static let cursorDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func createMoment(_ draft: MomentDraft, clientID: UUID) async throws -> Moment {
        _ = try await client.auth.session
        let parameters: CreateMomentParameters
        var uploadedPath: String?

        switch draft {
        case let .mood(mood):
            parameters = CreateMomentParameters(
                targetRelationshipID: relationshipID,
                targetClientID: clientID,
                targetKind: "mood",
                targetMoodValue: mood.rawValue,
                targetTextContent: nil,
                targetMediaByteSize: nil
            )
        case let .text(body):
            guard let body = MomentDraftPolicy.normalizedText(body) else {
                throw MomentServiceError.invalidDraft
            }
            parameters = CreateMomentParameters(
                targetRelationshipID: relationshipID,
                targetClientID: clientID,
                targetKind: "text",
                targetMoodValue: nil,
                targetTextContent: body,
                targetMediaByteSize: nil
            )
        case let .photo(data):
            guard !data.isEmpty else { throw MomentServiceError.invalidDraft }
            let path = photoPath(momentID: clientID)
            try await client.storage
                .from(Self.photoBucket)
                .upload(
                    path,
                    data: data,
                    options: FileOptions(contentType: "image/jpeg", upsert: false)
                )
            uploadedPath = path
            parameters = CreateMomentParameters(
                targetRelationshipID: relationshipID,
                targetClientID: clientID,
                targetKind: "photo",
                targetMoodValue: nil,
                targetTextContent: nil,
                targetMediaByteSize: data.count
            )
        }

        do {
            let rows: [MomentRow] = try await client
                .rpc("create_moment", params: parameters)
                .execute()
                .value
            guard let row = rows.first else { throw MomentServiceError.missingCreatedMoment }
            return try row.moment()
        } catch {
            if let uploadedPath {
                _ = try? await client.storage
                    .from(Self.photoBucket)
                    .remove(paths: [uploadedPath])
            }
            throw error
        }
    }

    func createQuestion(
        _ draft: MomentQuestionDraft,
        momentClientID: UUID,
        answerClientID: UUID
    ) async throws -> Moment {
        _ = try await client.auth.session
        guard let answer = MomentQuestionPolicy.normalizedAnswer(draft.answer),
              MomentQuestionPrompt.accepted.contains(where: { $0.id == draft.questionKey })
        else {
            throw MomentServiceError.invalidDraft
        }
        let parameters = CreateQuestionMomentParameters(
            targetRelationshipID: relationshipID,
            targetMomentClientID: momentClientID,
            targetQuestionKey: draft.questionKey,
            targetAnswerClientID: answerClientID,
            targetAnswerContent: answer
        )
        try await client.rpc("create_question_moment", params: parameters).execute()
        guard let moment = try await fetchMoment(id: momentClientID) else {
            throw MomentServiceError.missingCreatedMoment
        }
        return moment
    }

    func createResponse(
        to momentID: UUID,
        draft: MomentResponseDraft,
        clientID: UUID
    ) async throws -> MomentResponse {
        _ = try await client.auth.session
        let parameters: CreateMomentResponseParameters
        switch draft {
        case let .emoji(emoji):
            parameters = CreateMomentResponseParameters(
                targetRelationshipID: relationshipID,
                targetMomentClientID: momentID,
                targetClientID: clientID,
                targetKind: "emoji",
                targetEmojiValue: emoji.rawValue,
                targetTextContent: nil
            )
        case let .text(value):
            guard let value = MomentResponsePolicy.normalizedText(value) else {
                throw MomentServiceError.invalidDraft
            }
            parameters = CreateMomentResponseParameters(
                targetRelationshipID: relationshipID,
                targetMomentClientID: momentID,
                targetClientID: clientID,
                targetKind: "text",
                targetEmojiValue: nil,
                targetTextContent: value
            )
        }
        let rows: [MomentResponseRow] = try await client
            .rpc("create_moment_response", params: parameters)
            .execute()
            .value
        guard let row = rows.first else { throw MomentServiceError.missingCreatedResponse }
        return try row.response()
    }

    func answerQuestion(momentID: UUID, answer: String, clientID: UUID) async throws
        -> MomentQuestionAnswer
    {
        _ = try await client.auth.session
        guard let answer = MomentQuestionPolicy.normalizedAnswer(answer) else {
            throw MomentServiceError.invalidDraft
        }
        let parameters = AnswerMomentQuestionParameters(
            targetRelationshipID: relationshipID,
            targetMomentClientID: momentID,
            targetAnswerClientID: clientID,
            targetAnswerContent: answer
        )
        let rows: [MomentQuestionAnswerRow] = try await client
            .rpc("answer_moment_question", params: parameters)
            .execute()
            .value
        guard let row = rows.first else { throw MomentServiceError.missingCreatedAnswer }
        return row.answer()
    }

    func deleteMoment(id: UUID, operationID: UUID) async throws -> RecentlyDeletedMoment {
        let session = try await client.auth.session
        guard session.user.id == currentUserIDValue else {
            throw MomentServiceError.accountChanged
        }
        let rows: [MomentRow] = try await client
            .rpc(
                "delete_moment",
                params: MomentOperationParameters(
                    targetRelationshipID: relationshipID,
                    targetMomentClientID: id,
                    targetOperationID: operationID
                )
            )
            .execute()
            .value
        guard let row = rows.first else {
            throw MomentServiceError.operationSuperseded
        }
        guard let deletedAt = row.deletedAt, let purgeAfter = row.purgeAfter else {
            throw MomentServiceError.operationSuperseded
        }
        guard let moment = try await hydrate([row]).first else {
            throw MomentServiceError.missingUpdatedMoment
        }
        let deleted = RecentlyDeletedMoment(
            moment: moment,
            deletedAt: deletedAt,
            purgeAfter: purgeAfter
        )
        return deleted
    }

    func restoreMoment(id: UUID, operationID: UUID) async throws -> Moment {
        let session = try await client.auth.session
        guard session.user.id == currentUserIDValue else {
            throw MomentServiceError.accountChanged
        }
        let rows: [MomentRow] = try await client
            .rpc(
                "restore_moment",
                params: MomentOperationParameters(
                    targetRelationshipID: relationshipID,
                    targetMomentClientID: id,
                    targetOperationID: operationID
                )
            )
            .execute()
            .value
        guard let row = rows.first else {
            throw MomentServiceError.operationSuperseded
        }
        guard row.deletedAt == nil else {
            throw MomentServiceError.operationSuperseded
        }
        guard let moment = try await hydrate([row]).first else {
            throw MomentServiceError.missingUpdatedMoment
        }
        return moment
    }

    func removeResponse(momentID: UUID, responseID: UUID, operationID: UUID) async throws
        -> Moment?
    {
        try await mutateMoment(
            rpc: "remove_moment_response",
            parameters: MomentInteractionOperationParameters(
                targetRelationshipID: relationshipID,
                targetMomentClientID: momentID,
                targetInteractionClientID: responseID,
                targetOperationID: operationID
            )
        )
    }

    func removeAnswer(momentID: UUID, answerID: UUID, operationID: UUID) async throws -> Moment? {
        try await mutateMoment(
            rpc: "remove_moment_answer",
            parameters: MomentInteractionOperationParameters(
                targetRelationshipID: relationshipID,
                targetMomentClientID: momentID,
                targetInteractionClientID: answerID,
                targetOperationID: operationID
            )
        )
    }

    private func mutateMoment<Parameters: Encodable>(
        rpc: String,
        parameters: Parameters
    ) async throws -> Moment? {
        let session = try await client.auth.session
        guard session.user.id == currentUserIDValue else {
            throw MomentServiceError.accountChanged
        }
        let rows: [MomentRow] = try await client
            .rpc(rpc, params: parameters)
            .execute()
            .value
        return try await hydrate(Array(rows.prefix(1))).first
    }

    func photoData(for moment: Moment) async throws -> Data {
        do {
            let session = try await client.auth.session
            guard session.user.id == currentUserIDValue else {
                throw MomentServiceError.accountChanged
            }
            let bucket: String
            let path: String
            if let sourceMessageID = moment.sourceMessageID {
                bucket = "couplespace-w1-photos"
                path = relationshipID.uuidString.lowercased()
                    + "/" + sourceMessageID.uuidString.lowercased() + ".jpg"
            } else {
                bucket = Self.photoBucket
                path = photoPath(momentID: moment.id)
            }
            let data = try await client.storage.from(bucket).download(path: path)
            try? snapshotStore.savePhoto(
                data,
                userID: currentUserIDValue,
                relationshipID: relationshipID,
                momentID: moment.id
            )
            return data
        } catch {
            if let cached = try? snapshotStore.loadPhoto(
                userID: currentUserIDValue,
                relationshipID: relationshipID,
                momentID: moment.id
            ) {
                return cached
            }
            throw error
        }
    }

    func startObservingChanges(
        _ onChange: @escaping @MainActor (MomentRemoteChange) async -> Void
    ) async throws {
        await stopObservingChanges()

        let session = try await client.auth.session
        guard session.user.id == currentUserIDValue else {
            throw MomentServiceError.accountChanged
        }
        await client.realtimeV2.setAuth(session.accessToken)

        let channel = client.channel(
            "relationship:\(relationshipID.uuidString.lowercased())"
        ) { config in
            config.isPrivate = true
        }
        let changes = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "moments",
            filter: .eq("relationship_id", value: relationshipID.uuidString.lowercased())
        )
        let responseChanges = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "moment_responses",
            filter: .eq("relationship_id", value: relationshipID.uuidString.lowercased())
        )
        let answerChanges = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "moment_question_answers",
            filter: .eq("relationship_id", value: relationshipID.uuidString.lowercased())
        )
        let lifecycleChanges = channel.broadcastStream(event: "moment-lifecycle")
        realtimeChannel = channel
        realtimeTasks = [changes, responseChanges, answerChanges].map { stream in
            Task {
                for await _ in stream {
                    guard !Task.isCancelled else { return }
                    await onChange(.reloadFirstPage)
                }
            }
        }
        realtimeTasks.append(
            Task {
                for await message in lifecycleChanges {
                    guard !Task.isCancelled else { return }
                    guard let payload = message["payload"]?.objectValue,
                          let lifecycle = try? payload.decode(
                              as: MomentLifecycleBroadcast.self
                          )
                    else { continue }
                    switch lifecycle.changeKind {
                    case "deleted":
                        await onChange(.momentDeleted(lifecycle.momentClientID))
                    case "restored", "response_removed", "answer_removed":
                        await onChange(.momentChanged(lifecycle.momentClientID))
                    default:
                        continue
                    }
                }
            }
        )

        do {
            try await channel.subscribeWithError()
        } catch {
            realtimeTasks.forEach { $0.cancel() }
            realtimeTasks = []
            realtimeChannel = nil
            await client.removeChannel(channel)
            throw error
        }
    }

    func stopObservingChanges() async {
        realtimeTasks.forEach { $0.cancel() }
        realtimeTasks = []
        if let realtimeChannel {
            await client.removeChannel(realtimeChannel)
            self.realtimeChannel = nil
        }
    }

    private func photoPath(momentID: UUID) -> String {
        "\(relationshipID.uuidString.lowercased())/\(momentID.uuidString.lowercased()).jpg"
    }

    private func evictCachedMoment(_ momentID: UUID) {
        snapshotStore.removeMoment(
            userID: currentUserIDValue,
            relationshipID: relationshipID,
            momentID: momentID
        )
    }

}

enum MomentServiceError: LocalizedError {
    case invalidDraft
    case invalidServerMoment
    case invalidServerResponse
    case missingCreatedMoment
    case missingCreatedResponse
    case missingCreatedAnswer
    case missingUpdatedMoment
    case accountChanged
    case operationConflict
    case operationSuperseded
    case notAuthorized
    case restoreUnavailable
    case missingInteraction

    var errorDescription: String? {
        switch self {
        case .invalidDraft: "Moment 內容不完整。"
        case .invalidServerMoment: "無法讀取這筆 Moment。"
        case .invalidServerResponse: "無法讀取這筆 Moment 回應。"
        case .missingCreatedMoment: "伺服器未回傳新建立的 Moment。"
        case .missingCreatedResponse: "伺服器未回傳新建立的回應。"
        case .missingCreatedAnswer: "伺服器未回傳新建立的回答。"
        case .missingUpdatedMoment: "伺服器未回傳更新後的 Moment。"
        case .accountChanged: "目前登入帳號已變更。"
        case .operationConflict: "這個操作識別碼已用於其他操作。"
        case .operationSuperseded: "這個操作已被較新的狀態取代。"
        case .notAuthorized: "你沒有權限執行這個操作。"
        case .restoreUnavailable: "這筆 Moment 已無法復原。"
        case .missingInteraction: "找不到可移除的互動。"
        }
    }
}

@MainActor
final class InMemoryMomentService: MomentRemoteServing {
    private let userID: UUID
    private var moments: [Moment]
    private var recentlyDeletedByMomentID: [UUID: RecentlyDeletedMoment]
    private var photoDataByMomentID: [UUID: Data]
    private var cachedPhotoDataByMomentID: [UUID: Data]
    private var operationReceipts: [UUID: OperationReceipt] = [:]
    private var pendingOperationIDs: [MomentOperationIdentity: UUID] = [:]
    private var syncHintsByMomentID: [UUID: MomentSyncHint] = [:]
    private var observation: (@MainActor (MomentRemoteChange) async -> Void)?
    private let now: () -> Date

    private enum OperationReceipt {
        case delete(momentID: UUID)
        case restore(momentID: UUID)
        case removeResponse(momentID: UUID, responseID: UUID)
        case removeAnswer(momentID: UUID, answerID: UUID)
    }

    init(
        userID: UUID = UUID(),
        moments: [Moment] = [],
        photoDataByMomentID: [UUID: Data] = [:],
        recentlyDeletedMoments: [RecentlyDeletedMoment] = [],
        now: @escaping () -> Date = { Date() }
    ) {
        self.userID = userID
        self.moments = moments
        self.photoDataByMomentID = photoDataByMomentID
        cachedPhotoDataByMomentID = photoDataByMomentID
        recentlyDeletedByMomentID = Dictionary(
            uniqueKeysWithValues: recentlyDeletedMoments.map { ($0.id, $0) }
        )
        for deleted in recentlyDeletedMoments {
            cachedPhotoDataByMomentID[deleted.id] = nil
            syncHintsByMomentID[deleted.id] = MomentSyncHint(
                momentID: deleted.id,
                isDeleted: true,
                sourceMessageID: deleted.moment.sourceMessageID,
                revision: 1
            )
        }
        self.now = now
    }

    func currentUserID() async throws -> UUID { userID }

    func cachedMoments() -> [Moment]? { moments }

    func cachedPhotoData(for momentID: UUID) -> Data? {
        cachedPhotoDataByMomentID[momentID]
    }

    func removeCachedMomentData(for momentID: UUID) {
        cachedPhotoDataByMomentID[momentID] = nil
    }

    func fetchMoments() async throws -> [Moment] { moments }

    func fetchMoment(id: UUID) async throws -> Moment? {
        moments.first(where: { $0.id == id })
    }

    func fetchHiddenMomentIDs() async throws -> Set<UUID> {
        Set(recentlyDeletedByMomentID.keys)
    }

    func fetchMomentSyncHints(after momentID: UUID?, limit: Int) async throws
        -> [MomentSyncHint]
    {
        let ordered = syncHintsByMomentID.values.sorted {
            $0.momentID.uuidString < $1.momentID.uuidString
        }
        return Array(ordered.lazy.filter {
            guard let momentID else { return true }
            return $0.momentID.uuidString > momentID.uuidString
        }.prefix(limit))
    }

    func operationID(for identity: MomentOperationIdentity) throws -> UUID {
        if let existing = pendingOperationIDs[identity] { return existing }
        let created = UUID()
        pendingOperationIDs[identity] = created
        return created
    }

    func clearOperationID(for identity: MomentOperationIdentity) {
        pendingOperationIDs[identity] = nil
    }

    func fetchRecentlyDeletedMoments() async throws -> [RecentlyDeletedMoment] {
        recentlyDeletedByMomentID.values
            .filter { $0.moment.creatorUserID == userID && now() < $0.purgeAfter }
            .sorted { $0.deletedAt > $1.deletedAt }
    }

    func createMoment(_ draft: MomentDraft, clientID: UUID) async throws -> Moment {
        let content: MomentContent
        switch draft {
        case let .mood(mood): content = .mood(mood)
        case let .text(text):
            guard let text = MomentDraftPolicy.normalizedText(text) else {
                throw MomentServiceError.invalidDraft
            }
            content = .text(text)
        case let .photo(data):
            content = .photo
            photoDataByMomentID[clientID] = data
        }
        let moment = Moment(
            id: clientID,
            creatorUserID: userID,
            content: content,
            createdAt: .now
        )
        moments.insert(moment, at: 0)
        await observation?(.reloadFirstPage)
        return moment
    }

    func createQuestion(
        _ draft: MomentQuestionDraft,
        momentClientID: UUID,
        answerClientID: UUID
    ) async throws -> Moment {
        guard let prompt = MomentQuestionPrompt.accepted.first(where: { $0.id == draft.questionKey }),
              let answer = MomentQuestionPolicy.normalizedAnswer(draft.answer)
        else {
            throw MomentServiceError.invalidDraft
        }
        let questionAnswer = MomentQuestionAnswer(
            id: answerClientID,
            answererUserID: userID,
            content: answer,
            createdAt: .now
        )
        let moment = Moment(
            id: momentClientID,
            creatorUserID: userID,
            content: .question(MomentQuestion(key: prompt.id, prompt: prompt.prompt)),
            createdAt: .now,
            questionAnswers: [questionAnswer]
        )
        moments.insert(moment, at: 0)
        await observation?(.reloadFirstPage)
        return moment
    }

    func createResponse(
        to momentID: UUID,
        draft: MomentResponseDraft,
        clientID: UUID
    ) async throws -> MomentResponse {
        guard let index = moments.firstIndex(where: { $0.id == momentID }),
              moments[index].creatorUserID != userID,
              moments[index].responses.isEmpty
        else {
            throw MomentServiceError.invalidDraft
        }
        let content: MomentResponseContent
        switch draft {
        case let .emoji(emoji):
            content = .emoji(emoji)
        case let .text(value):
            guard let value = MomentResponsePolicy.normalizedText(value) else {
                throw MomentServiceError.invalidDraft
            }
            content = .text(value)
        }
        let response = MomentResponse(
            id: clientID,
            responderUserID: userID,
            content: content,
            createdAt: .now
        )
        moments[index].responses.append(response)
        await observation?(.reloadFirstPage)
        return response
    }

    func answerQuestion(momentID: UUID, answer: String, clientID: UUID) async throws
        -> MomentQuestionAnswer
    {
        guard let index = moments.firstIndex(where: { $0.id == momentID }),
              moments[index].creatorUserID != userID,
              !moments[index].questionAnswers.contains(where: { $0.answererUserID == userID }),
              let answer = MomentQuestionPolicy.normalizedAnswer(answer)
        else {
            throw MomentServiceError.invalidDraft
        }
        let questionAnswer = MomentQuestionAnswer(
            id: clientID,
            answererUserID: userID,
            content: answer,
            createdAt: .now
        )
        moments[index].questionAnswers.append(questionAnswer)
        await observation?(.reloadFirstPage)
        return questionAnswer
    }

    func deleteMoment(id: UUID, operationID: UUID) async throws -> RecentlyDeletedMoment {
        if let receipt = operationReceipts[operationID] {
            guard case let .delete(receiptMomentID) = receipt,
                  receiptMomentID == id
            else { throw MomentServiceError.operationConflict }
            if let deleted = recentlyDeletedByMomentID[id] { return deleted }
            if moments.contains(where: { $0.id == id }) {
                throw MomentServiceError.operationSuperseded
            }
            throw MomentServiceError.missingUpdatedMoment
        }
        guard let index = moments.firstIndex(where: { $0.id == id }) else {
            throw MomentServiceError.missingUpdatedMoment
        }
        guard moments[index].creatorUserID == userID else {
            throw MomentServiceError.notAuthorized
        }
        let deletedAt = now()
        let deleted = RecentlyDeletedMoment(
            moment: moments.remove(at: index),
            deletedAt: deletedAt,
            purgeAfter: deletedAt.addingTimeInterval(30 * 24 * 60 * 60)
        )
        recentlyDeletedByMomentID[id] = deleted
        cachedPhotoDataByMomentID[id] = nil
        operationReceipts[operationID] = .delete(momentID: id)
        recordSyncHint(for: deleted.moment, isDeleted: true)
        await observation?(.momentDeleted(id))
        return deleted
    }

    func restoreMoment(id: UUID, operationID: UUID) async throws -> Moment {
        if let receipt = operationReceipts[operationID] {
            guard case let .restore(receiptMomentID) = receipt,
                  receiptMomentID == id
            else { throw MomentServiceError.operationConflict }
            if let moment = moments.first(where: { $0.id == id }) { return moment }
            if recentlyDeletedByMomentID[id] != nil {
                throw MomentServiceError.operationSuperseded
            }
            throw MomentServiceError.missingUpdatedMoment
        }
        guard let deleted = recentlyDeletedByMomentID[id],
              deleted.moment.creatorUserID == userID,
              now() < deleted.purgeAfter
        else {
            throw MomentServiceError.restoreUnavailable
        }
        recentlyDeletedByMomentID[id] = nil
        moments.removeAll { $0.id == id }
        moments.append(deleted.moment)
        sortMoments()
        operationReceipts[operationID] = .restore(momentID: id)
        recordSyncHint(for: deleted.moment, isDeleted: false)
        await observation?(.momentChanged(id))
        return deleted.moment
    }

    func removeResponse(momentID: UUID, responseID: UUID, operationID: UUID) async throws
        -> Moment?
    {
        if let receipt = operationReceipts[operationID] {
            guard case let .removeResponse(
                receiptMomentID,
                receiptResponseID
            ) = receipt,
                receiptMomentID == momentID,
                receiptResponseID == responseID
            else { throw MomentServiceError.operationConflict }
            return moments.first(where: { $0.id == momentID })
        }
        guard let momentIndex = moments.firstIndex(where: { $0.id == momentID }),
              let responseIndex = moments[momentIndex].responses.firstIndex(
                  where: { $0.id == responseID }
              )
        else {
            throw MomentServiceError.missingInteraction
        }
        guard moments[momentIndex].responses[responseIndex].responderUserID == userID else {
            throw MomentServiceError.notAuthorized
        }
        moments[momentIndex].responses.remove(at: responseIndex)
        let updated = moments[momentIndex]
        operationReceipts[operationID] = .removeResponse(
            momentID: momentID,
            responseID: responseID
        )
        recordSyncHint(for: updated, isDeleted: false)
        await observation?(.momentChanged(momentID))
        return updated
    }

    func removeAnswer(momentID: UUID, answerID: UUID, operationID: UUID) async throws -> Moment? {
        if let receipt = operationReceipts[operationID] {
            guard case let .removeAnswer(receiptMomentID, receiptAnswerID) = receipt,
                  receiptMomentID == momentID,
                  receiptAnswerID == answerID
            else { throw MomentServiceError.operationConflict }
            return moments.first(where: { $0.id == momentID })
        }
        guard let momentIndex = moments.firstIndex(where: { $0.id == momentID }),
              let answerIndex = moments[momentIndex].questionAnswers.firstIndex(
                  where: { $0.id == answerID }
              )
        else {
            throw MomentServiceError.missingInteraction
        }
        let answer = moments[momentIndex].questionAnswers[answerIndex]
        guard answer.answererUserID == userID else {
            throw MomentServiceError.notAuthorized
        }
        guard !answer.isRemoved else {
            throw MomentServiceError.missingInteraction
        }
        moments[momentIndex].questionAnswers[answerIndex] = MomentQuestionAnswer(
            id: answer.id,
            answererUserID: answer.answererUserID,
            content: nil,
            createdAt: answer.createdAt,
            removedAt: now()
        )
        let updated = moments[momentIndex]
        operationReceipts[operationID] = .removeAnswer(
            momentID: momentID,
            answerID: answerID
        )
        recordSyncHint(for: updated, isDeleted: false)
        await observation?(.momentChanged(momentID))
        return updated
    }

    func photoData(for moment: Moment) async throws -> Data {
        guard let data = photoDataByMomentID[moment.id] else {
            throw MomentServiceError.invalidServerMoment
        }
        cachedPhotoDataByMomentID[moment.id] = data
        return data
    }

    func startObservingChanges(
        _ onChange: @escaping @MainActor (MomentRemoteChange) async -> Void
    ) async throws {
        observation = onChange
    }

    func stopObservingChanges() async {
        observation = nil
    }

    private func sortMoments() {
        moments.sort {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString > $1.id.uuidString
        }
    }

    private func recordSyncHint(for moment: Moment, isDeleted: Bool) {
        let nextRevision = (syncHintsByMomentID[moment.id]?.revision ?? 0) + 1
        syncHintsByMomentID[moment.id] = MomentSyncHint(
            momentID: moment.id,
            isDeleted: isDeleted,
            sourceMessageID: moment.sourceMessageID,
            revision: nextRevision
        )
    }
}
