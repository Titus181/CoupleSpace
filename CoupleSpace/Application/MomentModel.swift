import Combine
import Foundation

@MainActor
final class MomentModel: ObservableObject {
    @Published private(set) var moments: [Moment] = []
    @Published private(set) var photoDataByMomentID: [UUID: Data] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var currentUserID: UUID?

    private let service: MomentRemoteServing
    private var hasStarted = false

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

    func authorLabel(for moment: Moment) -> String {
        guard let currentUserID else { return "留下者未確認" }
        return moment.creatorUserID == currentUserID ? "你留下的" : "對方留下的"
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

    private func loadMissingPhotos() async {
        for moment in moments where photoDataByMomentID[moment.id] == nil {
            guard case .photo = moment.content else { continue }
            await loadPhoto(moment)
        }
    }

    private func loadPhoto(_ moment: Moment) async {
        if let data = try? await service.photoData(for: moment.id) {
            photoDataByMomentID[moment.id] = data
        }
    }
}
