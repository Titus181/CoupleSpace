import SwiftUI
import UIKit

struct NextSharedAppointmentSection: View {
    @ObservedObject var model: SharedAppointmentModel
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("下一個共同約定")
                    .font(.headline)
                Spacer()
                Button {
                    isCreating = true
                } label: {
                    Label("建立", systemImage: "plus")
                }
                .accessibilityIdentifier("create-shared-appointment")
            }

            if model.isLoading && model.appointments.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else if let appointment = model.nextAppointment {
                if appointment.deliveryState == .synced {
                    NavigationLink {
                        SharedAppointmentDetailView(
                            appointmentID: appointment.id,
                            model: model
                        )
                    } label: {
                        SharedAppointmentCard(appointment: appointment, model: model)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("next-shared-appointment")
                } else {
                    SharedAppointmentCard(appointment: appointment, model: model)
                        .accessibilityIdentifier("next-shared-appointment")
                }
            } else {
                Button {
                    isCreating = true
                } label: {
                    Label("安排一個兩人的約定", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }

            if let statusMessage = model.statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("shared-appointment-status")
            }
        }
        .sheet(isPresented: $isCreating) {
            SharedAppointmentComposerView(model: model)
        }
    }
}

private struct SharedAppointmentCard: View {
    let appointment: SharedAppointment
    @ObservedObject var model: SharedAppointmentModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appointment.title)
                .font(.title3.weight(.semibold))
            Label(
                appointment.startsAt.formatted(date: .abbreviated, time: .shortened),
                systemImage: "calendar"
            )
            if let location = appointment.location {
                Label(location, systemImage: "mappin.and.ellipse")
            }
            if let note = appointment.note {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            switch appointment.deliveryState {
            case .sending:
                Text("等待同步")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed:
                Button("同步失敗，點此重試") {
                    Task { await model.retryAppointment(id: appointment.id) }
                }
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("retry-shared-appointment")
            case .synced:
                EmptyView()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct SharedAppointmentScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: SharedAppointmentModel
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SharedAppointmentCalendarView(model: model)
                    } label: {
                        Label("查看月曆", systemImage: "calendar")
                    }
                    .accessibilityIdentifier("open-shared-appointment-calendar")
                }

                Section("近期") {
                    if model.upcomingAppointments.isEmpty {
                        Text("目前沒有即將到來的共同約定。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.upcomingAppointments) { appointment in
                            appointmentLink(appointment)
                        }
                    }
                }

                Section("過往與已取消") {
                    if model.pastOrCancelledAppointments.isEmpty {
                        Text("過往約定會保留在這裡。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.pastOrCancelledAppointments) { appointment in
                            appointmentLink(appointment)
                        }
                    }
                }

                if let statusMessage = model.statusMessage {
                    Section("狀態") {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("共同日程")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("建立共同約定")
                    .accessibilityIdentifier("create-appointment-from-schedule")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .refreshable { await model.refresh() }
            .sheet(isPresented: $isCreating) {
                SharedAppointmentComposerView(model: model)
            }
        }
        .accessibilityIdentifier("shared-appointment-schedule")
    }

    private func appointmentLink(_ appointment: SharedAppointment) -> some View {
        NavigationLink {
            SharedAppointmentDetailView(
                appointmentID: appointment.id,
                model: model
            )
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(appointment.title)
                        .font(.body.weight(.semibold))
                    Spacer()
                    if appointment.status == .cancelled {
                        Text("已取消")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(appointment.startsAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("shared-appointment-row-\(appointment.id.uuidString.lowercased())")
    }
}

private struct SharedAppointmentCalendarView: View {
    @ObservedObject var model: SharedAppointmentModel
    @State private var selectedDate = Date()

    private var selectedAppointments: [SharedAppointment] {
        model.appointments(on: selectedDate)
    }

    var body: some View {
        List {
            Section {
                DatePicker(
                    "選擇日期",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .accessibilityIdentifier("shared-appointment-calendar")
            }

            Section(selectedDate.formatted(date: .complete, time: .omitted)) {
                if selectedAppointments.isEmpty {
                    Text("這一天沒有共同約定。")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("shared-appointment-calendar-empty")
                } else {
                    ForEach(selectedAppointments) { appointment in
                        NavigationLink {
                            SharedAppointmentDetailView(
                                appointmentID: appointment.id,
                                model: model
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(appointment.title)
                                        .font(.body.weight(.semibold))
                                    Spacer()
                                    if appointment.status == .cancelled {
                                        Text("已取消")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(appointment.startsAt.formatted(date: .omitted, time: .shortened))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier(
                            "calendar-appointment-row-\(appointment.id.uuidString.lowercased())"
                        )
                    }
                }
            }
        }
        .navigationTitle("共同月曆")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("shared-appointment-calendar-screen")
    }
}

struct SharedAppointmentDetailView: View {
    @ObservedObject var model: SharedAppointmentModel
    let appointmentID: UUID
    @State private var isEditing = false
    @State private var isConfirmingCancellation = false

    init(appointmentID: UUID, model: SharedAppointmentModel) {
        self.appointmentID = appointmentID
        self.model = model
    }

    var body: some View {
        Group {
            if let appointment = model.appointment(id: appointmentID) {
                List {
                    Section("約定") {
                        LabeledContent("標題", value: appointment.title)
                        LabeledContent(
                            "開始時間",
                            value: appointment.startsAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                        if let location = appointment.location {
                            LabeledContent("地點", value: location)
                        }
                        if let note = appointment.note {
                            LabeledContent("註記", value: note)
                        }
                        if let reminderAt = appointment.reminderAt {
                            LabeledContent(
                                "提醒",
                                value: reminderAt.formatted(date: .abbreviated, time: .shortened)
                            )
                        }
                        LabeledContent(
                            "狀態",
                            value: appointment.status == .scheduled ? "已安排" : "已取消"
                        )
                    }

                    if appointment.status == .cancelled {
                        Section {
                            Text("這筆約定已取消；原內容會保留在你們的過往約定中。")
                                .foregroundStyle(.secondary)
                        }
                    } else if appointment.deliveryState == .synced {
                        Section {
                            Button("編輯共同約定") { isEditing = true }
                                .accessibilityIdentifier("edit-shared-appointment")
                            Button("取消共同約定", role: .destructive) {
                                isConfirmingCancellation = true
                            }
                            .accessibilityIdentifier("cancel-shared-appointment")
                        }
                    } else {
                        Section {
                            Text("等待同步完成後即可編輯或取消。")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("約定詳情")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $isEditing) {
                    SharedAppointmentComposerView(
                        model: model,
                        appointment: appointment
                    )
                }
                .alert("要取消這筆共同約定嗎？", isPresented: $isConfirmingCancellation) {
                    Button("取消約定", role: .destructive) {
                        Task { _ = await model.cancel(id: appointmentID) }
                    }
                    Button("保留", role: .cancel) {}
                } message: {
                    Text("取消後不會刪除內容，雙方仍可在過往約定中查看。")
                }
            } else {
                ContentUnavailableView(
                    "找不到共同約定",
                    systemImage: "calendar.badge.exclamationmark"
                )
            }
        }
        .accessibilityIdentifier("shared-appointment-detail")
    }
}

struct SharedAppointmentComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: SharedAppointmentModel
    @State private var title: String
    @State private var startsAt: Date
    @State private var location: String
    @State private var note: String
    @State private var reminderEnabled: Bool
    @State private var reminderAt: Date
    private let appointmentID: UUID?
    private let sourceMessageID: UUID?

    init(
        model: SharedAppointmentModel,
        initialTitle: String = "",
        sourceMessageID: UUID? = nil
    ) {
        self.model = model
        _title = State(initialValue: initialTitle)
        let initialStartsAt = Date().addingTimeInterval(3_600)
        _startsAt = State(initialValue: initialStartsAt)
        _location = State(initialValue: "")
        _note = State(initialValue: "")
        _reminderEnabled = State(initialValue: false)
        _reminderAt = State(initialValue: initialStartsAt.addingTimeInterval(-1_800))
        appointmentID = nil
        self.sourceMessageID = sourceMessageID
    }

    init(model: SharedAppointmentModel, appointment: SharedAppointment) {
        self.model = model
        _title = State(initialValue: appointment.title)
        _startsAt = State(initialValue: appointment.startsAt)
        _location = State(initialValue: appointment.location ?? "")
        _note = State(initialValue: appointment.note ?? "")
        _reminderEnabled = State(initialValue: appointment.reminderAt != nil)
        _reminderAt = State(initialValue:
            appointment.reminderAt ?? appointment.startsAt.addingTimeInterval(-1_800)
        )
        appointmentID = appointment.id
        sourceMessageID = appointment.sourceMessageID
    }

    private var draft: SharedAppointmentDraft {
        SharedAppointmentDraft(
            title: title,
            startsAt: startsAt,
            location: location,
            note: note,
            reminderAt: reminderEnabled ? min(reminderAt, startsAt) : nil,
            sourceMessageID: sourceMessageID
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("約定") {
                    TextField("標題", text: $title)
                        .accessibilityIdentifier("appointment-title")
                    DatePicker("開始時間", selection: $startsAt)
                    TextField("地點（選填）", text: $location)
                    TextField("短註記（選填）", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("提醒") {
                    Toggle("設定一次提醒", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker(
                            "提醒時間",
                            selection: $reminderAt,
                            in: ...startsAt
                        )
                    }
                }

                Section {
                    Text(sourceMessageID == nil
                         ? "建立後會同步給你們兩人；不會加入外部行事曆。"
                         : "已帶入原訊息文字；請自行確認標題、日期與時間後再建立。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(appointmentID == nil ? "建立共同約定" : "編輯共同約定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(appointmentID == nil ? "建立" : "儲存") {
                        Task {
                            let succeeded: Bool
                            if let appointmentID {
                                succeeded = await model.update(id: appointmentID, draft: draft)
                            } else {
                                succeeded = await model.create(draft)
                            }
                            if succeeded { dismiss() }
                        }
                    }
                    .disabled(
                        model.isSaving
                            || SharedAppointmentPolicy.normalizedDraft(draft) == nil
                    )
                    .accessibilityIdentifier(
                        appointmentID == nil
                            ? "confirm-shared-appointment"
                            : "save-shared-appointment"
                    )
                }
            }
        }
    }
}
