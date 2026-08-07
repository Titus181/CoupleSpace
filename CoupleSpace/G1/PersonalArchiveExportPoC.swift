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

struct PersonalArchiveExportPhoto: Equatable, Sendable {
    let clientID: UUID
    let jpegData: Data
}

enum PersonalArchiveExportError: Error, Equatable {
    case duplicateItem
    case invalidItemContent
    case photoSetMismatch
    case importUnsupported
}

struct PersonalArchiveExportPackage: Sendable {
    let manifest: PersonalArchiveExportManifest
    let photos: [PersonalArchiveExportPhoto]

    init(
        relationshipID: UUID,
        exportedAt: Date,
        items: [PersonalArchiveExportItem],
        photos: [PersonalArchiveExportPhoto]
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

        let expectedPhotos = Set(
            sortedItems.filter { $0.kind == "photo" }.map(\.clientID)
        )
        let providedPhotos = Set(photos.map(\.clientID))
        guard expectedPhotos == providedPhotos,
              providedPhotos.count == photos.count else {
            throw PersonalArchiveExportError.photoSetMismatch
        }

        manifest = PersonalArchiveExportManifest(
            schemaVersion: 1,
            relationshipID: relationshipID,
            exportedAt: exportedAt,
            items: sortedItems
        )
        self.photos = photos.sorted {
            $0.clientID.uuidString < $1.clientID.uuidString
        }
    }

    func fileWrapper() throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let manifestWrapper = FileWrapper(
            regularFileWithContents: try encoder.encode(manifest)
        )
        manifestWrapper.preferredFilename = "manifest.json"

        var rootFiles = ["manifest.json": manifestWrapper]
        if !photos.isEmpty {
            var photoFiles: [String: FileWrapper] = [:]
            for photo in photos {
                let fileName = Self.photoFileName(clientID: photo.clientID)
                let wrapper = FileWrapper(regularFileWithContents: photo.jpegData)
                wrapper.preferredFilename = fileName
                photoFiles[fileName] = wrapper
            }
            let photosWrapper = FileWrapper(directoryWithFileWrappers: photoFiles)
            photosWrapper.preferredFilename = "photos"
            rootFiles["photos"] = photosWrapper
        }

        return FileWrapper(directoryWithFileWrappers: rootFiles)
    }

    static func photoFileName(clientID: UUID) -> String {
        "\(clientID.uuidString.lowercased()).jpg"
    }
}

struct PersonalArchiveExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }

    private let package: PersonalArchiveExportPackage

    init(package: PersonalArchiveExportPackage) {
        self.package = package
    }

    init(configuration: ReadConfiguration) throws {
        throw PersonalArchiveExportError.importUnsupported
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try package.fileWrapper()
    }
}
