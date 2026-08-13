import Foundation
import Supabase

@MainActor
protocol MomentRemoteServing: AnyObject {
    func currentUserID() async throws -> UUID
    func cachedMoments() -> [Moment]?
    func cachedPhotoData(for momentID: UUID) -> Data?
    func fetchMoments() async throws -> [Moment]
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
    func photoData(for momentID: UUID) async throws -> Data
    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws
    func stopObservingChanges() async
}

extension MomentRemoteServing {
    func cachedMoments() -> [Moment]? { nil }
    func cachedPhotoData(for momentID: UUID) -> Data? { nil }
}

private struct MomentRow: Decodable {
    let clientID: UUID
    let creatorUserID: UUID
    let kind: String
    let moodValue: String?
    let textContent: String?
    let questionKey: String?
    let questionPrompt: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case creatorUserID = "creator_user_id"
        case kind
        case moodValue = "mood_value"
        case textContent = "text_content"
        case questionKey = "question_key"
        case questionPrompt = "question_prompt"
        case createdAt = "created_at"
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
    let answerContent: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case momentClientID = "moment_client_id"
        case clientID = "client_id"
        case answererUserID = "answerer_user_id"
        case answerContent = "answer_content"
        case createdAt = "created_at"
    }

    func answer() -> MomentQuestionAnswer {
        MomentQuestionAnswer(
            id: clientID,
            answererUserID: answererUserID,
            content: answerContent,
            createdAt: createdAt
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

@MainActor
final class SupabaseMomentService: MomentRemoteServing {
    private static let photoBucket = "couplespace-moment-photos"

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

    func fetchMoments() async throws -> [Moment] {
        do {
            let moments = try await fetchRemoteMoments()
            try? snapshotStore.saveMoments(
                moments,
                userID: currentUserIDValue,
                relationshipID: relationshipID
            )
            return moments
        } catch {
            if let cached = try? snapshotStore.loadMoments(
                userID: currentUserIDValue,
                relationshipID: relationshipID
            ) {
                return cached
            }
            throw error
        }
    }

    private func fetchRemoteMoments() async throws -> [Moment] {
        let session = try await client.auth.session
        guard session.user.id == currentUserIDValue else {
            throw MomentServiceError.accountChanged
        }
        let rows: [MomentRow] = try await client
            .from("moments")
            .select(
                "client_id,creator_user_id,kind,mood_value,text_content,question_key,question_prompt,created_at"
            )
            .eq("relationship_id", value: relationshipID)
            .order("created_at", ascending: false)
            .order("client_id", ascending: false)
            .execute()
            .value
        let responseRows: [MomentResponseRow] = try await client
            .from("moment_responses")
            .select(
                "moment_client_id,client_id,responder_user_id,kind,emoji_value,text_content,created_at"
            )
            .eq("relationship_id", value: relationshipID)
            .order("created_at", ascending: true)
            .execute()
            .value
        let answerRows: [MomentQuestionAnswerRow] = try await client
            .from("moment_question_answers")
            .select("moment_client_id,client_id,answerer_user_id,answer_content,created_at")
            .eq("relationship_id", value: relationshipID)
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
            let moment = try row.moment()
            cache(moment)
            if case let .photo(data) = draft {
                try? snapshotStore.savePhoto(
                    data,
                    userID: currentUserIDValue,
                    relationshipID: relationshipID,
                    momentID: moment.id
                )
            }
            return moment
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
        guard let moment = try await fetchMoments().first(where: { $0.id == momentClientID }) else {
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
        let response = try row.response()
        cache(response, for: momentID)
        return response
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
        let savedAnswer = row.answer()
        cache(savedAnswer, for: momentID)
        return savedAnswer
    }

    func photoData(for momentID: UUID) async throws -> Data {
        do {
            let session = try await client.auth.session
            guard session.user.id == currentUserIDValue else {
                throw MomentServiceError.accountChanged
            }
            let data = try await client.storage
                .from(Self.photoBucket)
                .download(path: photoPath(momentID: momentID))
            try? snapshotStore.savePhoto(
                data,
                userID: currentUserIDValue,
                relationshipID: relationshipID,
                momentID: momentID
            )
            return data
        } catch {
            if let cached = try? snapshotStore.loadPhoto(
                userID: currentUserIDValue,
                relationshipID: relationshipID,
                momentID: momentID
            ) {
                return cached
            }
            throw error
        }
    }

    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws {
        await stopObservingChanges()

        let channel = client.channel("moments-\(UUID().uuidString.lowercased())")
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
        realtimeChannel = channel
        realtimeTasks = [changes, responseChanges, answerChanges].map { stream in
            Task {
                for await _ in stream {
                    guard !Task.isCancelled else { return }
                    await onChange()
                }
            }
        }

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

    private func cache(_ moment: Moment) {
        var moments = (try? snapshotStore.loadMoments(
            userID: currentUserIDValue,
            relationshipID: relationshipID
        )) ?? []
        moments.removeAll { $0.id == moment.id }
        moments.insert(moment, at: 0)
        try? snapshotStore.saveMoments(
            moments,
            userID: currentUserIDValue,
            relationshipID: relationshipID
        )
    }

    private func cache(_ response: MomentResponse, for momentID: UUID) {
        guard var moments = try? snapshotStore.loadMoments(
            userID: currentUserIDValue,
            relationshipID: relationshipID
        ), let index = moments.firstIndex(where: { $0.id == momentID }) else { return }
        moments[index].responses.removeAll { $0.id == response.id }
        moments[index].responses.append(response)
        try? snapshotStore.saveMoments(
            moments,
            userID: currentUserIDValue,
            relationshipID: relationshipID
        )
    }

    private func cache(_ answer: MomentQuestionAnswer, for momentID: UUID) {
        guard var moments = try? snapshotStore.loadMoments(
            userID: currentUserIDValue,
            relationshipID: relationshipID
        ), let index = moments.firstIndex(where: { $0.id == momentID }) else { return }
        moments[index].questionAnswers.removeAll { $0.id == answer.id }
        moments[index].questionAnswers.append(answer)
        try? snapshotStore.saveMoments(
            moments,
            userID: currentUserIDValue,
            relationshipID: relationshipID
        )
    }
}

private enum MomentServiceError: LocalizedError {
    case invalidDraft
    case invalidServerMoment
    case invalidServerResponse
    case missingCreatedMoment
    case missingCreatedResponse
    case missingCreatedAnswer
    case accountChanged

    var errorDescription: String? {
        switch self {
        case .invalidDraft: "Moment 內容不完整。"
        case .invalidServerMoment: "無法讀取這筆 Moment。"
        case .invalidServerResponse: "無法讀取這筆 Moment 回應。"
        case .missingCreatedMoment: "伺服器未回傳新建立的 Moment。"
        case .missingCreatedResponse: "伺服器未回傳新建立的回應。"
        case .missingCreatedAnswer: "伺服器未回傳新建立的回答。"
        case .accountChanged: "目前登入帳號已變更。"
        }
    }
}

@MainActor
final class InMemoryMomentService: MomentRemoteServing {
    private let userID: UUID
    private var moments: [Moment]
    private var photoDataByMomentID: [UUID: Data]

    init(
        userID: UUID = UUID(),
        moments: [Moment] = [],
        photoDataByMomentID: [UUID: Data] = [:]
    ) {
        self.userID = userID
        self.moments = moments
        self.photoDataByMomentID = photoDataByMomentID
    }

    func currentUserID() async throws -> UUID { userID }

    func fetchMoments() async throws -> [Moment] { moments }

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
        return questionAnswer
    }

    func photoData(for momentID: UUID) async throws -> Data {
        guard let data = photoDataByMomentID[momentID] else {
            throw MomentServiceError.invalidServerMoment
        }
        return data
    }

    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws {}
    func stopObservingChanges() async {}
}
