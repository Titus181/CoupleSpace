import Combine
import Foundation

@MainActor
final class MomentModel: ObservableObject {
    @Published private(set) var moments: [Moment] = []
    @Published private(set) var photoDataByMomentID: [UUID: Data] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var activeInteractionMomentIDs: Set<UUID> = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var currentUserID: UUID?

    private let service: MomentRemoteServing
    private var hasStarted = false
    private var pendingResponseAttempts: [UUID: (draft: MomentResponseDraft, clientID: UUID)] = [:]
    private var optimisticResponses: [UUID: MomentResponse] = [:]
    private var pendingAnswerAttempts: [UUID: (answer: String, clientID: UUID)] = [:]
    private var pendingQuestionAttempt: (draft: MomentQuestionDraft, momentID: UUID, answerID: UUID)?

    init(service: MomentRemoteServing) {
        self.service = service
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        do {
            currentUserID = try await service.currentUserID()
        } catch {
            statusMessage = "無法確認 Moment 留下者，請稍後再試。"
        }
        await refresh()
        do {
            try await service.startObservingChanges { [weak self] in
                await self?.refresh()
            }
        } catch {
            statusMessage = "即時同步暫時無法連線；重新開啟畫面時會再讀取。"
        }
    }

    func authorLabel(for moment: Moment, names: TogetherNowSnapshot?) -> String {
        guard let currentUserID else { return "留下者未確認" }
        let label = names?.participantLabel(for: moment.creatorUserID)
            ?? (moment.creatorUserID == currentUserID ? "我" : "伴侶")
        return "\(label)留下的"
    }

    func response(for moment: Moment) -> MomentResponse? {
        moment.responses.first
    }

    func responseLabel(for response: MomentResponse, names: TogetherNowSnapshot?) -> String {
        guard let currentUserID else { return "回應者未確認" }
        let label = names?.participantPossessiveLabel(for: response.responderUserID)
            ?? (response.responderUserID == currentUserID ? "我的" : "伴侶的")
        return "\(label)回應"
    }

    func currentUserHasAnswered(_ moment: Moment) -> Bool {
        guard let currentUserID else { return false }
        return moment.questionAnswers.contains { $0.answererUserID == currentUserID }
    }

    func answerLabel(for answer: MomentQuestionAnswer, names: TogetherNowSnapshot?) -> String {
        guard let currentUserID else { return "留下者未確認" }
        let label = names?.participantPossessiveLabel(for: answer.answererUserID)
            ?? (answer.answererUserID == currentUserID ? "我的" : "伴侶的")
        return "\(label)回答"
    }

