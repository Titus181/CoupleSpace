import PhotosUI
import SwiftUI
import UIKit

struct TodayMomentView: View {
    @ObservedObject var model: MomentModel
    @State private var isCreatingMoment = false

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
                                authorLabel: model.authorLabel(for: latest)
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
        }
        .accessibilityIdentifier("today-screen")
    }
}

struct MomentTimelineView: View {
    @ObservedObject var model: MomentModel

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
                                authorLabel: model.authorLabel(for: moment)
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
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipped()
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
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("moment-card")
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
                    Text("Moment 會立即進入你們的共同時間線；回應功能會在下一個切片加入。")
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
