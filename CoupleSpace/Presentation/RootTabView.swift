import SwiftUI

struct RootTabView: View {
    @State private var selection = PrimarySection.defaultSelection

    var body: some View {
        TabView(selection: $selection) {
            Tab("今天", systemImage: "sun.max", value: PrimarySection.today) {
                TodayView()
            }

            Tab("對話", systemImage: "bubble.left.and.bubble.right", value: PrimarySection.conversation) {
                ConversationView()
            }

            Tab("我們", systemImage: "person.2", value: PrimarySection.us) {
                UsView()
            }
        }
        .tint(.accentColor)
    }
}

private struct TodayView: View {
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

                    ContentUnavailableView {
                        Label("Moment・此刻", systemImage: "sparkles")
                    } description: {
                        Text("之後可以在這裡留下心情、照片或一句話。")
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                }
                .padding()
            }
            .navigationTitle("今天")
        }
        .accessibilityIdentifier("today-screen")
    }
}

private struct ConversationView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "兩人的對話",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("配對後，日常對話會留在這裡。")
            )
            .navigationTitle("對話")
        }
        .accessibilityIdentifier("conversation-screen")
    }
}

private struct UsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "我們的生活",
                systemImage: "person.2",
                description: Text("共同時間線、日程與收藏會慢慢累積在這裡。")
            )
            .navigationTitle("我們")
        }
        .accessibilityIdentifier("us-screen")
    }
}

#Preview {
    RootTabView()
}
