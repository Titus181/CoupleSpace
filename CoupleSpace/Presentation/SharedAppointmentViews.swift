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
                SharedAppointmentCard(appointment: appointment, model: model)
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
        .accessibilityIdentifier("next-shared-appointment")
    }
}

struct SharedAppointmentComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: SharedAppointmentModel
    @State private var title: String
    @State private var startsAt = Date().addingTimeInterval(3_600)
    @State private var location = ""
    @State private var note = ""
    @State private var reminderEnabled = false
    @State private var reminderAt = Date().addingTimeInterval(1_800)
    private let sourceMessageID: UUID?

    init(
        model: SharedAppointmentModel,
        initialTitle: String = "",
        sourceMessageID: UUID? = nil
    ) {
        self.model = model
        _title = State(initialValue: initialTitle)
        self.sourceMessageID = sourceMessageID
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
            .navigationTitle("建立共同約定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("建立") {
                        Task {
                            if await model.create(draft) { dismiss() }
                        }
                    }
                    .disabled(
                        model.isSaving
                            || SharedAppointmentPolicy.normalizedDraft(draft) == nil
                    )
                    .accessibilityIdentifier("confirm-shared-appointment")
                }
            }
        }
    }
}
