import Supabase
import SwiftUI
import UIKit

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = PrimarySection.defaultSelection
    @State private var conversationFocusMessageID: UUID?
    @State private var appointmentDiscussionFocus: AppointmentDiscussionFocus?
    @State private var sourceNavigationRequestID: UUID?
    @State private var relationshipUnreadCount: Int?
#if DEBUG
    @State private var isShowingSessionCapabilityProbe = false
#endif

    private var displayedUnreadCount: Int {
        relationshipUnreadCount
            ?? conversationModel.unreadCount + sharedAppointmentModel.discussionUnreadCount
    }
    @StateObject private var networkRecoveryMonitor = NetworkRecoveryMonitor()
    @StateObject private var momentModel: MomentModel
    @StateObject private var togetherNowModel: TogetherNowModel
    @StateObject private var sharedAppointmentModel: SharedAppointmentModel
    @StateObject private var conversationModel: ConversationModel

    private var isOffline: Bool {
        networkRecoveryMonitor.state == .unavailable
            || ProcessInfo.processInfo.arguments.contains("--ui-testing-offline")
    }

    let accountUserToken: String?
    let accountStatusMessage: String?
    let relationshipToken: String?
    private let relationshipID: UUID?
    let technicalValidationClient: SupabaseClient?
    let pairingModel: PairingModel?
    let onSignOut: () -> Void
    let onRelationshipLifecycleChanged: @MainActor () async -> Void
    private let shouldActivateRemotePush: Bool

    init(
        accountUserID: UUID? = nil,
        accountUserToken: String? = nil,
        accountStatusMessage: String? = nil,
        relationshipID: UUID? = nil,
        relationshipToken: String? = nil,
        technicalValidationClient: SupabaseClient? = nil,
        pairingModel: PairingModel? = nil,
        onSignOut: @escaping () -> Void = {},
        onRelationshipLifecycleChanged: @escaping @MainActor () async -> Void = {}
    ) {
        self.accountUserToken = accountUserToken
        self.accountStatusMessage = accountStatusMessage
        self.relationshipToken = relationshipToken
        self.relationshipID = relationshipID
        self.technicalValidationClient = technicalValidationClient
        self.pairingModel = pairingModel
        self.onSignOut = onSignOut
        self.onRelationshipLifecycleChanged = onRelationshipLifecycleChanged
        shouldActivateRemotePush = accountUserID != nil
            && relationshipID != nil
            && technicalValidationClient != nil
        if let accountUserID, let relationshipID, let technicalValidationClient {
            _momentModel = StateObject(
                wrappedValue: MomentModel(
                    service: SupabaseMomentService(
                        client: technicalValidationClient,
                        currentUserID: accountUserID,
                        relationshipID: relationshipID
                    )
                )
            )
            _togetherNowModel = StateObject(
                wrappedValue: TogetherNowModel(
                    service: SupabaseTogetherNowService(
                        client: technicalValidationClient,
                        currentUserID: accountUserID,
                        relationshipID: relationshipID
                    )
                )
            )
            _sharedAppointmentModel = StateObject(
                wrappedValue: SharedAppointmentModel(
                    service: SupabaseSharedAppointmentService(
                        client: technicalValidationClient,
                        currentUserID: accountUserID,
                        relationshipID: relationshipID
                    ),
                    reminderScheduler: LocalSharedAppointmentReminderScheduler(
                        relationshipID: relationshipID
                    ),
                    discussionModelFactory: { appointmentID in
                        ConversationModel(
                            service: SupabaseConversationService(
                                client: technicalValidationClient,
                                currentUserID: accountUserID,
                                relationshipID: relationshipID,
                                scope: .appointment(appointmentID)
                            )
                        )
                    }
                )
            )
            _conversationModel = StateObject(
                wrappedValue: ConversationModel(
                    service: SupabaseConversationService(
                        client: technicalValidationClient,
                        currentUserID: accountUserID,
                        relationshipID: relationshipID
                    )
                )
            )
        } else {
            let service: InMemoryMomentService
            let arguments = ProcessInfo.processInfo.arguments
            let uiTestUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
            let uiTestPartnerID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D2")!
            if arguments.contains("--ui-testing-w10-chat") {
                let sourceMessageID = UUID(uuidString: "D4000000-0000-0000-0000-000000000010")!
                service = InMemoryMomentService(
                    userID: uiTestUserID,
                    moments: [Moment(
                        id: UUID(uuidString: "D1000000-0000-0000-0000-000000000010")!,
                        creatorUserID: uiTestUserID,
                        content: .text("值得留下的晚餐約定"),
                        createdAt: .now,
                        sourceMessageID: sourceMessageID
                    )]
                )
            } else if arguments.contains("--ui-testing-w11-discussion") {
                service = InMemoryMomentService(
                    userID: uiTestUserID,
                    moments: [Moment(
                        id: UUID(uuidString: "D1000000-0000-0000-0000-000000000011")!,
                        creatorUserID: uiTestUserID,
                        content: .text("從約定留下的 Moment"),
                        createdAt: .now,
                        sourceMessageID: UUID(
                            uuidString: "D4000000-0000-0000-0000-000000000020"
                        )!,
                        sourceAppointmentID: UUID(
                            uuidString: "A4000000-0000-0000-0000-000000000004"
                        )!
                    )]
                )
            } else if arguments.contains("--ui-testing-w11-source-routing") {
                let appointmentID = UUID(
                    uuidString: "A4000000-0000-0000-0000-000000000004"
                )!
                service = InMemoryMomentService(
                    userID: uiTestUserID,
                    moments: [
                        Moment(
                            id: UUID(uuidString: "D1000000-0000-0000-0000-000000000012")!,
                            creatorUserID: uiTestUserID,
                            content: .text("第一個約定來源"),
                            createdAt: .now,
                            sourceMessageID: UUID(
                                uuidString: "D4000000-0000-0000-0000-000000000020"
                            )!,
                            sourceAppointmentID: appointmentID
                        ),
                        Moment(
                            id: UUID(uuidString: "D1000000-0000-0000-0000-000000000013")!,
                            creatorUserID: uiTestUserID,
                            content: .text("一般聊天來源"),
                            createdAt: .now.addingTimeInterval(-1),
                            sourceMessageID: UUID(
                                uuidString: "D4000000-0000-0000-0000-000000000030"
                            )!
                        ),
                        Moment(
                            id: UUID(uuidString: "D1000000-0000-0000-0000-000000000014")!,
                            creatorUserID: uiTestUserID,
                            content: .text("第二個約定來源"),
                            createdAt: .now.addingTimeInterval(-2),
                            sourceMessageID: UUID(
                                uuidString: "D4000000-0000-0000-0000-000000000022"
                            )!,
                            sourceAppointmentID: appointmentID
                        ),
                    ]
                )
            } else if arguments.contains("--ui-testing-w12-pagination") {
                service = InMemoryMomentService(
                    userID: uiTestUserID,
                    moments: (0..<55).map { index in
                        Moment(
                            id: UUID(),
                            creatorUserID: uiTestUserID,
                            content: .text("分頁 Moment \(index)"),
                            createdAt: Date(timeIntervalSince1970: TimeInterval(10_000 - index))
                        )
                    }
                )
            } else if arguments.contains("--ui-testing-w12-weekly-review") {
                service = InMemoryMomentService(
                    userID: uiTestUserID,
                    moments: [
                        Moment(
                            id: UUID(uuidString: "C3000000-0000-0000-0000-000000000001")!,
                            creatorUserID: uiTestUserID,
                            content: .text("這週一起散步"),
                            createdAt: .now.addingTimeInterval(-3_600)
                        ),
                        Moment(
                            id: UUID(uuidString: "C3000000-0000-0000-0000-000000000002")!,
                            creatorUserID: uiTestPartnerID,
                            content: .mood(.happy),
                            createdAt: .now.addingTimeInterval(-86_400)
                        ),
                        Moment(
                            id: UUID(uuidString: "C3000000-0000-0000-0000-000000000003")!,
                            creatorUserID: uiTestPartnerID,
                            content: .text("八天前的 Moment"),
                            createdAt: .now.addingTimeInterval(-691_200)
                        ),
                    ]
                )
            } else if arguments.contains("--ui-testing-w12-monthly-timeline") {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                let fixture: [(String, Int, Int, String)] = [
                    ("C1000000-0000-0000-0000-000000000001", 8, 17, "八月一起散步"),
                    ("C1000000-0000-0000-0000-000000000002", 8, 3, "八月的晚餐"),
                    ("C1000000-0000-0000-0000-000000000003", 7, 21, "七月的小旅行"),
                    ("C1000000-0000-0000-0000-000000000004", 7, 2, "七月一起看電影"),
                    ("C1000000-0000-0000-0000-000000000005", 6, 18, "六月雨天"),
                    ("C1000000-0000-0000-0000-000000000006", 6, 1, "六月第一天"),
                ]
                let photoFixture: [(String, Int, Int, UUID?)] = [
                    ("C2000000-0000-0000-0000-000000000001", 6, 5, nil),
                    ("C2000000-0000-0000-0000-000000000002", 7, 8, nil),
                    (
                        "C2000000-0000-0000-0000-000000000003",
                        8,
                        16,
                        UUID(uuidString: "D4000000-0000-0000-0000-000000000040")!
                    ),
                ]
                let textMoments = fixture.map { id, month, day, text in
                    Moment(
                        id: UUID(uuidString: id)!,
                        creatorUserID: uiTestUserID,
                        content: .text(text),
                        createdAt: calendar.date(from: DateComponents(
                            year: 2026,
                            month: month,
                            day: day,
                            hour: 12
                        ))!
                    )
                }
                let photoMoments = photoFixture.map { id, month, day, sourceMessageID in
                    Moment(
                        id: UUID(uuidString: id)!,
                        creatorUserID: uiTestUserID,
                        content: .photo,
                        createdAt: calendar.date(from: DateComponents(
                            year: 2026,
                            month: month,
                            day: day,
                            hour: 12
                        ))!,
                        sourceMessageID: sourceMessageID
                    )
                }
                let photoData = [
                    Self.uiTestPhotoData(size: CGSize(width: 640, height: 320)),
                    Self.uiTestPhotoData(size: CGSize(width: 500, height: 500)),
                    Self.uiTestPhotoData(size: CGSize(width: 320, height: 640)),
                ]
                service = InMemoryMomentService(
                    userID: uiTestUserID,
                    moments: textMoments + photoMoments,
                    photoDataByMomentID: Dictionary(
                        uniqueKeysWithValues: zip(photoMoments, photoData).map { moment, data in
                            (moment.id, data)
                        }
                    )
                )
            } else if arguments.contains("--ui-testing-photo-moment"),
               let photoData = Data(base64Encoded:
                   "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
               ) {
                let momentID = UUID(uuidString: "B1000000-0000-0000-0000-000000000099")!
                service = InMemoryMomentService(
                    moments: [Moment(
                        id: momentID,
                        creatorUserID: UUID(),
                        content: .photo,
                        createdAt: .now
                    )],
                    photoDataByMomentID: [momentID: photoData]
                )
            } else if arguments.contains("--ui-testing-partner-moment") {
                service = InMemoryMomentService(
                    userID: uiTestUserID,
                    moments: [Moment(
                        id: UUID(uuidString: "D1000000-0000-0000-0000-000000000001")!,
                        creatorUserID: uiTestPartnerID,
                        content: .text("今天也辛苦了"),
                        createdAt: .now
                    )]
                )
            } else if arguments.contains("--ui-testing-partner-question") {
                service = InMemoryMomentService(
                    userID: uiTestUserID,
                    moments: [Moment(
                        id: UUID(uuidString: "D1000000-0000-0000-0000-000000000002")!,
                        creatorUserID: uiTestPartnerID,
                        content: .question(MomentQuestion(
                            key: "recent_small_happiness",
                            prompt: "最近有哪件小事讓你感到幸福？"
                        )),
                        createdAt: .now,
                        questionAnswers: [MomentQuestionAnswer(
                            id: UUID(uuidString: "D3000000-0000-0000-0000-000000000001")!,
                            answererUserID: uiTestPartnerID,
                            content: "下班一起吃飯",
                            createdAt: .now
                        )]
                    )]
                )
            } else {
                service = InMemoryMomentService()
            }
            _momentModel = StateObject(
                wrappedValue: MomentModel(service: service)
            )
            _togetherNowModel = StateObject(
                wrappedValue: TogetherNowModel(service: InMemoryTogetherNowService())
            )
            let pastDiscussionAppointmentID = UUID(
                uuidString: "A4000000-0000-0000-0000-000000000006"
            )!
            let cancelledDiscussionAppointmentID = UUID(
                uuidString: "A4000000-0000-0000-0000-000000000007"
            )!
            let seededAppointments: [SharedAppointment]
            if arguments.contains("--ui-testing-w11-appointments") {
                seededAppointments = [
                    SharedAppointment(
                        id: UUID(uuidString: "A4000000-0000-0000-0000-000000000001")!,
                        creatorUserID: uiTestUserID,
                        title: "週末一起吃晚餐",
                        startsAt: .now.addingTimeInterval(86_400),
                        location: "中山站",
                        note: "記得先訂位",
                        reminderAt: .now.addingTimeInterval(82_800),
                        status: .scheduled,
                        sourceMessageID: nil,
                        createdAt: .now,
                        updatedAt: .now
                    ),
                    SharedAppointment(
                        id: UUID(uuidString: "A4000000-0000-0000-0000-000000000002")!,
                        creatorUserID: uiTestPartnerID,
                        title: "上週一起散步",
                        startsAt: .now.addingTimeInterval(-86_400),
                        location: nil,
                        note: nil,
                        reminderAt: nil,
                        status: .scheduled,
                        sourceMessageID: nil,
                        createdAt: .now.addingTimeInterval(-172_800),
                        updatedAt: .now.addingTimeInterval(-86_400)
                    ),
                ]
            } else if arguments.contains("--ui-testing-w12-past-appointments") {
                seededAppointments = [
                    SharedAppointment(
                        id: UUID(uuidString: "A4000000-0000-0000-0000-000000000005")!,
                        creatorUserID: uiTestUserID,
                        title: "下週一起吃晚餐",
                        startsAt: .now.addingTimeInterval(86_400),
                        location: nil,
                        note: nil,
                        reminderAt: nil,
                        status: .scheduled,
                        sourceMessageID: nil,
                        createdAt: .now,
                        updatedAt: .now
                    ),
                    SharedAppointment(
                        id: pastDiscussionAppointmentID,
                        creatorUserID: uiTestPartnerID,
                        title: "昨天一起散步",
                        startsAt: .now.addingTimeInterval(-86_400),
                        location: "河濱公園",
                        note: nil,
                        reminderAt: nil,
                        status: .scheduled,
                        sourceMessageID: nil,
                        createdAt: .now.addingTimeInterval(-172_800),
                        updatedAt: .now.addingTimeInterval(-86_400)
                    ),
                    SharedAppointment(
                        id: cancelledDiscussionAppointmentID,
                        creatorUserID: uiTestUserID,
                        title: "取消的電影約會",
                        startsAt: .now.addingTimeInterval(-172_800),
                        location: "電影院",
                        note: nil,
                        reminderAt: nil,
                        status: .cancelled,
                        sourceMessageID: nil,
                        createdAt: .now.addingTimeInterval(-259_200),
                        updatedAt: .now.addingTimeInterval(-172_800)
                    ),
                ]
            } else if arguments.contains("--ui-testing-w11-calendar") {
                let startsAt = Calendar.autoupdatingCurrent.date(
                    bySettingHour: 18,
                    minute: 0,
                    second: 0,
                    of: .now
                ) ?? .now
                seededAppointments = [SharedAppointment(
                    id: UUID(uuidString: "A4000000-0000-0000-0000-000000000003")!,
                    creatorUserID: uiTestPartnerID,
                    title: "今天一起喝咖啡",
                    startsAt: startsAt,
                    location: "常去的咖啡店",
                    note: nil,
                    reminderAt: nil,
                    status: .scheduled,
                    sourceMessageID: nil,
                    createdAt: .now,
                    updatedAt: .now
                )]
            } else if arguments.contains("--ui-testing-w11-discussion")
                        || arguments.contains("--ui-testing-w11-source-routing") {
                seededAppointments = [SharedAppointment(
                    id: UUID(uuidString: "A4000000-0000-0000-0000-000000000004")!,
                    creatorUserID: uiTestUserID,
                    title: "週末去看展",
                    startsAt: .now.addingTimeInterval(86_400),
                    location: "美術館",
                    note: nil,
                    reminderAt: nil,
                    status: .scheduled,
                    sourceMessageID: nil,
                    createdAt: .now,
                    updatedAt: .now
                )]
            } else {
                seededAppointments = []
            }
            let discussionAppointmentID = UUID(
                uuidString: "A4000000-0000-0000-0000-000000000004"
            )!
            let seededDiscussionSummaries: [SharedAppointmentDiscussionSummary]
                if arguments.contains("--ui-testing-w11-discussion")
                    || arguments.contains("--ui-testing-w11-source-routing") {
                seededDiscussionSummaries = [SharedAppointmentDiscussionSummary(
                    appointmentID: discussionAppointmentID,
                    latestActivityAt: .now,
                    unreadCount: 2
                )]
            } else {
                seededDiscussionSummaries = []
            }
            let seededAppointmentEvents: [SharedAppointmentEvent]
            if arguments.contains("--ui-testing-w11-discussion") {
                seededAppointmentEvents = [SharedAppointmentEvent(
                    id: UUID(uuidString: "A5000000-0000-0000-0000-000000000001")!,
                    appointmentID: discussionAppointmentID,
                    actorUserID: uiTestPartnerID,
                    kind: .rescheduled,
                    previousStartsAt: .now.addingTimeInterval(82_800),
                    startsAt: .now.addingTimeInterval(86_400),
                    createdAt: .now.addingTimeInterval(-60)
                )]
            } else {
                seededAppointmentEvents = []
            }
            _sharedAppointmentModel = StateObject(
                wrappedValue: SharedAppointmentModel(
                    service: InMemorySharedAppointmentService(
                        appointments: seededAppointments,
                        events: seededAppointmentEvents,
                        discussionSummaries: seededDiscussionSummaries
                    ),
                    discussionModelFactory: { appointmentID in
                        let messages: [ChatMessage]
                        let photoDataByMessageID: [UUID: Data]
                        if arguments.contains("--ui-testing-w12-past-appointments"),
                           appointmentID == pastDiscussionAppointmentID {
                            messages = [ChatMessage(
                                id: UUID(uuidString: "D4000000-0000-0000-0000-000000000023")!,
                                senderUserID: uiTestPartnerID,
                                body: "散步後還想聊聊",
                                createdAt: .now.addingTimeInterval(-86_300)
                            )]
                            photoDataByMessageID = [:]
                        } else if arguments.contains("--ui-testing-w12-past-appointments"),
                                  appointmentID == cancelledDiscussionAppointmentID {
                            messages = [ChatMessage(
                                id: UUID(uuidString: "D4000000-0000-0000-0000-000000000024")!,
                                senderUserID: uiTestPartnerID,
                                body: "電影票已經退好了",
                                createdAt: .now.addingTimeInterval(-172_700)
                            )]
                            photoDataByMessageID = [:]
                        } else if (arguments.contains("--ui-testing-w11-discussion")
                            || arguments.contains("--ui-testing-w11-source-routing")),
                           appointmentID == discussionAppointmentID {
                            let photoMessageID = UUID(
                                uuidString: "D4000000-0000-0000-0000-000000000021"
                            )!
                            let pixel = Data(base64Encoded:
                                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
                            )!
                            messages = [
                                ChatMessage(
                                    id: photoMessageID,
                                    senderUserID: uiTestPartnerID,
                                    content: .photo,
                                    createdAt: .now.addingTimeInterval(-1)
                                ),
                                ChatMessage(
                                    id: UUID(uuidString: "D4000000-0000-0000-0000-000000000020")!,
                                    senderUserID: uiTestPartnerID,
                                    body: "要不要先約下午兩點？",
                                    createdAt: .now
                                ),
                                ChatMessage(
                                    id: UUID(uuidString: "D4000000-0000-0000-0000-000000000022")!,
                                    senderUserID: uiTestPartnerID,
                                    body: "第二個約定來源訊息",
                                    createdAt: .now.addingTimeInterval(1)
                                ),
                            ]
                            photoDataByMessageID = [photoMessageID: pixel]
                        } else {
                            messages = []
                            photoDataByMessageID = [:]
                        }
                        return ConversationModel(
                            service: InMemoryConversationService(
                                currentUserID: uiTestUserID,
                                messages: messages,
                                unreadCount: messages.count,
                                photoDataByMessageID: photoDataByMessageID
                            )
                        )
                    }
                )
            )
            let seededMessages: [ChatMessage]
            let seededPhotoDataByMessageID: [UUID: Data]
            if arguments.contains("--ui-testing-w12-chat-pagination") {
                seededMessages = (0..<55).map { index in
                    ChatMessage(
                        id: UUID(),
                        senderUserID: uiTestPartnerID,
                        body: "分頁訊息 \(index)",
                        createdAt: Date(timeIntervalSince1970: TimeInterval(10_000 - index))
                    )
                }
                seededPhotoDataByMessageID = [:]
            } else if arguments.contains("--ui-testing-w11-source-routing") {
                seededMessages = [ChatMessage(
                    id: UUID(uuidString: "D4000000-0000-0000-0000-000000000030")!,
                    senderUserID: uiTestPartnerID,
                    body: "一般聊天來源訊息",
                    createdAt: .now
                )]
                seededPhotoDataByMessageID = [:]
            } else if arguments.contains("--ui-testing-w10-chat") {
                let sourceMessageID = UUID(uuidString: "D4000000-0000-0000-0000-000000000010")!
                let photoMessageID = UUID(uuidString: "D4000000-0000-0000-0000-000000000011")!
                seededMessages = [
                    ChatMessage(
                        id: sourceMessageID,
                        senderUserID: uiTestPartnerID,
                        body: "晚餐後一起散步",
                        createdAt: .now.addingTimeInterval(-1)
                    ),
                    ChatMessage(
                        id: photoMessageID,
                        senderUserID: uiTestPartnerID,
                        content: .photo,
                        createdAt: .now
                    ),
                ]
                let pixel = Data(base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
                )!
                seededPhotoDataByMessageID = [photoMessageID: pixel]
            } else if arguments.contains("--ui-testing-failed-message") {
                seededMessages = ["第一則待重試", "第二則待重試", "第三則待重試"]
                    .enumerated()
                    .map { index, body in
                        ChatMessage(
                            id: UUID(uuidString: "D4000000-0000-0000-0000-00000000000\(index + 2)")!,
                            senderUserID: uiTestUserID,
                            body: body,
                            createdAt: .now.addingTimeInterval(TimeInterval(index)),
                            deliveryState: .failed
                        )
                    }
                seededPhotoDataByMessageID = [:]
            } else if arguments.contains("--ui-testing-partner-message") {
                seededMessages = [ChatMessage(
                    id: UUID(uuidString: "D4000000-0000-0000-0000-000000000001")!,
                    senderUserID: uiTestPartnerID,
                    body: "晚點一起吃飯嗎？",
                    createdAt: .now
                )]
                seededPhotoDataByMessageID = [:]
            } else {
                seededMessages = []
                seededPhotoDataByMessageID = [:]
            }
            _conversationModel = StateObject(
                wrappedValue: ConversationModel(
                    service: InMemoryConversationService(
                        currentUserID: uiTestUserID,
                        messages: seededMessages,
                        unreadCount: seededMessages.count,
                        sendFailuresRemaining: arguments.contains("--ui-testing-offline") ? .max : 0,
                        photoDataByMessageID: seededPhotoDataByMessageID,
                        returnsCachedSnapshot: !arguments.contains("--ui-testing-w12-chat-pagination")
                    )
                )
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isOffline {
                Label("目前為離線模式，待送內容會在恢復網路後重試。", systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.thinMaterial)
                    .accessibilityIdentifier("offline-status")
            }

            TabView(selection: $selection) {
                Tab("今天", systemImage: "sun.max", value: PrimarySection.today) {
                    TodayMomentView(
                        model: momentModel,
                        togetherNowModel: togetherNowModel,
                        sharedAppointmentModel: sharedAppointmentModel,
                        onOpenSourceMessage: openSourceMessage
                    )
                }

                Tab("對話", systemImage: "bubble.left.and.bubble.right", value: PrimarySection.conversation) {
                    ConversationView(
                        model: conversationModel,
                        sharedAppointmentModel: sharedAppointmentModel,
                        focusMessageID: $conversationFocusMessageID,
                        appointmentDiscussionFocus: $appointmentDiscussionFocus,
                        savedMomentSourceIDs: Set(momentModel.moments.compactMap(\.sourceMessageID)),
                        onMomentSaved: { await momentModel.refresh() }
                    )
                }
                .badge(displayedUnreadCount)

                Tab("我們", systemImage: "person.2", value: PrimarySection.us) {
                    UsView(
                        momentModel: momentModel,
                        togetherNowModel: togetherNowModel,
                        sharedAppointmentModel: sharedAppointmentModel,
                        conversationModel: conversationModel,
                        accountUserToken: accountUserToken,
                        accountStatusMessage: accountStatusMessage,
                        relationshipToken: relationshipToken,
                        technicalValidationClient: technicalValidationClient,
                        pairingModel: pairingModel,
                        onOpenSourceMessage: openSourceMessage,
                        onSignOut: onSignOut,
                        onRelationshipLifecycleChanged: onRelationshipLifecycleChanged
                    )
                }
            }
#if DEBUG
            .overlay(alignment: .topTrailing) {
                if SessionCapabilityProbeAvailability.isEnabled(
                    arguments: ProcessInfo.processInfo.arguments
                ), let technicalValidationClient {
                    Button {
                        isShowingSessionCapabilityProbe = true
                    } label: {
                        Label("W13 session 測試", systemImage: "checkmark.shield")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("session-capability-probe-entry")
                    .padding()
                }
            }
            .sheet(isPresented: $isShowingSessionCapabilityProbe) {
                if let technicalValidationClient {
                    NavigationStack {
                        SessionCapabilityProbeScreen(client: technicalValidationClient)
                            .navigationTitle("W13 session 測試")
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("完成") {
                                        isShowingSessionCapabilityProbe = false
                                    }
                                }
                            }
                    }
                }
            }
#endif
        }
        .tint(.accentColor)
        .task {
            networkRecoveryMonitor.start()
            if shouldActivateRemotePush,
               !ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                await PushNotificationPlatformAdapter.shared.requestAuthorizationAndRegister()
            }
            async let momentStart: Void = momentModel.start()
            async let togetherNowStart: Void = togetherNowModel.start()
            async let sharedAppointmentStart: Void = sharedAppointmentModel.start()
            async let conversationStart: Void = conversationModel.start()
            _ = await (
                momentStart,
                togetherNowStart,
                sharedAppointmentStart,
                conversationStart
            )
            await refreshRelationshipUnreadBadge()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .coupleSpaceDidRequestSecureRefresh
            )
        ) { _ in
            Task { await refreshAfterSecureNotificationInteraction() }
        }
        .onChange(of: selection) { _, selection in
            Task {
                await conversationModel.setConversationVisible(selection == .conversation)
            }
        }
        .onChange(of: conversationModel.unreadCount) { _, _ in
            Task { await refreshRelationshipUnreadBadge() }
        }
        .onChange(of: conversationModel.unreadRefreshGeneration) { _, _ in
            Task { await refreshRelationshipUnreadBadge() }
        }
        .onChange(of: sharedAppointmentModel.discussionUnreadCount) { _, _ in
            Task { await refreshRelationshipUnreadBadge() }
        }
        .onChange(of: sharedAppointmentModel.refreshGeneration) { _, _ in
            Task { await refreshRelationshipUnreadBadge() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                Task { await conversationModel.setConversationVisible(false) }
                return
            }
            Task {
                await conversationModel.setConversationVisible(selection == .conversation)
                async let momentRefresh: Void = momentModel.refresh()
                async let togetherNowRefresh: Void = togetherNowModel.refresh()
                async let sharedAppointmentRefresh: Void = sharedAppointmentModel
                    .recoverPendingAppointments()
                async let conversationRecovery: Void = conversationModel.recoverPendingMessages()
                _ = await (
                    momentRefresh,
                    togetherNowRefresh,
                    sharedAppointmentRefresh,
                    conversationRecovery
                )
            }
        }
        .onChange(of: networkRecoveryMonitor.state) { previous, current in
            guard scenePhase == .active,
                  NetworkRecoveryTriggerPolicy.shouldRecover(
                      previous: previous,
                      current: current
                  )
            else { return }
            Task {
                async let momentRefresh: Void = momentModel.refresh()
                async let togetherNowRefresh: Void = togetherNowModel.refresh()
                async let sharedAppointmentRefresh: Void = sharedAppointmentModel
                    .recoverPendingAppointments()
                async let conversationRecovery: Void = conversationModel.recoverPendingMessages()
                _ = await (
                    momentRefresh,
                    togetherNowRefresh,
                    sharedAppointmentRefresh,
                    conversationRecovery
                )
            }
        }
        .onDisappear {
            Task {
                await momentModel.stop()
                await togetherNowModel.stop()
                await sharedAppointmentModel.stop()
                await conversationModel.stop()
            }
        }
    }

    private func refreshRelationshipUnreadBadge() async {
        guard let technicalValidationClient, let relationshipID else { return }
        struct UnreadRow: Decodable {
            let totalUnreadCount: Int
            enum CodingKeys: String, CodingKey { case totalUnreadCount = "total_unread_count" }
        }
        struct Parameters: Encodable {
            let targetRelationshipID: UUID
            enum CodingKeys: String, CodingKey { case targetRelationshipID = "target_relationship_id" }
        }
        do {
            let rows: [UnreadRow] = try await technicalValidationClient.rpc(
                "relationship_unread_counts",
                params: Parameters(targetRelationshipID: relationshipID)
            ).execute().value
            let count = rows.first?.totalUnreadCount ?? 0
            relationshipUnreadCount = count
#if os(iOS)
            UIApplication.shared.applicationIconBadgeNumber = count
#endif
        } catch {
            relationshipUnreadCount = nil
#if os(iOS)
            UIApplication.shared.applicationIconBadgeNumber = displayedUnreadCount
#endif
        }
    }

    private func openSourceMessage(_ source: MomentSource) {
        let requestID = UUID()
        sourceNavigationRequestID = requestID
        conversationFocusMessageID = nil
        appointmentDiscussionFocus = nil
        selection = .conversation
        Task { @MainActor in
            await Task.yield()
            guard sourceNavigationRequestID == requestID else { return }
            if let appointmentID = source.appointmentID {
                appointmentDiscussionFocus = AppointmentDiscussionFocus(
                    appointmentID: appointmentID,
                    messageID: source.messageID
                )
            } else {
                conversationFocusMessageID = source.messageID
            }
        }
    }

    private func refreshAfterSecureNotificationInteraction() async {
        async let momentRefresh: Void = momentModel.refresh()
        async let togetherNowRefresh: Void = togetherNowModel.refresh()
        async let appointmentRefresh: Void = sharedAppointmentModel.refresh()
        async let conversationRefresh: Void = conversationModel.refresh()
        _ = await (
            momentRefresh,
            togetherNowRefresh,
            appointmentRefresh,
            conversationRefresh
        )
    }

    private static func uiTestPhotoData(size: CGSize) -> Data {
        UIGraphicsImageRenderer(size: size).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

private enum UsSurface: Hashable {
    case timeline
    case photos
}

private struct UsView: View {
    @State private var isShowingAccountSettings = false
    @State private var isShowingSharedSchedule = false
    @State private var selectedSurface = UsSurface.timeline
    @ObservedObject var momentModel: MomentModel
    @ObservedObject var togetherNowModel: TogetherNowModel
    @ObservedObject var sharedAppointmentModel: SharedAppointmentModel
    @ObservedObject var conversationModel: ConversationModel
    let accountUserToken: String?
    let accountStatusMessage: String?
    let relationshipToken: String?
    let technicalValidationClient: SupabaseClient?
    let pairingModel: PairingModel?
    let onOpenSourceMessage: (MomentSource) -> Void
    let onSignOut: () -> Void
    let onRelationshipLifecycleChanged: @MainActor () async -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("我們的內容", selection: $selectedSurface) {
                    Text("時間線").tag(UsSurface.timeline)
                    Text("照片").tag(UsSurface.photos)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .accessibilityIdentifier("us-surface-picker")

                switch selectedSurface {
                case .timeline:
                    MomentTimelineView(
                        model: momentModel,
                        togetherNowModel: togetherNowModel,
                        onOpenSourceMessage: onOpenSourceMessage
                    )
                case .photos:
                    MomentPhotoGridView(
                        model: momentModel,
                        togetherNowModel: togetherNowModel,
                        onOpenSourceMessage: onOpenSourceMessage
                    )
                }
                if let accountStatusMessage {
                    Text(accountStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .accessibilityIdentifier("account-status")
                }
            }
            .navigationTitle("我們")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSharedSchedule = true
                    } label: {
                        Label("共同日程", systemImage: "calendar")
                    }
                    .accessibilityIdentifier("open-shared-appointment-schedule")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAccountSettings = true
                    } label: {
                        Label("帳號設定", systemImage: "person.crop.circle")
                    }
                    .accessibilityIdentifier("account-settings")
                }
            }
            .sheet(isPresented: $isShowingAccountSettings) {
                AccountSettingsView(
                    togetherNowModel: togetherNowModel,
                    userToken: accountUserToken,
                    statusMessage: accountStatusMessage,
                    relationshipToken: relationshipToken,
                    technicalValidationClient: technicalValidationClient,
                    pairingModel: pairingModel,
                    hasInFlightContent: conversationModel.isSending || sharedAppointmentModel.isSaving,
                    onSignOut: onSignOut,
                    onRelationshipLifecycleChanged: onRelationshipLifecycleChanged
                )
            }
            .sheet(isPresented: $isShowingSharedSchedule) {
                SharedAppointmentScheduleView(
                    model: sharedAppointmentModel,
                    onMomentSaved: { await momentModel.refresh() }
                )
            }
        }
        .accessibilityIdentifier("us-screen")
        .onAppear {
            isShowingAccountSettings = false
            isShowingSharedSchedule = false
        }
        .onDisappear {
            isShowingAccountSettings = false
            isShowingSharedSchedule = false
        }
    }
}

