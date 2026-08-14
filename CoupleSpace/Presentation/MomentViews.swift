import PhotosUI
import SwiftUI
import UIKit

struct TodayMomentView: View {
    @ObservedObject var model: MomentModel
    @ObservedObject var togetherNowModel: TogetherNowModel
    @ObservedObject var sharedAppointmentModel: SharedAppointmentModel
    let onOpenSourceMessage: (MomentSource) -> Void
    @State private var isCreatingMoment = false
    @State private var isCreatingQuestion = false

    init(
        model: MomentModel,
        togetherNowModel: TogetherNowModel,
        sharedAppointmentModel: SharedAppointmentModel,
        onOpenSourceMessage: @escaping (MomentSource) -> Void = { _ in }
    ) {
        self.model = model
        self.togetherNowModel = togetherNowModel
        self.sharedAppointmentModel = sharedAppointmentModel
        self.onOpenSourceMessage = onOpenSourceMessage
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("再忙，也能每天留一點位置給彼此。")
                            .font(.title2.weight(.semibold))
                        Text("把零碎日常，慢慢變成我們的生活。")
                            .foregroundStyle(.secondary)
                    }

                    TogetherNowSectionView(model: togetherNowModel)

                    Button {
                        isCreatingMoment = true
                    } label: {
                        Label("留下 Moment", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("create-moment")

                    Button {
                        isCreatingQuestion = true
                    } label: {
                        Label("我們的一題", systemImage: "questionmark.bubble")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("create-question-moment")

                    NextSharedAppointmentSection(
                        model: sharedAppointmentModel,
                        onMomentSaved: { await model.refresh() }
                    )

                    if model.isLoading && model.moments.isEmpty {
                        ProgressView("正在更新你們的此刻…")
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else if let latest = model.moments.first {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("最新的 Moment")
                                .font(.headline)
                            MomentCard(
                                moment: latest,
                                photoData: model.photoDataByMomentID[latest.id],
                                authorLabel: model.authorLabel(
                                    for: latest,
                                    names: togetherNowModel.snapshot
                                ),
                                names: togetherNowModel.snapshot,
                                model: model,
                                onOpenSourceMessage: onOpenSourceMessage
                            )
                        }
                    } else {
                        ContentUnavailableView {
                            Label("Moment・此刻", systemImage: "sparkles")
                        } description: {
                            Text("留下一個心情、一句話或一張照片，開始你們的共同時間線。")
                        }
                        .frame(maxWidth: .infinity, minHeight: 240)
                    }

                    if let statusMessage = model.statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .accessibilityIdentifier("moment-status")
                    }
                }
                .padding()
            }
            .refreshable { await model.refresh() }
            .navigationTitle("今天")
            .sheet(isPresented: $isCreatingMoment) {
                MomentComposerView(model: model)
            }
            .sheet(isPresented: $isCreatingQuestion) {
                QuestionMomentComposerView(model: model)
            }
        }
        .accessibilityIdentifier("today-screen")
    }
}

struct MomentTimelineView: View {
    @ObservedObject var model: MomentModel
    @ObservedObject var togetherNowModel: TogetherNowModel
    let onOpenSourceMessage: (MomentSource) -> Void

    init(
        model: MomentModel,
        togetherNowModel: TogetherNowModel,
        onOpenSourceMessage: @escaping (MomentSource) -> Void = { _ in }
    ) {
        self.model = model
        self.togetherNowModel = togetherNowModel
        self.onOpenSourceMessage = onOpenSourceMessage
    }

    var body: some View {
        Group {
            if model.isLoading && model.moments.isEmpty {
                ProgressView("正在整理共同時間線…")
            } else if model.moments.isEmpty {
                ContentUnavailableView(
                    "共同時間線",
                    systemImage: "sparkles.rectangle.stack",
                    description: Text("你們留下的 Moment 會依時間出現在這裡。")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(model.moments) { moment in
                            MomentCard(
                                moment: moment,
                                photoData: model.photoDataByMomentID[moment.id],
                                authorLabel: model.authorLabel(
                                    for: moment,
                                    names: togetherNowModel.snapshot
                                ),
                                names: togetherNowModel.snapshot,
                                model: model,
                                onOpenSourceMessage: onOpenSourceMessage
                            )
                        }
                    }
                    .padding()
                }
                .refreshable { await model.refresh() }
            }
        }
        .accessibilityIdentifier("moment-timeline")
    }
}

