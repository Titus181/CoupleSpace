import Combine
import Foundation
import Supabase

@MainActor
final class PairingModel: ObservableObject {
    @Published private(set) var state: PairingState
    @Published private(set) var isWorking = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var closingPersonalArchive: PersonalArchive?
    @Published private(set) var archiveExportDocument: PersonalArchiveExportDocument?
    @Published private(set) var archiveExportFileName = "CoupleSpace-personal-archive"

    private let service: PairingRemoteServing
    private let removeRelationshipReminders: @MainActor (UUID) async -> Void
    private var sessionGeneration = 0
    private var archiveExportStagingURL: URL?

    init(
        service: PairingRemoteServing,
        initialState: PairingState = .checking,
        removeRelationshipReminders: @escaping @MainActor (UUID) async -> Void = {
            relationshipID in
            await LocalSharedAppointmentReminderScheduler(
                relationshipID: relationshipID
            ).removeAll()
        }
    ) {
        self.service = service
        self.state = initialState
        self.removeRelationshipReminders = removeRelationshipReminders
    }

    convenience init(client: SupabaseClient, initialState: PairingState = .checking) {
        self.init(service: SupabasePairingService(client: client), initialState: initialState)
    }

    func resetForAuthenticatedSession() {
        sessionGeneration += 1
        isWorking = false
        state = .checking
        statusMessage = nil
        closingPersonalArchive = nil
        cleanupArchiveExportStaging()
        archiveExportDocument = nil
    }

    func restoreCachedRelationship(userID: UUID) async {
        guard state == .checking,
              let relationship = await service.cachedRelationship(userID: userID)
        else { return }
        try? await apply(relationship: relationship)
    }

    func refreshForAuthenticatedSession(userID: UUID) async {
        guard let generation = beginOperation() else { return }
        defer { finishOperation(generation: generation) }

        do {
            let relationship = try await service.currentRelationship()
            guard generation == sessionGeneration else { return }
            try await apply(relationship: relationship)
            guard generation == sessionGeneration else { return }
            statusMessage = nil
        } catch {
            guard generation == sessionGeneration else { return }
            if let cachedRelationship = await service.cachedRelationship(userID: userID) {
                guard generation == sessionGeneration else { return }
                try? await apply(relationship: cachedRelationship)
            } else if state == .checking {
                state = .unpaired
            }
            guard generation == sessionGeneration else { return }
            statusMessage = message(for: error)
        }
    }

    func refresh() async {
        guard let generation = beginOperation() else { return }
        defer { finishOperation(generation: generation) }

        do {
            let relationship = try await service.currentRelationship()
            guard generation == sessionGeneration else { return }
            try await apply(relationship: relationship)
            guard generation == sessionGeneration else { return }
            statusMessage = nil
        } catch {
            guard generation == sessionGeneration else { return }
            if state == .checking {
                state = .unpaired
            }
            statusMessage = message(for: error)
        }
    }

    func createOrRetryInvitation() async {
        let previousInvitationToken: UUID?
        if case let .waiting(_, invitation) = state {
            previousInvitationToken = invitation?.token
        } else {
            previousInvitationToken = nil
        }
        guard let generation = beginOperation() else { return }
        defer { finishOperation(generation: generation) }

        do {
            let invitation = try await service.createInvitation()
            guard generation == sessionGeneration else { return }
            state = .waiting(
                PairingRelationship(id: invitation.relationshipID, memberCount: 1),
                invitation: invitation
            )
            if let previousInvitationToken {
                statusMessage = previousInvitationToken == invitation.token
                    ? "目前的邀請仍然有效。"
                    : "已建立新的邀請碼，請重新分享給伴侶。"
            } else {
                statusMessage = "邀請已準備好，可以分享給伴侶。"
            }
        } catch {
            guard generation == sessionGeneration else { return }
            statusMessage = message(for: error)
        }
    }

    func acceptInvitation(rawToken: String) async {
        guard let identifier = PairingInputPolicy.invitationIdentifier(from: rawToken) else {
            statusMessage = "邀請碼格式不正確，請輸入八位碼或完整貼上邀請內容。"
            return
        }
        guard let generation = beginOperation() else { return }
        defer { finishOperation(generation: generation) }

        do {
            let relationshipID = try await service.acceptInvitation(identifier: identifier)
            guard generation == sessionGeneration else { return }
            state = .paired(PairingRelationship(id: relationshipID, memberCount: 2))
            statusMessage = "配對完成。"
        } catch {
            guard generation == sessionGeneration else { return }
            statusMessage = message(for: error)
        }
    }

