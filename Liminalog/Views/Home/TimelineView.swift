import SwiftUI

struct TimelineView: View {
    @Environment(ChapterStore.self) private var store
    @Binding var editingChapter: Chapter?

    @State private var chapters: [Chapter] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("タイムライン")
                    .font(.title3.bold())
                Spacer()
                Text(Date(), style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)

            if chapters.isEmpty {
                Text("まだ記録がありません")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(chapters) { chapter in
                    TimelineChapterCard(chapter: chapter) {
                        editingChapter = chapter
                    }
                }
            }
        }
        .onAppear { refresh() }
        .onChange(of: store.activeChapter?.id) { _, _ in refresh() }
    }

    private func refresh() {
        chapters = store.todaysChapters()
    }
}