struct MomentCard: View {
    let moment: Moment
    let photoData: Data?
    let authorLabel: String
    let names: TogetherNowSnapshot?
    @ObservedObject var model: MomentModel
    let onOpenSourceMessage: (MomentSource) -> Void
    @State private var isWritingResponse = false
    @State private var isChoosingEmoji = false
    @State private var isAnsweringQuestion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch moment.content {
            case let .mood(mood):
                Label(mood.title, systemImage: mood.symbol)
                    .font(.title3.weight(.semibold))
            case let .text(text):
                Text(text)
                    .font(.body)
            case .photo:
                if let photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .allowsHitTesting(false)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.quaternary)
                        ProgressView()
                    }
                    .frame(height: 180)
                }
            case let .question(question):
                VStack(alignment: .leading, spacing: 8) {
                    Label("我們的一題", systemImage: "questionmark.bubble.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                    Text(question.prompt)
                        .font(.title3.weight(.semibold))
                }
            }

            HStack(spacing: 6) {
                Text(authorLabel)
                    .accessibilityIdentifier("moment-author")
                Text("·")
                    .accessibilityHidden(true)
                Text(moment.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            interactionContent

            if let source = moment.source {
                Divider()
                Button {
                    onOpenSourceMessage(source)
                } label: {
                    Label("查看原對話", systemImage: "bubble.left.and.bubble.right")
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("open-source-conversation")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("moment-card")
        .sheet(isPresented: $isWritingResponse) {
            MomentTextResponseView(moment: moment, model: model)
        }
        .sheet(isPresented: $isChoosingEmoji) {
            EmojiPickerView(
                accessibilityIdentifier: "moment-emoji-picker",
                emojiIdentifierPrefix: "custom-moment-emoji"
            ) { emoji in
                Task { await model.respond(to: moment, with: .text(emoji)) }
            }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isAnsweringQuestion) {
            MomentQuestionAnswerView(moment: moment, model: model)
        }
    }

    @ViewBuilder
    private var interactionContent: some View {
        switch moment.content {
        case .question:
            questionInteraction
        case .mood, .text, .photo:
            standardInteraction
        }
    }

    @ViewBuilder
    private var standardInteraction: some View {
        if let response = model.response(for: moment) {
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(model.responseLabel(for: response, names: names))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                switch response.content {
                case let .emoji(emoji):
                    Text(emoji.symbol)
                        .font(.title2)
                        .accessibilityLabel(emoji.accessibilityLabel)
                case let .text(text):
                    Text(text)
                        .font(MomentResponsePolicy.normalizedEmoji(text) == nil ? .body : .title2)
                }
            }
            .accessibilityIdentifier("moment-response")
        } else if let currentUserID = model.currentUserID,
                  currentUserID != moment.creatorUserID
        {
            Divider()
            Text("回應這一刻")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(MomentEmoji.allCases, id: \.self) { emoji in
                    Button {
                        Task { await model.respond(to: moment, with: .emoji(emoji)) }
                    } label: {
                        Text(emoji.symbol)
                            .font(.title3)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(emoji.accessibilityLabel)
                    .accessibilityIdentifier("moment-emoji-\(emoji.rawValue)")
                    .disabled(model.activeInteractionMomentIDs.contains(moment.id))
                }
                Button { isChoosingEmoji = true } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("更多 Emoji")
                .accessibilityIdentifier("more-moment-emoji")
                .disabled(model.activeInteractionMomentIDs.contains(moment.id))
            }
            Button("回一句") { isWritingResponse = true }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("write-moment-response")
        }
    }

    @ViewBuilder
    private var questionInteraction: some View {
        Divider()
        if moment.isComplete {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(moment.questionAnswers) { answer in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.answerLabel(for: answer, names: names))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(answer.content)
                    }
                }
            }
            .accessibilityIdentifier("question-reveal")
        } else if model.currentUserHasAnswered(moment) {
            Label("回答已送出，等對方有空時一起揭曉。", systemImage: "lock")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("question-waiting")
        } else {
            Button("回答這一題") { isAnsweringQuestion = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("answer-moment-question")
        }
    }
}