    func declineInvitation(rawToken: String) async {
        guard let identifier = PairingInputPolicy.invitationIdentifier(from: rawToken) else {
            statusMessage = "邀請碼格式不正確，請輸入八位碼或完整貼上邀請內容。"
            return
        }
        guard let generation = beginOperation() else { return }
        defer { finishOperation(generation: generation) }

        do {
            try await service.declineInvitation(identifier: identifier)
            guard generation == sessionGeneration else { return }
            state = .unpaired
            statusMessage = "已拒絕這份邀請。"
        } catch {
            guard generation == sessionGeneration else { return }
            statusMessage = message(for: error)
        }
    }

    func cancelInvitation() async {
        guard let generation = beginOperation() else { return }
        defer { finishOperation(generation: generation) }

        do {
            try await service.cancelInvitation()
            guard generation == sessionGeneration else { return }
            state = .unpaired
            statusMessage = "已取消邀請，可以改用伴侶的邀請碼。"
        } catch {
            guard generation == sessionGeneration else { return }
            statusMessage = message(for: error)
        }
    }

    func sealPersonalArchive() async {
        guard case let .closing(relationship) = state,
              let generation = beginOperation()
        else { return }
        defer { finishOperation(generation: generation) }

        do {
            let archive = try await service.sealPersonalArchive(
                relationshipID: relationship.id
            )
            guard generation == sessionGeneration else { return }
            closingPersonalArchive = archive
            let refreshedRelationship = try await service.currentRelationship()
            guard generation == sessionGeneration else { return }
            try await apply(relationship: refreshedRelationship)
            guard generation == sessionGeneration else { return }
            statusMessage = refreshedRelationship == nil
                ? "解除配對已完成；你的個人封存可以匯出。"
                : "你的個人封存已建立，等待另一方完成。"
        } catch {
            guard generation == sessionGeneration else { return }
            statusMessage = message(for: error)
        }
    }

    func beginUnpairingAndSealPersonalArchive(hasInFlightContent: Bool) async {
        guard case let .paired(relationship) = state else { return }
        guard !hasInFlightContent else {
            statusMessage = "仍有內容正在傳送。請先等待完成或在對話／共同日程中重試後，再解除配對。"
            return
        }
        guard let generation = beginOperation() else { return }
        defer { finishOperation(generation: generation) }

        do {
            switch try await service.unpairingReadiness(relationshipID: relationship.id) {
            case .ready:
                break
            case let .pendingContent(count):
                statusMessage = "尚有 \(count) 筆待送內容。請先在對話或共同日程完成或重試，內容不會被靜默捨棄。"
                return
            }

            try await service.beginUnpairing(relationshipID: relationship.id)
            guard generation == sessionGeneration else { return }
            state = .closing(PairingRelationship(
                id: relationship.id,
                memberCount: relationship.memberCount,
                status: "closing"
            ))
            await removeRelationshipReminders(relationship.id)
            guard generation == sessionGeneration else { return }
            closingPersonalArchive = nil
            statusMessage = "共同空間已停止新增內容，正在建立你的個人封存。"

            let archive = try await service.sealPersonalArchive(
                relationshipID: relationship.id
            )
            guard generation == sessionGeneration else { return }
            closingPersonalArchive = archive
            let refreshedRelationship = try await service.currentRelationship()
            guard generation == sessionGeneration else { return }
            try await apply(relationship: refreshedRelationship)
            guard generation == sessionGeneration else { return }
            statusMessage = refreshedRelationship == nil
                ? "解除配對已完成；你的個人封存可以匯出。"
                : "你的個人封存已安全保存，等待另一方完成。"
        } catch {
            guard generation == sessionGeneration else { return }
            if case .closing = state {
                statusMessage = "解除配對已開始，但個人封存尚未完成。請重新確認狀態後重試。"
            } else {
                statusMessage = "目前無法開始解除配對。請確認網路與待送內容後再試。"
            }
        }
    }

