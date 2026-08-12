import SwiftUI

struct TogetherNowSectionView: View {
    @ObservedObject var model: TogetherNowModel
    @State private var isEditingStatus = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("現在的我們")
                    .font(.headline)
                    .accessibilityIdentifier("together-now-heading")
                Spacer()
                Text("由彼此主動設定")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.isLoading && model.snapshot == nil {
                ProgressView("正在更新狀態…")
                    .frame(maxWidth: .infinity, minHeight: 110)
            } else if let snapshot = model.snapshot {
                HStack(alignment: .top, spacing: 12) {
                    statusCard(
                        label: snapshot.partnerLabel,
                        status: snapshot.partnerStatus,
                        isCurrentUser: false
                    )
                    statusCard(
                        label: snapshot.currentUserLabel,
                        status: snapshot.currentStatus,
                        isCurrentUser: true
                    )
                }
            } else {
                Text("目前無法讀取狀態，稍後下拉重新整理。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }

            Text("這不是在線或已讀狀態；過期後會自動回到尚未設定。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $isEditingStatus) {
            CurrentStatusEditorView(model: model)
        }
    }

    @ViewBuilder
    private func statusCard(
        label: String,
        status: CurrentRelationshipStatus?,
        isCurrentUser: Bool
    ) -> some View {
        if isCurrentUser {
            Button {
                isEditingStatus = true
            } label: {
                statusCardContent(label: label, status: status, showsEditIndicator: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("current-user-status-card")
        } else {
            statusCardContent(label: label, status: status, showsEditIndicator: false)
                .accessibilityIdentifier("partner-status-card")
        }
    }

    private func statusCardContent(
        label: String,
        status: CurrentRelationshipStatus?,
        showsEditIndicator: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if showsEditIndicator {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }

            if let status {
                Label(status.content.title, systemImage: symbol(for: status.content))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(expirationText(for: status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("尚未設定", systemImage: "circle.dashed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func symbol(for content: CurrentStatusContent) -> String {
        switch content {
        case let .fixed(kind): kind.symbol
        case .custom: "text.bubble"
        }
    }

    private func expirationText(for status: CurrentRelationshipStatus) -> String {
        guard let expiresAt = status.expiresAt else { return "直到手動清除" }
        return "到 " + expiresAt.formatted(date: .omitted, time: .shortened)
    }
}

private struct CurrentStatusEditorView: View {
    private enum Choice: String, CaseIterable, Identifiable {
        case busy
        case availableToTalk = "available_to_talk"
        case quiet
        case tired
        case needCompany = "need_company"
        case needHug = "need_hug"
        case thinkingOfYou = "thinking_of_you"
        case custom

        var id: Self { self }

        var title: String {
            if self == .custom { return "自訂短句" }
            return CurrentStatusKind(rawValue: rawValue)?.title ?? rawValue
        }

        var fixedKind: CurrentStatusKind? {
            CurrentStatusKind(rawValue: rawValue)
        }
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: TogetherNowModel
    @State private var choice = Choice.busy
    @State private var customText = ""
    @State private var expiration = CurrentStatusExpiration.oneHour
    @State private var savesAsMoment = false
    @State private var loadedExistingStatus = false

    private var draft: CurrentStatusDraft? {
        let content: CurrentStatusContent
        if choice == .custom {
            guard let text = TogetherNowTextPolicy.normalizedCustomStatus(customText) else {
                return nil
            }
            content = .custom(text)
        } else {
            guard let kind = choice.fixedKind else { return nil }
            content = .fixed(kind)
        }
        return CurrentStatusDraft(
            content: content,
            expiration: expiration,
            savesAsMoment: savesAsMoment
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("現在的狀態") {
                    Picker("選擇狀態", selection: $choice) {
                        ForEach(Choice.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .accessibilityIdentifier("current-status-choice")

                    if choice == .custom {
                        TextField("最多 40 字", text: $customText, axis: .vertical)
                            .lineLimit(2...3)
                            .accessibilityIdentifier("current-status-custom-text")
                        Text("\(customText.unicodeScalars.count)/\(TogetherNowTextPolicy.maximumCustomStatusLength)")
                            .font(.caption)
                            .foregroundStyle(
                                customText.unicodeScalars.count > TogetherNowTextPolicy.maximumCustomStatusLength
                                    ? .red
                                    : .secondary
                            )
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                Section("維持時間") {
                    Picker("狀態會維持", selection: $expiration) {
                        ForEach(CurrentStatusExpiration.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .accessibilityIdentifier("current-status-expiration")
                }

                Section {
                    Toggle("也留成 Moment", isOn: $savesAsMoment)
                        .accessibilityIdentifier("save-status-as-moment")
                    Text("預設只更新現在的狀態；開啟後才會另外留下不可被後續狀態改寫的 Moment。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if model.snapshot?.currentStatus != nil {
                    Section {
                        Button("清除目前狀態", role: .destructive) {
                            Task {
                                if await model.clearStatus() { dismiss() }
                            }
                        }
                        .disabled(model.isSaving)
                        .accessibilityIdentifier("clear-current-status")
                    }
                }
            }
            .navigationTitle("更新此刻狀態")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        guard let draft else { return }
                        Task {
                            if await model.saveStatus(draft) { dismiss() }
                        }
                    }
                    .disabled(draft == nil || model.isSaving)
                    .accessibilityIdentifier("save-current-status")
                }
            }
            .onAppear { loadExistingStatusIfNeeded() }
        }
    }

    private func loadExistingStatusIfNeeded() {
        guard !loadedExistingStatus, let status = model.snapshot?.currentStatus else { return }
        loadedExistingStatus = true
        expiration = status.expiration
        switch status.content {
        case let .fixed(kind):
            choice = Choice(rawValue: kind.rawValue) ?? .busy
        case let .custom(text):
            choice = .custom
            customText = text
        }
    }
}

struct RelationshipNamesSettingsView: View {
    @ObservedObject var model: TogetherNowModel
    @State private var displayName = ""
    @State private var privatePartnerName = ""
    @State private var loaded = false

    var body: some View {
        Section("我們如何稱呼彼此") {
            TextField("我的顯示名稱", text: $displayName)
                .accessibilityIdentifier("display-name-input")
            Text("伴侶看得到；不要求真實姓名或全域唯一。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("清除我的名稱", role: .destructive) {
                Task {
                    let savedPartnerName = model.snapshot?.privatePartnerName ?? ""
                    if await model.saveNames(
                        displayName: "",
                        privatePartnerName: savedPartnerName
                    ) {
                        displayName = ""
                    }
                }
            }
            .disabled(model.isSaving || model.snapshot?.currentDisplayName == nil)
            .accessibilityIdentifier("clear-display-name")

            TextField("我對伴侶的稱呼", text: $privatePartnerName)
                .accessibilityIdentifier("private-partner-name-input")
            Text("只有你看得到，不會改變伴侶設定的名稱。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("清除伴侶名稱", role: .destructive) {
                Task {
                    let savedDisplayName = model.snapshot?.currentDisplayName ?? ""
                    if await model.saveNames(
                        displayName: savedDisplayName,
                        privatePartnerName: ""
                    ) {
                        privatePartnerName = ""
                    }
                }
            }
            .disabled(model.isSaving || model.snapshot?.privatePartnerName == nil)
            .accessibilityIdentifier("clear-private-partner-name")

            Button("儲存稱呼") {
                Task {
                    _ = await model.saveNames(
                        displayName: displayName,
                        privatePartnerName: privatePartnerName
                    )
                }
            }
            .disabled(
                model.isSaving
                    || !TogetherNowTextPolicy.isValidOptionalNameInput(displayName)
                    || !TogetherNowTextPolicy.isValidOptionalNameInput(privatePartnerName)
            )
            .accessibilityIdentifier("save-relationship-names")
        }
        .onAppear {
            loadNamesIfNeeded(from: model.snapshot)
        }
        .onChange(of: model.snapshot) { _, snapshot in
            loadNamesIfNeeded(from: snapshot)
        }
    }

    private func loadNamesIfNeeded(from snapshot: TogetherNowSnapshot?) {
        guard !loaded, let snapshot else { return }
        loaded = true
        displayName = snapshot.currentDisplayName ?? ""
        privatePartnerName = snapshot.privatePartnerName ?? ""
    }
}
