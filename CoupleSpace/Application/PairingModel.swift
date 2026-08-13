import Combine
import Foundation
import Supabase

@MainActor
final class PairingModel: ObservableObject {
    @Published private(set) var state: PairingState
    @Published private(set) var isWorking = false
    @Published private(set) var statusMessage: String?

    private let service: PairingRemoteServing
    private var sessionGeneration = 0

    init(service: PairingRemoteServing, initialState: PairingState = .checking) {
        self.service = service
        self.state = initialState
    }

    convenience init(client: SupabaseClient, initialState: PairingState = .checking) {
        self.init(service: SupabasePairingService(client: client), initialState: initialState)
    }

    func resetForAuthenticatedSession() {
        sessionGeneration += 1
        isWorking = false
        state = .checking
        statusMessage = nil
    }

    func restoreCachedRelationship(userID: UUID) async {
        guard state == .checking,
              let relationship = await service.cachedRelationship(userID: userID)
        else { return }
        apply(relationship: relationship)
    }

    func refreshForAuthenticatedSession(userID: UUID) async {
        guard let generation = beginOperation() else { return }
        defer { finishOperation(generation: generation) }

        do {
            let relationship = try await service.currentRelationship()
            guard generation == sessionGeneration else { return }
            apply(relationship: relationship)
            statusMessage = nil
        } catch {
            guard generation == sessionGeneration else { return }
            if let cachedRelationship = await service.cachedRelationship(userID: userID) {
                guard generation == sessionGeneration else { return }
                apply(relationship: cachedRelationship)
            } else if state == .checking {
                state = .unpaired
            }
            statusMessage = message(for: error)
        }
    }

    func refresh() async {
        guard let generation = beginOperation() else { return }
        defer { finishOperation(generation: generation) }

        do {
            let relationship = try await service.currentRelationship()
            guard generation == sessionGeneration else { return }
            apply(relationship: relationship)
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
        guard let token = PairingInputPolicy.invitationToken(from: rawToken) else {
            statusMessage = "邀請碼格式不正確，請完整貼上後再試。"
            return
        }
        guard let generation = beginOperation() else { return }
        defer { finishOperation(generation: generation) }

        do {
            let relationshipID = try await service.acceptInvitation(token: token)
            guard generation == sessionGeneration else { return }
            state = .paired(PairingRelationship(id: relationshipID, memberCount: 2))
            statusMessage = "配對完成。"
        } catch {
            guard generation == sessionGeneration else { return }
            statusMessage = message(for: error)
        }
    }

    func declineInvitation(rawToken: String) async {
        guard let token = PairingInputPolicy.invitationToken(from: rawToken) else {
            statusMessage = "邀請碼格式不正確，請完整貼上後再試。"
            return
        }
        guard let generation = beginOperation() else { return }
        defer { finishOperation(generation: generation) }

        do {
            try await service.declineInvitation(token: token)
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

    private func beginOperation() -> Int? {
        guard !isWorking else { return nil }
        isWorking = true
        return sessionGeneration
    }

    private func finishOperation(generation: Int) {
        guard generation == sessionGeneration else { return }
        isWorking = false
    }

    private func apply(relationship: PairingRelationship?) {
        guard let relationship else {
            state = .unpaired
            return
        }

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

    private func message(for error: Error) -> String {
        if let error = error as? PostgrestError {
            return PairingErrorMessage.message(serverMessage: error.message)
        }
        return PairingErrorMessage.message(serverMessage: error.localizedDescription)
    }
}
