import SwiftUI
import Combine

struct CurrentChapterCard: View {
    @Environment(ChapterStore.self) private var store
    @State private var elapsedTime: TimeInterval = 0

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
        .frame(height: 48)
    }

    private func activeCard(chapter: Chapter, category: Category) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(category.color.opacity(0.12))
            .overlay(
                HStack(spacing: 12) {
                    Circle()
                        .fill(category.color)
                        .frame(width: 10, height: 10)
                        .shadow(color: category.color.opacity(0.4), radius: 4, x: 0, y: 2)

                    Text(category.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Spacer()

                    Text(formatDuration(elapsedTime))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)

                    Button {
                        store.endActiveChapter()
                    } label: {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(category.color)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("記録を終了")

                    Button {
                        store.setChapterVisibility(chapter, isPublic: !chapter.isPublic)
                    } label: {
                        Image(systemName: chapter.isPublic ? "eye" : "eye.slash")
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
            )
            .onReceive(timer) { _ in
                elapsedTime = chapter.durationLive
            }
            .onAppear {
                elapsedTime = chapter.durationLive
            }
    }

    private var placeholderCard: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay(
                Text("カテゴリをタップして記録を開始")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            )
    }
}
