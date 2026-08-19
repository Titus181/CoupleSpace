import Foundation
import UserNotifications

enum SharedAppointmentReminderAuthorization: Equatable {
    case notDetermined
    case authorized
    case denied
}

@MainActor
protocol SharedAppointmentReminderScheduling {
    func activate() async
    func authorizationStatus() async -> SharedAppointmentReminderAuthorization
    func requestAuthorization() async -> SharedAppointmentReminderAuthorization
    func reconcile(_ appointments: [SharedAppointment]) async throws
    func removeAll() async
}

extension SharedAppointmentReminderScheduling {
    func activate() async {}
}

@MainActor
final class DisabledSharedAppointmentReminderScheduler: SharedAppointmentReminderScheduling {
    func authorizationStatus() async -> SharedAppointmentReminderAuthorization { .authorized }
    func requestAuthorization() async -> SharedAppointmentReminderAuthorization { .authorized }
    func reconcile(_ appointments: [SharedAppointment]) async throws {}
    func removeAll() async {}
}

@MainActor
final class SharedAppointmentReminderLifecycleGate {
    private(set) var generation = 0
    private(set) var isActive = false

    @discardableResult
    func activate() -> Int {
        if !isActive {
            generation &+= 1
            isActive = true
        }
        return generation
    }

    func activate(ifGenerationMatches candidate: Int) -> Bool {
        guard generation == candidate else { return false }
        activate()
        return true
    }

    @discardableResult
    func deactivate() -> Int {
        generation &+= 1
        isActive = false
        return generation
    }

    func begin() -> Int? {
        isActive ? generation : nil
    }

    func accepts(_ candidate: Int) -> Bool {
        isActive && candidate == generation
    }
}

@MainActor
private final class SharedAppointmentReminderLifecycleRegistry {
    static let shared = SharedAppointmentReminderLifecycleRegistry()

    private var gates: [UUID: SharedAppointmentReminderLifecycleGate] = [:]

    func gate(for relationshipID: UUID) -> SharedAppointmentReminderLifecycleGate {
        if let gate = gates[relationshipID] { return gate }
        let gate = SharedAppointmentReminderLifecycleGate()
        gates[relationshipID] = gate
        return gate
    }
}

struct SharedAppointmentReminderRequest: Equatable {
    let identifier: String
    let appointmentID: UUID
    let fireDate: Date
    let title: String
    let body: String
    /// Local appointment reminders must not affect the app icon badge.
    let badge: Int?
    let userInfo: [String: String]
}

enum SharedAppointmentReminderPolicy {
    static let title = "共同約定提醒"
    static let body = "你有一筆即將開始的共同約定。"

    static func requests(
        for appointments: [SharedAppointment],
        identifierPrefix: String,
        now: Date
    ) -> [SharedAppointmentReminderRequest] {
        appointments.compactMap { appointment in
            guard appointment.status == .scheduled,
                  appointment.deliveryState == .synced,
                  let reminderAt = appointment.reminderAt,
                  reminderAt > now
            else { return nil }
            return SharedAppointmentReminderRequest(
                identifier: identifierPrefix + appointment.id.uuidString.lowercased(),
                appointmentID: appointment.id,
                fireDate: reminderAt,
                title: title,
                body: body,
                badge: nil,
                userInfo: [:]
            )
        }
        .sorted { ($0.fireDate, $0.identifier) < ($1.fireDate, $1.identifier) }
    }
}

@MainActor
final class LocalSharedAppointmentReminderScheduler: SharedAppointmentReminderScheduling {
    private let center: UNUserNotificationCenter
    private let relationshipID: UUID
    private let now: () -> Date

    private var identifierPrefix: String {
        "couplespace.shared-appointment-reminder."
            + relationshipID.uuidString.lowercased()
            + "."
    }

    init(
        relationshipID: UUID,
        center: UNUserNotificationCenter = .current(),
        now: @escaping () -> Date = Date.init
    ) {
        self.relationshipID = relationshipID
        self.center = center
        self.now = now
    }

    func activate() async {
        lifecycleGate.activate()
    }

    func lifecycleGeneration() async -> Int {
        lifecycleGate.generation
    }

    func activate(ifLifecycleGenerationMatches generation: Int) async -> Bool {
        lifecycleGate.activate(ifGenerationMatches: generation)
    }

    func authorizationStatus() async -> SharedAppointmentReminderAuthorization {
        Self.authorization(from: await center.notificationSettings().authorizationStatus)
    }

    func requestAuthorization() async -> SharedAppointmentReminderAuthorization {
        let current = await authorizationStatus()
        guard current == .notDetermined else { return current }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            return granted ? .authorized : .denied
        } catch {
            return await authorizationStatus()
        }
    }

    func reconcile(_ appointments: [SharedAppointment]) async throws {
        guard let generation = lifecycleGate.begin() else { return }
        let status = await authorizationStatus()
        guard lifecycleGate.accepts(generation) else { return }
        guard status == .authorized else {
            await removeScheduledNotifications()
            return
        }

        let requests = SharedAppointmentReminderPolicy.requests(
            for: appointments,
            identifierPrefix: identifierPrefix,
            now: now()
        )
        let desiredIdentifiers = Set(requests.map(\.identifier))
        let pending = await center.pendingNotificationRequests()
        guard lifecycleGate.accepts(generation) else { return }
        let staleIdentifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) && !desiredIdentifiers.contains($0) }
        if !staleIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)
        }
        let delivered = await center.deliveredNotifications()
        guard lifecycleGate.accepts(generation) else { return }
        let staleDeliveredIdentifiers = delivered
            .map(\.request.identifier)
            .filter { $0.hasPrefix(identifierPrefix) && !desiredIdentifiers.contains($0) }
        if !staleDeliveredIdentifiers.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: staleDeliveredIdentifiers)
        }

        for request in requests {
            guard lifecycleGate.accepts(generation) else { return }
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default
            content.badge = request.badge.map(NSNumber.init(value:))
            content.userInfo = request.userInfo
            let components = Calendar.autoupdatingCurrent.dateComponents(
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
                from: request.fireDate
            )
            let notificationRequest = UNNotificationRequest(
                identifier: request.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try await center.add(notificationRequest)
            guard lifecycleGate.accepts(generation) else {
                center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                return
            }
        }
    }

    func removeAll() async {
        lifecycleGate.deactivate()
        await removeScheduledNotifications()
    }

    private var lifecycleGate: SharedAppointmentReminderLifecycleGate {
        SharedAppointmentReminderLifecycleRegistry.shared.gate(for: relationshipID)
    }

    private func removeScheduledNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        let delivered = await center.deliveredNotifications()
        let deliveredIdentifiers = delivered.map(\.request.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removeDeliveredNotifications(withIdentifiers: deliveredIdentifiers)
    }

    private static func authorization(
        from status: UNAuthorizationStatus
    ) -> SharedAppointmentReminderAuthorization {
        switch status {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized, .provisional, .ephemeral:
            .authorized
        @unknown default:
            .denied
        }
    }
}