struct EmojiPickerView: View {
    private struct EmojiSection: Identifiable {
        let title: String
        let emojis: [String]
        var id: String { title }
    }

    private static let sections = [
        EmojiSection(title: "笑臉與人物", emojis: emojiList(
            "😀 😃 😄 😁 😆 😅 😂 🤣 😊 😇 🙂 🙃 😉 😌 😍 🥰 😘 😗 😙 😚 😋 😛 😝 😜 🤪 🤨 🧐 🤓 😎 🥸 🤩 🥳 😏 😒 😞 😔 😟 😕 🙁 ☹️ 😣 😖 😫 😩 🥺 😢 😭 😤 😠 😡 🤬 🤯 😳 🥵 🥶 😱 😨 😰 😥 😓 🫣 🤗 🫡 🤔 🫢 🤭 🤫 🤥 😶 🫥 😐 🫤 😑 😬 🙄 😯 😦 😧 😮 😲 🥱 😴 🤤 😪 😵 🤐 🥴 🤢 🤮 🤧 😷 🤒 🤕"
        )),
        EmojiSection(title: "手勢與愛心", emojis: emojiList(
            "👋 🤚 🖐️ ✋ 🖖 🫱 🫲 🫳 🫴 👌 🤌 🤏 ✌️ 🤞 🫰 🤟 🤘 🤙 👈 👉 👆 🖕 👇 ☝️ 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 🫶 👐 🤲 🤝 🙏 ✍️ 💅 🤳 💪 🦾 🫂 ❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❤️‍🔥 ❤️‍🩹 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟"
        )),
        EmojiSection(title: "動物與自然", emojis: emojiList(
            "🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐻‍❄️ 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🙈 🙉 🙊 🐒 🐔 🐧 🐦 🐤 🦆 🦅 🦉 🦇 🐺 🐗 🐴 🦄 🐝 🐛 🦋 🐌 🐞 🐜 🕷️ 🦂 🐢 🐍 🦎 🐙 🦑 🦐 🦞 🦀 🐠 🐟 🐡 🐬 🐳 🦈 🐊 🐅 🐆 🦓 🦍 🐘 🦛 🦏 🐪 🦒 🦘 🦬 🐄 🐎 🐖 🐏 🦙 🐐 🦌 🐕 🐈 🦜 🦢 🦩 🕊️ 🐇 🦝 🦨 🦡 🦦 🌸 🌹 🌺 🌻 🌼 🌷 🌱 🌲 🌳 🌴 🌵 🍀 🍁 🍂 🍃"
        )),
        EmojiSection(title: "食物與飲料", emojis: emojiList(
            "🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍈 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🍆 🥑 🥦 🥬 🥒 🌶️ 🫑 🌽 🥕 🫒 🧄 🧅 🥔 🍠 🥐 🥯 🍞 🥖 🥨 🧀 🥚 🍳 🧈 🥞 🧇 🥓 🥩 🍗 🍖 🌭 🍔 🍟 🍕 🥪 🥙 🌮 🌯 🥗 🥘 🍝 🍜 🍲 🍛 🍣 🍱 🥟 🍤 🍙 🍚 🍘 🍥 🥠 🥮 🍢 🍡 🍧 🍨 🍦 🥧 🧁 🍰 🎂 🍮 🍭 🍬 🍫 🍿 🍩 🍪 🌰 🥜 🍯 🥛 ☕️ 🫖 🍵 🧃 🥤 🧋 🍺 🍻 🥂 🍷 🍸 🍹 🍾"
        )),
        EmojiSection(title: "活動與旅行", emojis: emojiList(
            "⚽️ 🏀 🏈 ⚾️ 🥎 🎾 🏐 🏉 🥏 🎱 🪀 🏓 🏸 🏒 🏑 🥍 🏏 🥅 ⛳️ 🪁 🏹 🎣 🤿 🥊 🥋 🎽 🛹 🛼 🛷 ⛸️ 🥌 🎿 ⛷️ 🏂 🪂 🏋️ 🤸 ⛹️ 🤺 🤾 🏌️ 🏄 🚣 🏊 🚴 🧗 🎪 🎭 🎨 🎬 🎤 🎧 🎼 🎹 🥁 🎷 🎺 🎸 🎻 🎲 ♟️ 🎯 🎳 🎮 🧩 🚗 🚕 🚌 🚎 🏎️ 🚓 🚑 🚒 🚐 🛻 🚚 🚜 🛵 🏍️ 🚲 ✈️ 🚀 🚁 🚤 ⛵️ 🚢 🚆 🚇 🗺️ 🗿 🗽 🗼 🏰 🎡 🎢 🎠 ⛲️ 🏖️ 🏝️ 🏕️ ⛺️ 🌋 🗻"
        )),
        EmojiSection(title: "物件與符號", emojis: emojiList(
            "⌚️ 📱 💻 ⌨️ 🖥️ 🖨️ 🖱️ 📷 📸 📹 🎥 📞 ☎️ 📺 📻 🎙️ ⏰ ⌛️ 🔋 💡 🔦 🕯️ 🧯 💸 💵 💰 💳 💎 ⚖️ 🧰 🔧 🔨 🛠️ ⛏️ 🪛 ⚙️ 🧱 🧲 🔮 📿 🧿 💈 ⚗️ 🔭 🔬 💊 💉 🩹 🩺 🚪 🪑 🛏️ 🛋️ 🚿 🛁 🧴 🧹 🧺 🧻 🧼 🪥 🧽 🔑 🗝️ 🧸 🎁 🎈 🎀 🎊 🎉 🪅 ✉️ 📩 📦 📌 📍 📎 ✂️ 🖊️ ✏️ 📝 📚 🔒 🔓 🔔 🎵 ✅ ❌ ❓ ❗️ 💯 🔥 ✨ ⭐️ 🌟 💫 ⚡️ ☀️ 🌙 🌈 ☁️ ❄️ ☔️"
        )),
    ]

