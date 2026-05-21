import SwiftUI

struct TimelineChapterCard: View {
    let chapter: Chapter
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Time column
            VStack(alignment: .trailing, spacing: 2) {
                Text(chapter.startTime.shortTime)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary)
                if let end = chapter.endTime {
                    Text(end.shortTime)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 52)
            .padding(.top, 6)

            // Connector
            VStack(spacing: 0) {
                Circle()
                    .fill(chapter.category?.color ?? Color(.systemGray3))
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }

            // Content card
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let cat = chapter.category {
                            Text(cat.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(cat.color)
                        }
                        Spacer()
                        if let duration = chapter.duration {
                            Text(formatDuration(duration))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else {
                            Label("記録中", systemImage: "circle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(chapter.category?.color ?? .accentColor)
                                .symbolEffect(.pulse)
                        }
                    }

                    if let note = chapter.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if let mood = chapter.mood {
                        Text(mood)
                            .font(.caption)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 4)
    }
}
