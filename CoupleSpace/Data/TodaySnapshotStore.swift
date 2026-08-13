import Foundation

struct TodaySnapshotStore {
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let photoRootURL: URL
    private let momentKeyPrefix = "couplespace.today-moments.v1."
    private let togetherNowKeyPrefix = "couplespace.today-together-now.v1."

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        photoRootURL: URL? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.photoRootURL = photoRootURL
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("CoupleSpace/TodayPhotos", isDirectory: true)
    }

    func loadMoments(userID: UUID, relationshipID: UUID) throws -> [Moment]? {
        guard let data = defaults.data(forKey: momentKey(userID: userID, relationshipID: relationshipID)) else {
            return nil
        }
        return try JSONDecoder().decode([Moment].self, from: data)
    }

    func saveMoments(_ moments: [Moment], userID: UUID, relationshipID: UUID) throws {
        defaults.set(
            try JSONEncoder().encode(moments),
            forKey: momentKey(userID: userID, relationshipID: relationshipID)
        )
    }

    func loadTogetherNow(userID: UUID, relationshipID: UUID) throws -> TogetherNowSnapshot? {
        guard let data = defaults.data(forKey: togetherNowKey(userID: userID, relationshipID: relationshipID)) else {
            return nil
        }
        return try JSONDecoder().decode(TogetherNowSnapshot.self, from: data)
    }

    func saveTogetherNow(
        _ snapshot: TogetherNowSnapshot,
        userID: UUID,
        relationshipID: UUID
    ) throws {
        defaults.set(
            try JSONEncoder().encode(snapshot),
            forKey: togetherNowKey(userID: userID, relationshipID: relationshipID)
        )
    }

    func loadPhoto(userID: UUID, relationshipID: UUID, momentID: UUID) throws -> Data? {
        let url = photoURL(userID: userID, relationshipID: relationshipID, momentID: momentID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func savePhoto(_ data: Data, userID: UUID, relationshipID: UUID, momentID: UUID) throws {
        let url = photoURL(userID: userID, relationshipID: relationshipID, momentID: momentID)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    func clearAll(userID: UUID) {
        let userToken = userID.uuidString.lowercased()
        defaults.dictionaryRepresentation().keys
            .filter {
                $0.hasPrefix(momentKeyPrefix + userToken + ".")
                    || $0.hasPrefix(togetherNowKeyPrefix + userToken + ".")
            }
            .forEach(defaults.removeObject(forKey:))
        try? fileManager.removeItem(at: photoRootURL.appendingPathComponent(userToken, isDirectory: true))
    }

    private func momentKey(userID: UUID, relationshipID: UUID) -> String {
        scopedKey(prefix: momentKeyPrefix, userID: userID, relationshipID: relationshipID)
    }

    private func togetherNowKey(userID: UUID, relationshipID: UUID) -> String {
        scopedKey(prefix: togetherNowKeyPrefix, userID: userID, relationshipID: relationshipID)
    }

    private func scopedKey(prefix: String, userID: UUID, relationshipID: UUID) -> String {
        prefix
            + userID.uuidString.lowercased()
            + "."
            + relationshipID.uuidString.lowercased()
    }

    private func photoURL(userID: UUID, relationshipID: UUID, momentID: UUID) -> URL {
        photoRootURL
            .appendingPathComponent(userID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(relationshipID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(momentID.uuidString.lowercased() + ".jpg")
    }
}