    func stop() async {
        hasStarted = false
        await service.stopObservingChanges()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            moments = try await service.fetchMoments()
            mergeOptimisticResponses()
            statusMessage = nil
            await loadMissingPhotos()
        } catch {
            statusMessage = "無法更新 Moment，請稍後再試。"
        }
    }

    @discardableResult
    func create(_ draft: MomentDraft) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let moment = try await service.createMoment(draft, clientID: UUID())
            moments.removeAll { $0.id == moment.id }
            moments.insert(moment, at: 0)
            statusMessage = "已留在你們的共同時間線。"
            if case .photo = moment.content {
                await loadPhoto(moment)
            }
            return true
        } catch {
            statusMessage = "Moment 尚未送出，請確認連線後再試。"
            return false
        }
    }

    @discardableResult
    func createQuestion(_ draft: MomentQuestionDraft) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }

        let attempt: (draft: MomentQuestionDraft, momentID: UUID, answerID: UUID)
        if let pendingQuestionAttempt, pendingQuestionAttempt.draft == draft {
            attempt = pendingQuestionAttempt
        } else {
            attempt = (draft, UUID(), UUID())
            pendingQuestionAttempt = attempt
        }

        do {
            let moment = try await service.createQuestion(
                draft,
                momentClientID: attempt.momentID,
                answerClientID: attempt.answerID
            )
            moments.removeAll { $0.id == moment.id }
            moments.insert(moment, at: 0)
            pendingQuestionAttempt = nil
            statusMessage = "題目已留在你們的共同時間線。"
            return true
        } catch {
            statusMessage = "題目尚未送出，請確認連線後再試。"
            return false
        }
    }

    @discardableResult
    func respond(to moment: Moment, with draft: MomentResponseDraft) async -> Bool {
        guard !activeInteractionMomentIDs.contains(moment.id),
              let currentUserID,
              let content = responseContent(for: draft)
        else { return false }
        activeInteractionMomentIDs.insert(moment.id)
        defer { activeInteractionMomentIDs.remove(moment.id) }

        let attempt: (draft: MomentResponseDraft, clientID: UUID)
        if let pending = pendingResponseAttempts[moment.id], pending.draft == draft {
            attempt = pending
        } else {
            attempt = (draft, UUID())
            pendingResponseAttempts[moment.id] = attempt
        }
        let optimisticResponse = MomentResponse(
            id: attempt.clientID,
            responderUserID: currentUserID,
            content: content,
            createdAt: .now
        )
        optimisticResponses[moment.id] = optimisticResponse
        replaceResponse(in: moment.id, with: optimisticResponse)
        do {
            let response = try await service.createResponse(
                to: moment.id,
                draft: draft,
                clientID: attempt.clientID
            )
            pendingResponseAttempts[moment.id] = nil
            optimisticResponses[moment.id] = nil
            replaceResponse(in: moment.id, with: response)
            statusMessage = "已回應這個 Moment。"
            return true
        } catch {
            optimisticResponses[moment.id] = nil
            removeResponse(id: attempt.clientID, from: moment.id)
            statusMessage = "回應尚未送出，請確認連線後再試。"
            return false
        }
    }

    @discardableResult
    func answer(_ moment: Moment, text: String) async -> Bool {
        guard !activeInteractionMomentIDs.contains(moment.id) else { return false }
        activeInteractionMomentIDs.insert(moment.id)
        defer { activeInteractionMomentIDs.remove(moment.id) }

        guard let normalizedAnswer = MomentQuestionPolicy.normalizedAnswer(text) else {
            statusMessage = "回答內容不完整。"
            return false
        }
        let attempt: (answer: String, clientID: UUID)
        if let pending = pendingAnswerAttempts[moment.id], pending.answer == normalizedAnswer {
            attempt = pending
        } else {
            attempt = (normalizedAnswer, UUID())
            pendingAnswerAttempts[moment.id] = attempt
        }
        do {
            _ = try await service.answerQuestion(
                momentID: moment.id,
                answer: normalizedAnswer,
                clientID: attempt.clientID
            )
            pendingAnswerAttempts[moment.id] = nil
            await refresh()
            statusMessage = "回答已送出；雙方完成後會一起揭曉。"
            return true
        } catch {
            statusMessage = "回答尚未送出，請確認連線後再試。"
            return false
        }
    }

    private func loadMissingPhotos() async {
        for moment in moments where photoDataByMomentID[moment.id] == nil {
            guard case .photo = moment.content else { continue }
            await loadPhoto(moment)
        }
    }

    private func responseContent(for draft: MomentResponseDraft) -> MomentResponseContent? {
        switch draft {
        case let .emoji(emoji):
            return .emoji(emoji)
        case let .text(value):
            guard let value = MomentResponsePolicy.normalizedText(value) else { return nil }
            return .text(value)
        }
    }

    private func replaceResponse(in momentID: UUID, with response: MomentResponse) {
        guard let index = moments.firstIndex(where: { $0.id == momentID }) else { return }
        moments[index].responses.removeAll { $0.id == response.id }
        moments[index].responses.append(response)
    }

    private func removeResponse(id: UUID, from momentID: UUID) {
        guard let index = moments.firstIndex(where: { $0.id == momentID }) else { return }
        moments[index].responses.removeAll { $0.id == id }
    }

    private func mergeOptimisticResponses() {
        for (momentID, response) in optimisticResponses {
            guard let index = moments.firstIndex(where: { $0.id == momentID }),
                  !moments[index].responses.contains(where: { $0.id == response.id })
            else { continue }
            moments[index].responses.append(response)
        }
    }

    private func loadPhoto(_ moment: Moment) async {
        if let data = try? await service.photoData(for: moment.id) {
            photoDataByMomentID[moment.id] = data
        }
    }
}
