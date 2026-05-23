import SwiftUI
import WidgetKit

struct LiminalogStatusWidget: Widget {
    let kind = "LiminalogStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Liminalog")
        .description("現在の記録ステータスを表示します。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct StatusEntry: TimelineEntry {
    let date: Date
}

private struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        completion(Timeline(entries: [StatusEntry(date: Date())], policy: .never))
    }
}

private struct StatusWidgetView: View {
    let entry: StatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .systemMedium {
                HStack(spacing: 14) {
                    statusIcon

                    VStack(alignment: .leading, spacing: 6) {
                        title
                        message
                    }

                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    statusIcon
                    title
                    message
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.background, for: .widget)
    }

    private var statusIcon: some View {
        Image(systemName: "timer.circle.fill")
            .font(.title)
            .foregroundStyle(.blue)
    }

    private var title: some View {
        Text("Liminalog")
            .font(.headline)
    }

    private var message: some View {
        Text("記録中の活動はDynamic Islandに表示されます")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(family == .systemMedium ? 2 : 3)
    }
}