    func preparePersonalArchiveExport() async {
        guard case let .archived(archive) = state,
              let generation = beginOperation()
        else { return }
        defer { finishOperation(generation: generation) }

        cleanupArchiveExportStaging()
        archiveExportDocument = nil
        do {
            let preparation = try await service.preparePersonalArchiveExport(archive: archive)
            guard generation == sessionGeneration else {
                try? FileManager.default.removeItem(at: preparation.stagingURL)
                return
            }
            archiveExportDocument = preparation.document
            archiveExportFileName = preparation.fileName
            archiveExportStagingURL = preparation.stagingURL
            statusMessage = "匯出已準備，可以選擇儲存位置。"
        } catch {
            guard generation == sessionGeneration else { return }
            statusMessage = "個人封存匯出準備失敗：\(error.localizedDescription)"
        }
    }

    func finishPersonalArchiveExport(_ result: Result<URL, Error>) {
        archiveExportDocument = nil
        cleanupArchiveExportStaging()
        switch result {
        case .success:
            statusMessage = "個人封存已交付至所選位置。"
        case let .failure(error):
            statusMessage = "個人封存交付失敗：\(error.localizedDescription)"
        }
    }

    private func beginOperation() -> Int? {
        guard !isWorking else { return nil }
        isWorking = true
        return sessionGeneration
    }

    private func finishOperation(generation: Int) {
        guard generation == sessionGeneration else { return }
        isWorking = false
    }

    private func apply(relationship: PairingRelationship?) async throws {
        let applicationGeneration = sessionGeneration
        let previousRelationshipID = relationshipID(in: state)
        guard let relationship else {
            if let previousRelationshipID {
                await removeRelationshipReminders(previousRelationshipID)
            }
            guard applicationGeneration == sessionGeneration else { return }
            let archive = try await service.ownPersonalArchive()
            if let archive,
               archive.relationshipID != previousRelationshipID {
                await removeRelationshipReminders(archive.relationshipID)
            }
            guard applicationGeneration == sessionGeneration else { return }
            if let archive {
                state = .archived(archive)
                closingPersonalArchive = archive
            } else {
                state = .unpaired
                closingPersonalArchive = nil
            }
            return
        }

        if relationship.status == "closing" {
            state = .closing(relationship)
            await removeRelationshipReminders(relationship.id)
            guard applicationGeneration == sessionGeneration else { return }
            if let archive = try? await service.personalArchive(relationshipID: relationship.id) {
                guard applicationGeneration == sessionGeneration else { return }
                closingPersonalArchive = archive
            }
            return
        }

        if relationship.status == "archived" {
            state = .closing(relationship)
            await removeRelationshipReminders(relationship.id)
            guard applicationGeneration == sessionGeneration else { return }
            let relationshipArchive = try await service.personalArchive(
                relationshipID: relationship.id
            )
            guard applicationGeneration == sessionGeneration else { return }
            let archive: PersonalArchive?
            if let relationshipArchive {
                archive = relationshipArchive
            } else {
                archive = try await service.ownPersonalArchive()
            }
            guard applicationGeneration == sessionGeneration else { return }
            if let archive {
                state = .archived(archive)
                closingPersonalArchive = archive
            } else {
                state = .unpaired
                closingPersonalArchive = nil
            }
            return
        }

        closingPersonalArchive = nil

        if relationship.memberCount >= 2 {
            state = .paired(relationship)
        } else {
            let currentInvitation: PairingInvitation?
            if case let .waiting(currentRelationship, invitation) = state,
               currentRelationship.id == relationship.id {
                currentInvitation = invitation
            } else {
                currentInvitation = nil
            }
            state = .waiting(relationship, invitation: currentInvitation)
        }
    }

    private func relationshipID(in state: PairingState) -> UUID? {
        switch state {
        case let .waiting(relationship, _),
             let .paired(relationship),
             let .closing(relationship):
            relationship.id
        case let .archived(archive):
            archive.relationshipID
        case .checking, .unpaired:
            nil
        }
    }

    private func cleanupArchiveExportStaging() {
        guard let archiveExportStagingURL else { return }
        try? FileManager.default.removeItem(at: archiveExportStagingURL)
        self.archiveExportStagingURL = nil
    }

    private func message(for error: Error) -> String {
        if let error = error as? PostgrestError {
            return PairingErrorMessage.message(serverMessage: error.message)
        }
        return PairingErrorMessage.message(serverMessage: error.localizedDescription)
    }
}
