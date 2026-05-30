import SwiftUI
import SwiftData

struct CurrentChapterCard: View {
    @Environment(ChapterStore.self) private var store
    @Query private var activeChapters: [Chapter]
    @State private var clock = TickClock()

    init() {
        _activeChapters = Query(
            filter: #Predicate<Chapter> { $0.endTime == nil },
            sort: [SortDescriptor(\.startTime, order: .reverse)]
        )
    }

    var body: some View {
        Group {
            if let chapter = activeChapter, let category = chapter.category {
                activeCard(chapter: chapter, category: category)
            } else {
                placeholderCard
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .onAppear {
            clock.start()
        }
        .onDisappear {
            clock.stop()
        }
    }

    private var activeChapter: Chapter? {
        activeChapters.first
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

                    Text(formatDuration(clock.now.timeIntervalSince(chapter.startTime)))
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
