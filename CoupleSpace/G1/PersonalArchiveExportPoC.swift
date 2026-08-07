import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct PersonalArchiveExportItem: Codable, Equatable, Sendable {
    let clientID: UUID
    let kind: String
    let createdAt: Date
    let text: String?
    let photoFile: String?

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case kind
        case createdAt = "created_at"
        case text
        case photoFile = "photo_file"
    }
}

struct PersonalArchiveExportManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let relationshipID: UUID
    let exportedAt: Date
    let items: [PersonalArchiveExportItem]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case relationshipID = "relationship_id"
        case exportedAt = "exported_at"
        case items
    }
}

enum PersonalArchiveExportError: Error, Equatable {
    case duplicateItem
    case invalidItemContent
    case photoSetMismatch
    case duplicatePhoto
    case insufficientStagingCapacity
    case importUnsupported
}

extension PersonalArchiveExportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .insufficientStagingCapacity:
            return "裝置可用空間不足，未開始下載個人封存照片"
        default:
            return nil
        }
    }
}

enum PersonalArchiveExportCapacityPolicy {
    static func requiredBytes(
        manifestByteCount: Int,
        photoByteSizes: [Int64?]
    ) -> Int64? {
        guard manifestByteCount >= 0,
              photoByteSizes.allSatisfy({ ($0 ?? 0) > 0 }) else {
            return nil
        }

        var total = Int64(manifestByteCount)
        for byteSize in photoByteSizes.compactMap({ $0 }) {
            let addition = total.addingReportingOverflow(byteSize)
            guard !addition.overflow else { return nil }
            total = addition.partialValue
        }
        return total
    }

    static func permitsStaging(requiredBytes: Int64?, availableBytes: Int64?) -> Bool {
        guard let requiredBytes, let availableBytes else { return true }
        return requiredBytes <= availableBytes
    }

    static func availableBytes(
        at directoryURL: URL,
        fileManager: FileManager = .default
    ) -> Int64? {
        guard let number = try? fileManager.attributesOfFileSystem(
            forPath: directoryURL.path
        )[.systemFreeSize] as? NSNumber else {
            return nil
        }
        return number.int64Value
    }
}

struct PersonalArchiveExportPackage: Sendable {
    let manifest: PersonalArchiveExportManifest

    var expectedPhotoIDs: Set<UUID> {
        Set(manifest.items.filter { $0.kind == "photo" }.map(\.clientID))
    }

    init(
        relationshipID: UUID,
        exportedAt: Date,
        items: [PersonalArchiveExportItem]
    ) throws {
        let sortedItems = items.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.clientID.uuidString < $1.clientID.uuidString
        }
        guard Set(sortedItems.map(\.clientID)).count == sortedItems.count else {
            throw PersonalArchiveExportError.duplicateItem
        }
        guard sortedItems.allSatisfy({ item in
            switch item.kind {
            case "message":
                return item.text != nil && item.photoFile == nil
            case "photo":
                return item.text == nil
                    && item.photoFile == Self.photoFileName(clientID: item.clientID)
            default:
                return item.text == nil && item.photoFile == nil
            }
        }) else {
            throw PersonalArchiveExportError.invalidItemContent
        }

        manifest = PersonalArchiveExportManifest(
            schemaVersion: 1,
            relationshipID: relationshipID,
            exportedAt: exportedAt,
            items: sortedItems
        )
    }

    func manifestData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }

    static func photoFileName(clientID: UUID) -> String {
        "\(clientID.uuidString.lowercased()).jpg"
    }
}

struct PersonalArchiveExportStaging {
    static let directoryPrefix = "CoupleSpace-personal-archive-staging-"

    let directoryURL: URL
    private let package: PersonalArchiveExportPackage
    private var writtenPhotoIDs: Set<UUID> = []

    init(
        package: PersonalArchiveExportPackage,
        baseDirectory: URL = FileManager.default.temporaryDirectory
    ) throws {
        self.package = package
        directoryURL = baseDirectory.appendingPathComponent(
            Self.directoryPrefix + UUID().uuidString,
            isDirectory: true
        )

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        do {
            try package.manifestData().write(
                to: directoryURL.appendingPathComponent("manifest.json"),
                options: [.atomic, .completeFileProtection]
            )
            if !package.expectedPhotoIDs.isEmpty {
                try fileManager.createDirectory(
                    at: directoryURL.appendingPathComponent("photos", isDirectory: true),
                    withIntermediateDirectories: false
                )
            }
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw error
        }
    }

    mutating func writePhoto(clientID: UUID, jpegData: Data) throws {
        guard package.expectedPhotoIDs.contains(clientID) else {
            throw PersonalArchiveExportError.photoSetMismatch
        }
        guard writtenPhotoIDs.insert(clientID).inserted else {
            throw PersonalArchiveExportError.duplicatePhoto
        }
        do {
            try jpegData.write(
                to: directoryURL
                    .appendingPathComponent("photos", isDirectory: true)
                    .appendingPathComponent(PersonalArchiveExportPackage.photoFileName(
                        clientID: clientID
                    )),
                options: [.atomic, .completeFileProtection]
            )
        } catch {
            writtenPhotoIDs.remove(clientID)
            throw error
        }
    }

    func fileWrapper(exportFileName: String? = nil) throws -> FileWrapper {
        guard writtenPhotoIDs == package.expectedPhotoIDs else {
            throw PersonalArchiveExportError.photoSetMismatch
        }

        let manifestWrapper = try FileWrapper(
            url: directoryURL.appendingPathComponent("manifest.json"),
            options: []
        )
        manifestWrapper.preferredFilename = "manifest.json"

        var files = ["manifest.json": manifestWrapper]
        if !package.expectedPhotoIDs.isEmpty {
            let photosWrapper = try FileWrapper(
                url: directoryURL.appendingPathComponent("photos", isDirectory: true),
                options: []
            )
            photosWrapper.preferredFilename = "photos"
            files["photos"] = photosWrapper
        }

        let wrapper = FileWrapper(directoryWithFileWrappers: files)
        if let exportFileName {
            wrapper.preferredFilename = exportFileName
        }
        return wrapper
    }

    func remove() throws {
        try FileManager.default.removeItem(at: directoryURL)
    }

    static func cleanupAbandoned(
        in baseDirectory: URL = FileManager.default.temporaryDirectory
    ) throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for url in contents where url.lastPathComponent.hasPrefix(directoryPrefix) {
            guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                continue
            }
            try fileManager.removeItem(at: url)
        }
    }
}

struct PersonalArchiveExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }

    private let rootWrapper: FileWrapper

    init(staging: PersonalArchiveExportStaging, exportFileName: String) throws {
        rootWrapper = try staging.fileWrapper(exportFileName: exportFileName)
    }

    init(configuration: ReadConfiguration) throws {
        throw PersonalArchiveExportError.importUnsupported
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        rootWrapper
    }
}