    private static func emojiList(_ value: String) -> [String] {
        value.split(separator: " ").map(String.init)
    }

    @Environment(\.dismiss) private var dismiss
    let accessibilityIdentifier: String
    let emojiIdentifierPrefix: String
    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(Self.sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title)
                                .font(.headline)
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible()), count: 7),
                                spacing: 12
                            ) {
                                ForEach(Array(section.emojis.enumerated()), id: \.offset) { _, emoji in
                                    Button {
                                        dismiss()
                                        onSelect(emoji)
                                    } label: {
                                        Text(emoji)
                                            .font(.title2)
                                            .frame(maxWidth: .infinity, minHeight: 36)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(emoji)
                                    .accessibilityIdentifier("\(emojiIdentifierPrefix)-\(emoji)")
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("選擇 Emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct MomentComposerView: View {
    private enum ComposerKind: String, CaseIterable, Identifiable {
        case mood = "心情"
        case text = "一句話"
        case photo = "照片"

        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: MomentModel
    @State private var kind = ComposerKind.mood
    @State private var mood = MomentMood.calm
    @State private var text = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var preparedPhoto: PreparedPhotoAssets?
    @State private var selectionError: String?

    private var draft: MomentDraft? {
        switch kind {
        case .mood:
            return .mood(mood)
        case .text:
            guard let normalized = MomentDraftPolicy.normalizedText(text) else { return nil }
            return .text(normalized)
        case .photo:
            guard let preparedPhoto else { return nil }
            return .photo(preparedPhoto.fullData)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Moment 類型", selection: $kind) {
                    ForEach(ComposerKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                switch kind {
                case .mood:
                    Section("現在的心情") {
                        ForEach(MomentMood.allCases, id: \.self) { option in
                            Button {
                                mood = option
                            } label: {
                                HStack {
                                    Label(option.title, systemImage: option.symbol)
                                    Spacer()
                                    if mood == option {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                case .text:
                    Section("想留下的一句話") {
                        TextEditor(text: $text)
                            .frame(minHeight: 120)
                            .accessibilityIdentifier("moment-text")
                        Text("\(text.count)/\(MomentDraftPolicy.maximumTextLength)")
                            .font(.caption)
                            .foregroundStyle(text.count > MomentDraftPolicy.maximumTextLength ? .red : .secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                case .photo:
                    Section("這一刻的照片") {
                        if let image = preparedPhoto?.preview {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 260)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label(
                                preparedPhoto == nil ? "選擇照片" : "更換照片",
                                systemImage: "photo"
                            )
                        }
                        if let selectionError {
                            Text(selectionError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Text("Moment 會立即進入你們的共同時間線，伴侶可以用 Emoji 或一句話回應。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("留下 Moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("留下") {
                        guard let draft else { return }
                        Task {
                            if await model.create(draft) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(draft == nil || model.isSaving)
                    .accessibilityIdentifier("save-moment")
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    defer { selectedPhoto = nil }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            selectionError = "無法讀取這張照片。"
                            return
                        }
                        preparedPhoto = try PhotoAssetProcessor.prepare(data)
                        selectionError = nil
                    } catch {
                        selectionError = "無法準備這張照片，請改選另一張。"
                    }
                }
            }
        }
        .accessibilityIdentifier("moment-composer")
    }
}

private struct QuestionMomentComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: MomentModel
    @State private var selectedQuestion = MomentQuestionPrompt.accepted[0]
    @State private var answer = ""

    private var draft: MomentQuestionDraft? {
        guard MomentQuestionPolicy.normalizedAnswer(answer) != nil else { return nil }
        return MomentQuestionDraft(questionKey: selectedQuestion.id, answer: answer)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("選一題") {
                    Picker("題目", selection: $selectedQuestion) {
                        ForEach(MomentQuestionPrompt.accepted) { question in
                            Text(question.prompt).tag(question)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("你的回答") {
                    TextEditor(text: $answer)
                        .frame(minHeight: 140)
                        .accessibilityIdentifier("question-answer-text")
                    Text("\(answer.count)/\(MomentQuestionPolicy.maximumAnswerLength)")
                        .font(.caption)
                        .foregroundStyle(
                            answer.count > MomentQuestionPolicy.maximumAnswerLength ? .red : .secondary
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Section {
                    Label("你的回答會先鎖住；伴侶回答後才一起揭曉。", systemImage: "lock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("我們的一題")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("送出") {
                        guard let draft else { return }
                        Task {
                            if await model.createQuestion(draft) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(draft == nil || model.isSaving)
                    .accessibilityIdentifier("save-question-moment")
                }
            }
        }
        .accessibilityIdentifier("question-moment-composer")
    }
}

private struct MomentTextResponseView: View {
    @Environment(\.dismiss) private var dismiss
    let moment: Moment
    @ObservedObject var model: MomentModel
    @State private var text = ""

    private var normalizedText: String? {
        MomentResponsePolicy.normalizedText(text)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("回一句") {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                        .accessibilityIdentifier("moment-response-text")
                    Text("\(text.count)/\(MomentResponsePolicy.maximumTextLength)")
                        .font(.caption)
                        .foregroundStyle(
                            text.count > MomentResponsePolicy.maximumTextLength ? .red : .secondary
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .navigationTitle("回應 Moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("送出") {
                        guard let normalizedText else { return }
                        Task {
                            if await model.respond(to: moment, with: .text(normalizedText)) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(normalizedText == nil || model.activeInteractionMomentIDs.contains(moment.id))
                    .accessibilityIdentifier("save-moment-response")
                }
            }
        }
    }
}

private struct MomentQuestionAnswerView: View {
    @Environment(\.dismiss) private var dismiss
    let moment: Moment
    @ObservedObject var model: MomentModel
    @State private var answer = ""

    private var normalizedAnswer: String? {
        MomentQuestionPolicy.normalizedAnswer(answer)
    }

    var body: some View {
        NavigationStack {
            Form {
                if case let .question(question) = moment.content {
                    Section("我們的一題") {
                        Text(question.prompt)
                            .font(.headline)
                    }
                }
                Section("你的回答") {
                    TextEditor(text: $answer)
                        .frame(minHeight: 140)
                        .accessibilityIdentifier("partner-question-answer-text")
                    Text("\(answer.count)/\(MomentQuestionPolicy.maximumAnswerLength)")
                        .font(.caption)
                        .foregroundStyle(
                            answer.count > MomentQuestionPolicy.maximumAnswerLength ? .red : .secondary
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Section {
                    Label("送出後，兩人的回答會一起揭曉。", systemImage: "sparkles")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("回答這一題")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("送出") {
                        guard let normalizedAnswer else { return }
                        Task {
                            if await model.answer(moment, text: normalizedAnswer) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        normalizedAnswer == nil || model.activeInteractionMomentIDs.contains(moment.id)
                    )
                    .accessibilityIdentifier("save-question-answer")
                }
            }
        }
    }
}
