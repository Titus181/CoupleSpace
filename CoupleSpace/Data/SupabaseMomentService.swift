import Foundation
import Supabase

@MainActor
protocol MomentRemoteServing: AnyObject {
    func currentUserID() async throws -> UUID
    func fetchMoments() async throws -> [Moment]
    func createMoment(_ draft: MomentDraft, clientID: UUID) async throws -> Moment
    func photoData(for momentID: UUID) async throws -> Data
    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws
    func stopObservingChanges() async
}

private struct MomentRow: Decodable {
    let clientID: UUID
    let creatorUserID: UUID
    let kind: String
    let moodValue: String?
    let textContent: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case creatorUserID = "creator_user_id"
        case kind
        case moodValue = "mood_value"
        case textContent = "text_content"
        case createdAt = "created_at"
    }

    func moment() throws -> Moment {
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
        default:
            throw MomentServiceError.invalidServerMoment
        }

        return Moment(
            id: clientID,
            creatorUserID: creatorUserID,
            content: content,
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

@MainActor
final class SupabaseMomentService: MomentRemoteServing {
    private static let photoBucket = "couplespace-moment-photos"

    private let client: SupabaseClient
    private let relationshipID: UUID
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTask: Task<Void, Never>?

    init(client: SupabaseClient, relationshipID: UUID) {
        self.client = client
        self.relationshipID = relationshipID
    }

    func currentUserID() async throws -> UUID {
        try await client.auth.session.user.id
    }

    func fetchMoments() async throws -> [Moment] {
        _ = try await client.auth.session
        let rows: [MomentRow] = try await client
            .from("moments")
            .select("client_id,creator_user_id,kind,mood_value,text_content,created_at")
            .eq("relationship_id", value: relationshipID)
            .order("created_at", ascending: false)
            .order("client_id", ascending: false)
            .execute()
            .value
        return try rows.map { try $0.moment() }
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

    func photoData(for momentID: UUID) async throws -> Data {
        _ = try await client.auth.session
        return try await client.storage
            .from(Self.photoBucket)
            .download(path: photoPath(momentID: momentID))
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
        realtimeChannel = channel
        realtimeTask = Task {
            for await _ in changes {
                guard !Task.isCancelled else { return }
                await onChange()
            }
        }

        do {
            try await channel.subscribeWithError()
        } catch {
            realtimeTask?.cancel()
            realtimeTask = nil
            realtimeChannel = nil
            await client.removeChannel(channel)
            throw error
        }
    }

    func stopObservingChanges() async {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let realtimeChannel {
            await client.removeChannel(realtimeChannel)
            self.realtimeChannel = nil
        }
    }

    private func photoPath(momentID: UUID) -> String {
        "\(relationshipID.uuidString.lowercased())/\(momentID.uuidString.lowercased()).jpg"
    }
}

private enum MomentServiceError: LocalizedError {
    case invalidDraft
    case invalidServerMoment
    case missingCreatedMoment

    var errorDescription: String? {
        switch self {
        case .invalidDraft: "Moment 內容不完整。"
        case .invalidServerMoment: "無法讀取這筆 Moment。"
        case .missingCreatedMoment: "伺服器未回傳新建立的 Moment。"
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

    func photoData(for momentID: UUID) async throws -> Data {
        guard let data = photoDataByMomentID[momentID] else {
            throw MomentServiceError.invalidServerMoment
        }
        return data
    }

    func startObservingChanges(_ onChange: @escaping @MainActor () async -> Void) async throws {}
    func stopObservingChanges() async {}
}
