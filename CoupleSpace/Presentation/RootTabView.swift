import Supabase
import SwiftUI

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = PrimarySection.defaultSelection
    @State private var conversationFocusMessageID: UUID?
    @State private var appointmentDiscussionFocus: AppointmentDiscussionFocus?
    @State private var sourceNavigationRequestID: UUID?
    @State private var reminderAppointmentID: UUID?
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
    let technicalValidationClient: SupabaseClient?
    let onSignOut: () -> Void

    init(
        accountUserID: UUID? = nil,
        accountUserToken: String? = nil,
        accountStatusMessage: String? = nil,
        relationshipID: UUID? = nil,
        relationshipToken: String? = nil,
        technicalValidationClient: SupabaseClient? = nil,
        onSignOut: @escaping () -> Void = {}
    ) {
        self.accountUserToken = accountUserToken
        self.accountStatusMessage = accountStatusMessage
        self.relationshipToken = relationshipToken
        self.technicalValidationClient = technicalValidationClient
        self.onSignOut = onSignOut
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
                let photoData = Data(base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
                )!
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
                service = InMemoryMomentService(
                    userID: uiTestUserID,
                    moments: textMoments + photoMoments,
                    photoDataByMomentID: Dictionary(
                        uniqueKeysWithValues: photoMoments.map { ($0.id, photoData) }
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
                .badge(conversationModel.unreadCount + sharedAppointmentModel.discussionUnreadCount)

                Tab("我們", systemImage: "person.2", value: PrimarySection.us) {
                    UsView(
                        momentModel: momentModel,
                        togetherNowModel: togetherNowModel,
                        sharedAppointmentModel: sharedAppointmentModel,
                        accountUserToken: accountUserToken,
                        accountStatusMessage: accountStatusMessage,
                        relationshipToken: relationshipToken,
                        technicalValidationClient: technicalValidationClient,
                        onOpenSourceMessage: openSourceMessage,
                        onSignOut: onSignOut
                    )
                }
            }
        }
        .tint(.accentColor)
        .sheet(isPresented: Binding(
            get: { reminderAppointmentID != nil },
            set: { if !$0 { reminderAppointmentID = nil } }
        )) {
            if let reminderAppointmentID {
                NavigationStack {
                    SharedAppointmentDetailView(
                        appointmentID: reminderAppointmentID,
                        model: sharedAppointmentModel,
                        onMomentSaved: { await momentModel.refresh() }
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("關閉") { self.reminderAppointmentID = nil }
                        }
                    }
                }
            }
        }
        .task {
            networkRecoveryMonitor.start()
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
            openPendingAppointmentReminder()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: SharedAppointmentNotificationRoute.didRequestOpen
            )
        ) { notification in
            guard let appointmentID = notification.object as? UUID else { return }
            Task {
                await sharedAppointmentModel.refresh()
                _ = SharedAppointmentNotificationRoute.consumePendingAppointmentID()
                openAppointmentReminder(id: appointmentID)
            }
        }
        .onChange(of: selection) { _, selection in
            Task {
                await conversationModel.setConversationVisible(selection == .conversation)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
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

    private func openPendingAppointmentReminder() {
        guard let appointmentID = SharedAppointmentNotificationRoute
            .consumePendingAppointmentID()
        else { return }
        openAppointmentReminder(id: appointmentID)
    }

    private func openAppointmentReminder(id: UUID) {
        selection = .today
        reminderAppointmentID = id
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
    let accountUserToken: String?
    let accountStatusMessage: String?
    let relationshipToken: String?
    let technicalValidationClient: SupabaseClient?
    let onOpenSourceMessage: (MomentSource) -> Void
    let onSignOut: () -> Void

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
                    onSignOut: onSignOut
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
    @State private var isConfirmingSignOut = false
    @State private var isShowingTechnicalValidation = false
    @ObservedObject var togetherNowModel: TogetherNowModel
    let userToken: String?
    let statusMessage: String?
    let relationshipToken: String?
    let technicalValidationClient: SupabaseClient?
    let onSignOut: () -> Void

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

                if let relationshipToken {
                    Section("伴侶關係") {
                        LabeledContent("關係識別碼", value: relationshipToken)
                            .accessibilityIdentifier("relationship-token")
                        Text("雙方應看到相同的前 8 碼；這不是邀請碼。")
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
                    G1TechnicalSpikeView(supabaseClient: technicalValidationClient)
                }
            }
#endif
        }
    }
}

#Preview {
    RootTabView()
}
