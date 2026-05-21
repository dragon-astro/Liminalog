import SwiftUI
import Combine

struct CurrentChapterCard: View {
    @Environment(ChapterStore.self) private var store
    @State private var elapsedTime: TimeInterval = 0
    @State private var isPublic = true

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let chapter = store.activeChapter, let category = chapter.category {
                activeCard(chapter: chapter, category: category)
            } else {
                placeholderCard
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
    }

    private func activeCard(chapter: Chapter, category: Category) -> some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(category.color.opacity(0.12))
            .overlay(
                HStack(spacing: 12) {
                    Circle()
                        .fill(category.color)
                        .frame(width: 14, height: 14)
                        .shadow(color: category.color.opacity(0.4), radius: 4, x: 0, y: 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                            .font(.headline)
                        Text(formatDuration(elapsedTime))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        isPublic.toggle()
                    } label: {
                        Image(systemName: isPublic ? "eye" : "eye.slash")
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
            )
            .onReceive(timer) { _ in
                elapsedTime = chapter.durationLive
            }
            .onAppear {
                elapsedTime = chapter.durationLive
            }
    }

    private var placeholderCard: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay(
                Text("カテゴリをタップして記録を開始")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            )
    }
}