private struct AccountSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appLockModel: AppLockModel
    @AppStorage(CoupleSpaceTimeFormat.defaultsKey) private var timeFormatRawValue = CoupleSpaceTimeFormat.followSystem.rawValue
    @AppStorage("push-content-preview-enabled") private var showsNotificationContent = false
    @State private var isConfirmingSignOut = false
    @State private var isConfirmingOtherSessionsSignOut = false
    @State private var isShowingTechnicalValidation = false
    @StateObject private var otherSessionsSignOutModel = OtherSessionsSignOutModel()
    @ObservedObject var togetherNowModel: TogetherNowModel
    let userToken: String?
    let statusMessage: String?
    let relationshipToken: String?
    let technicalValidationClient: SupabaseClient?
    let pairingModel: PairingModel?
    let hasInFlightContent: Bool
    let onSignOut: () -> Void
    let onRelationshipLifecycleChanged: @MainActor () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                RelationshipNamesSettingsView(model: togetherNowModel)

                Section("帳號") {
                    LabeledContent("登入方式", value: "Apple")
                    LabeledContent("帳號識別碼", value: userToken ?? "無法取得")
                        .accessibilityIdentifier("account-user-token")
                    Text("識別碼只顯示前 8 碼，可用來確認重新登入後是否仍是同一個 CoupleSpace 帳號。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if technicalValidationClient != nil {
                    Section("登入安全") {
                        Button("登出其他所有登入", role: .destructive) {
                            isConfirmingOtherSessionsSignOut = true
                        }
                        .disabled(otherSessionsSignOutModel.isWorking)
                        .accessibilityIdentifier("other-sessions-sign-out")

                        Text("保留目前裝置；其他登入需要重新使用 Apple 驗證。這不會解除配對或刪除任何內容。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if otherSessionsSignOutModel.isWorking {
                            ProgressView("正在送出……")
                                .accessibilityIdentifier("other-sessions-sign-out-progress")
                        }

                        if let statusMessage = otherSessionsSignOutModel.statusMessage {
                            Text(statusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("other-sessions-sign-out-status")
                        }
                    }
                }

                Section("App Lock") {
                    Toggle(
                        "使用 Face ID 或裝置密碼解鎖",
                        isOn: Binding(
                            get: { appLockModel.isEnabled },
                            set: { appLockModel.setEnabled($0) }
                        )
                    )
                    .accessibilityIdentifier("app-lock-toggle")
                    Text("啟用後，CoupleSpace 進入背景時會遮蔽私密內容；回到 App 時需要重新解鎖。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("時間格式") {
                    Picker("顯示方式", selection: $timeFormatRawValue) {
                        ForEach(CoupleSpaceTimeFormat.allCases) { format in
                            Text(format.title).tag(format.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .accessibilityIdentifier("time-format-picker")
                    Text("此設定只影響這台裝置的時間顯示，不會改變共同資料或伴侶的設定。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("通知") {
                    Toggle("顯示通知內容", isOn: $showsNotificationContent)
                        .onChange(of: showsNotificationContent) { _, isEnabled in
                            Task { await PushNotificationPlatformAdapter.shared.setContentPreviewEnabled(isEnabled) }
                        }
                    Text("開啟後，文字通知會顯示傳送者與內容；照片與共同約定仍不顯示私密細節。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let relationshipToken {
                    Section("伴侶關係") {
                        LabeledContent("關係識別碼", value: relationshipToken)
                            .accessibilityIdentifier("relationship-token")
                        Text("雙方應看到相同的前 8 碼；這不是邀請碼。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let pairingModel {
                    Section("關係與資料") {
                        NavigationLink {
                            RelationshipAndDataSettingsView(
                                pairingModel: pairingModel,
                                hasInFlightContent: hasInFlightContent
                            )
                        } label: {
                            Label("解除配對", systemImage: "person.2.slash")
                        }
                        .accessibilityIdentifier("open-unpairing-settings")
                        Text("解除後，雙方各自保留只能由本人管理的唯讀封存。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let statusMessage {
                    Section("狀態") {
                        Text(statusMessage)
                            .accessibilityIdentifier("account-status")
                    }
                }

                if let togetherNowStatus = togetherNowModel.statusMessage {
                    Section("現在的我們") {
                        Text(togetherNowStatus)
                            .accessibilityIdentifier("together-now-status")
                    }
                }

#if DEBUG
                if technicalValidationClient != nil {
                    Section("開發測試") {
                        Button {
                            isShowingTechnicalValidation = true
                        } label: {
                            Label("W1 技術驗證工具", systemImage: "wrench.and.screwdriver")
                        }
                        .accessibilityIdentifier("w1-technical-tools")

                        Text("可測試訊息、照片、配對、解除關係與個人封存；不屬於正式產品介面。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
#endif

                Section {
                    Button("登出", role: .destructive) {
                        isConfirmingSignOut = true
                    }
                }
            }
            .navigationTitle("帳號設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .alert(
                "登出其他所有登入？",
                isPresented: $isConfirmingOtherSessionsSignOut
            ) {
                Button("登出其他所有登入", role: .destructive) {
                    guard let technicalValidationClient else { return }
                    Task {
                        await otherSessionsSignOutModel.signOutOtherSessions {
                            try await technicalValidationClient.auth.signOut(scope: .others)
                        }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("目前裝置會保持登入。其他裝置需要重新使用 Apple 登入；已簽發的存取權杖可能在到期前短暫有效。這不會解除配對、刪除共同內容或改變個人封存。")
            }
            .alert(
                "要登出 CoupleSpace 嗎？",
                isPresented: $isConfirmingSignOut
            ) {
                Button("登出", role: .destructive) {
                    onSignOut()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("之後可使用同一個 Apple 帳號重新登入。")
            }
#if DEBUG
            .sheet(isPresented: $isShowingTechnicalValidation) {
                if let technicalValidationClient {
                    G1TechnicalSpikeView(
                        supabaseClient: technicalValidationClient,
                        onRelationshipLifecycleChanged: onRelationshipLifecycleChanged
                    )
                }
            }
#endif
        }
    }
}

private struct RelationshipAndDataSettingsView: View {
    @ObservedObject var pairingModel: PairingModel
    let hasInFlightContent: Bool
    @State private var isConfirmingUnpairing = false

    var body: some View {
        Form {
            Section {
                Text("解除配對會停止這段共同空間的新內容。這個動作不能恢復原 relationship，但之後仍可建立新的配對。")
                    .foregroundStyle(.secondary)
            }

            Section("解除後會保留") {
                Label("雙方各自保留一份只屬於自己的唯讀封存", systemImage: "archivebox")
                Label("對方不能刪除、匯出或管理你的封存", systemImage: "lock")
                Label("完成後可匯出封存或建立新的配對", systemImage: "arrow.triangle.2.circlepath")
            }

            Section {
                Button("解除配對", role: .destructive) {
                    isConfirmingUnpairing = true
                }
                .disabled(pairingModel.isWorking)
                .accessibilityIdentifier("begin-unpairing-from-settings")
            }

            if let statusMessage = pairingModel.statusMessage {
                Section("狀態") {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("unpairing-status")
                }
            }
        }
        .navigationTitle("關係與資料")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "確認解除配對？",
            isPresented: $isConfirmingUnpairing,
            titleVisibility: .visible
        ) {
            Button("開始解除配對", role: .destructive) {
                Task {
                    await pairingModel.beginUnpairingAndSealPersonalArchive(
                        hasInFlightContent: hasInFlightContent
                    )
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("開始後，共同空間會停止新增內容，並依序建立你的個人封存。對方需使用自己的帳號建立自己的封存。")
        }
    }
}

#Preview {
    RootTabView()
        .environmentObject(AppLockModel(initiallyEnabled: false))
}
