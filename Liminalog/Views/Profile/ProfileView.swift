import SwiftUI

struct ProfileView: View {
    @Environment(ChapterStore.self) private var store
    @State private var displayName = "Ryu"
    @State private var bio = "切り替わる瞬間を記録中"
    @State private var isShowingSettings = false

    private var recentChapters: [Chapter] {
        store.recentChapters(limit: 10_000)
    }

    private var totalRecordedDuration: TimeInterval {
        recentChapters.reduce(0) { total, chapter in
            total + max(0, chapter.durationLive)
        }
    }

    private var diaryDays: [Date] {
        let grouped = Dictionary(grouping: recentChapters) { chapter in
            DayBoundary.dayStart(for: chapter.startTime)
        }
        return grouped.keys.sorted(by: >).prefix(12).map(\.self)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    identityZone
                    statsRow
                    collectionPreview
                    diaryPreview
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.title3.weight(.semibold))
                    }
                    .accessibilityLabel("設定")
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
    }

    private var identityZone: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(.linearGradient(colors: [.blue, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(String(displayName.prefix(1)))
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                }
                .frame(width: 82, height: 82)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("名前", text: $displayName)
                        .font(.title2.bold())
                        .textInputAutocapitalization(.never)

                    TextField("自己紹介", text: $bio, axis: .vertical)
                        .font(.subheadline)
                        .lineLimit(2...3)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            ProfileStatTile(title: "連続", value: "\(store.streakCount())日", systemImage: "flame.fill")
            ProfileStatTile(title: "累計", value: formatDuration(totalRecordedDuration), systemImage: "clock.fill")
            ProfileStatTile(title: "友達", value: "0人", systemImage: "person.2.fill")
        }
    }

    private var collectionPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionHeader(title: "コレクション", subtitle: "解放した記録を飾る場所")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(0..<6, id: \.self) { index in
                        ProfileCollectionBadge(index: index)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var diaryPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionHeader(title: "日記カード", subtitle: "毎日の記録がここに蓄積されます")

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                if diaryDays.isEmpty {
                    ForEach(0..<6, id: \.self) { _ in
                        ProfileDiaryPlaceholder()
                    }
                } else {
                    ForEach(diaryDays, id: \.self) { date in
                        ProfileDiaryTile(date: date)
                    }
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = max(0, Int(duration / 60))
        if minutes < 60 {
            return "\(minutes)分"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)時間" : "\(hours)時間\(remainingMinutes)分"
    }
}

private struct ProfileStatTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

private struct ProfileSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProfileCollectionBadge: View {
    let index: Int

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemGroupedBackground))
                Circle()
                    .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
                Image(systemName: index == 0 ? "sparkles" : "lock.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(index == 0 ? Color.accentColor : Color.secondary)
            }
            .frame(width: 58, height: 58)

            Text(index == 0 ? "はじめる" : "未解放")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 68)
    }
}

private struct ProfileDiaryTile: View {
    let date: Date

    var body: some View {
        VStack(alignment: .leading) {
            Spacer()
            Text(Self.dayFormatter.string(from: date))
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(8)
        }
        .frame(height: 112)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.linearGradient(colors: [.indigo, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d"
        return formatter
    }()
}

private struct ProfileDiaryPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(height: 112)
    }
}

#Preview("Profile") {
    ProfileView()
        .liminalogPreviewEnvironment()
}
