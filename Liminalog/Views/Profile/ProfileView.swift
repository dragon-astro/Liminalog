import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ChapterStore.self) private var store
    @Query(sort: \UserSettings.createdAt) private var settingsList: [UserSettings]

    @State private var isShowingSettings = false
    @State private var isShowingEditProfile = false
    @State private var selectedDigest: ProfileDayDigest?

    private var settings: UserSettings? {
        settingsList.first
    }

    private var displayName: String {
        let name = settings?.profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Liminalogユーザー" : name
    }

    private var bio: String {
        settings?.profileBio.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var accentColor: Color {
        Color(hex: settings?.profileAccentColorHex ?? "#2F80ED")
    }

    private var recentChapters: [Chapter] {
        store.recentChapters(limit: 10_000)
    }

    private var finishedChapters: [Chapter] {
        recentChapters.filter { $0.endTime != nil }
    }

    private var totalRecordedDuration: TimeInterval {
        recentChapters.reduce(0) { total, chapter in
            total + max(0, chapter.durationLive)
        }
    }

    private var recordedDays: [Date] {
        let grouped = Dictionary(grouping: recentChapters) { chapter in
            DayBoundary.dayStart(for: chapter.startTime)
        }
        return grouped.keys.sorted(by: >)
    }

    private var diaryDigests: [ProfileDayDigest] {
        Dictionary(grouping: recentChapters) { chapter in
            DayBoundary.dayStart(for: chapter.startTime)
        }
        .map { day, chapters in
            ProfileDayDigest(date: day, chapters: chapters.sorted { $0.startTime < $1.startTime })
        }
        .sorted { $0.date > $1.date }
    }

    private var badges: [ProfileBadgeModel] {
        [
            ProfileBadgeModel(
                title: "はじめの記録",
                systemImage: "sparkles",
                tint: "#2F80ED",
                isUnlocked: !recentChapters.isEmpty,
                progressText: recentChapters.isEmpty ? "0/1" : "達成"
            ),
            ProfileBadgeModel(
                title: "3日記録",
                systemImage: "calendar.badge.checkmark",
                tint: "#27AE60",
                isUnlocked: recordedDays.count >= 3,
                progressText: "\(min(recordedDays.count, 3))/3"
            ),
            ProfileBadgeModel(
                title: "7日連続",
                systemImage: "flame.fill",
                tint: "#EB5757",
                isUnlocked: store.streakCount() >= 7,
                progressText: "\(min(store.streakCount(), 7))/7"
            ),
            ProfileBadgeModel(
                title: "10時間",
                systemImage: "clock.fill",
                tint: "#6C5CE7",
                isUnlocked: totalRecordedDuration >= 36_000,
                progressText: "\(min(Int(totalRecordedDuration / 3600), 10))/10h"
            ),
            ProfileBadgeModel(
                title: "朝の記録",
                systemImage: "sunrise.fill",
                tint: "#F2994A",
                isUnlocked: finishedChapters.contains { Calendar.current.component(.hour, from: $0.startTime) < 9 },
                progressText: finishedChapters.contains { Calendar.current.component(.hour, from: $0.startTime) < 9 } ? "達成" : "未達成"
            )
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ProfileHero(
                        displayName: displayName,
                        bio: bio,
                        imageData: settings?.profileImageData,
                        accentColor: accentColor,
                        onEdit: { isShowingEditProfile = true }
                    )

                    ProfileStatsRow(
                        streak: store.streakCount(),
                        totalDuration: totalRecordedDuration,
                        friendCount: 0
                    )

                    ProfileCollectionSection(badges: badges)

                    ProfileDiarySection(digests: Array(diaryDigests.prefix(18))) { digest in
                        selectedDigest = digest
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 36)
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
            .navigationDestination(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $isShowingEditProfile) {
                ProfileEditSheet(settings: settings, onSave: saveProfile)
            }
            .sheet(item: $selectedDigest) { digest in
                ProfileDiaryDetailSheet(digest: digest)
            }
            .task {
                ensureUserSettings()
            }
        }
    }

    private func ensureUserSettings() {
        guard settingsList.isEmpty else { return }
        let settings = UserSettings()
        modelContext.insert(settings)
        try? modelContext.save()
    }

    private func saveProfile(_ draft: ProfileDraft) {
        let target: UserSettings
        if let settings {
            target = settings
        } else {
            let created = UserSettings()
            modelContext.insert(created)
            target = created
        }

        target.profileDisplayName = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.profileBio = draft.bio.trimmingCharacters(in: .whitespacesAndNewlines)
        target.profileImageData = draft.imageData
        target.profileAccentColorHex = draft.accentColorHex
        target.updatedAt = Date()
        try? modelContext.save()
    }
}

private struct ProfileHero: View {
    let displayName: String
    let bio: String
    let imageData: Data?
    let accentColor: Color
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                ProfilePhotoView(displayName: displayName, imageData: imageData, accentColor: accentColor, size: 88)

                VStack(alignment: .leading, spacing: 8) {
                    Text(displayName)
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(bio.isEmpty ? " " : bio)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(minHeight: 36, alignment: .topLeading)
                }
            }

            Button(action: onEdit) {
                Label("編集", systemImage: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(accentColor)
        }
    }
}

private struct ProfilePhotoView: View {
    let displayName: String
    let imageData: Data?
    let accentColor: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(accentColor.gradient)

            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            Circle()
                .stroke(.white.opacity(0.75), lineWidth: 2)
        }
        .shadow(color: accentColor.opacity(0.2), radius: 14, y: 6)
    }

    private var initial: String {
        String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }
}

private struct ProfileStatsRow: View {
    let streak: Int
    let totalDuration: TimeInterval
    let friendCount: Int

    var body: some View {
        HStack(spacing: 10) {
            ProfileStatTile(title: "連続", value: "\(streak)日", systemImage: "flame.fill")
            ProfileStatTile(title: "累計", value: ProfileFormat.duration(totalDuration), systemImage: "clock.fill")
            ProfileStatTile(title: "友達", value: "\(friendCount)人", systemImage: "person.2.fill")
        }
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
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

private struct ProfileCollectionSection: View {
    let badges: [ProfileBadgeModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionHeader(title: "コレクション")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(badges) { badge in
                        ProfileCollectionBadge(badge: badge)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct ProfileCollectionBadge: View {
    let badge: ProfileBadgeModel

    private var tint: Color {
        Color(hex: badge.tint)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(badge.isUnlocked ? tint.opacity(0.18) : Color(.secondarySystemGroupedBackground))
                Circle()
                    .stroke(badge.isUnlocked ? tint.opacity(0.65) : Color(.separator).opacity(0.4), lineWidth: 1)
                Image(systemName: badge.isUnlocked ? badge.systemImage : "lock.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(badge.isUnlocked ? tint : Color.secondary)
            }
            .frame(width: 62, height: 62)

            Text(badge.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(badge.progressText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 78)
        .opacity(badge.isUnlocked ? 1 : 0.55)
    }
}

private struct ProfileDiarySection: View {
    let digests: [ProfileDayDigest]
    let onSelect: (ProfileDayDigest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                ProfileSectionHeader(title: "日記カード")
                Spacer()
                Text("1日の表紙")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 2), spacing: 9) {
                if digests.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in
                        ProfileDiaryPlaceholder()
                    }
                } else {
                    ForEach(digests) { digest in
                        Button {
                            onSelect(digest)
                        } label: {
                            ProfileDiaryTile(digest: digest)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct ProfileDiaryTile: View {
    let digest: ProfileDayDigest

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tileGradient)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ProfileFormat.monthDay(digest.date))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.82))
                        Text(digest.autoTitle)
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                    }

                    Spacer(minLength: 6)

                    Image(systemName: digest.mainCategory?.icon ?? "sparkles")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.16), in: Circle())
                }

                Spacer(minLength: 0)

                ProfileRhythmStrip(segments: digest.rhythmSegments)
                    .frame(height: 28)

                HStack(spacing: 6) {
                    Text(digest.mainCategory?.name ?? "記録")
                        .font(.caption.weight(.bold))
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Text(ProfileFormat.duration(digest.totalDuration))
                        .font(.caption.monospacedDigit().weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.9))

                Text(digest.summaryText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(1)
            }
            .padding(12)
        }
        .frame(height: 178)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var tileGradient: LinearGradient {
        let base = digest.mainCategory.map { Color(hex: $0.colorHex) } ?? Color.accentColor
        let secondary = digest.topCategories.dropFirst().first.map { Color(hex: $0.colorHex) } ?? base.opacity(0.58)
        return LinearGradient(
            colors: [
                base.opacity(0.92),
                secondary.opacity(0.68),
                Color.black.opacity(0.84)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct ProfileDiaryPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.title3.weight(.semibold))
                    Text("記録すると表紙ができます")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.tertiary)
            }
            .frame(height: 178)
    }
}

private struct ProfileRhythmStrip: View {
    let segments: [ProfileRhythmSegment]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.16))

                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(hex: segment.colorHex).opacity(0.95))
                        .frame(width: max(2, proxy.size.width * segment.widthRatio))
                        .offset(x: proxy.size.width * segment.startRatio)
                }
            }
        }
        .clipShape(Capsule())
    }
}

private struct ProfileDiaryDetailSheet: View {
    let digest: ProfileDayDigest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        ProfileDiaryTile(digest: digest)
                            .listRowInsets(EdgeInsets())

                        Text(ProfileFormat.fullDate(digest.date))
                            .font(.title3.weight(.bold))
                        Text(digest.summaryText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("記録") {
                    ForEach(digest.chapters, id: \.id) { chapter in
                        HStack(spacing: 12) {
                            Image(systemName: chapter.category?.icon ?? "circle.fill")
                                .foregroundStyle(chapter.category.map { Color(hex: $0.colorHex) } ?? .secondary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(chapter.category?.name ?? "未分類")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(ProfileFormat.time(chapter.startTime)) - \(ProfileFormat.time(chapter.endTime ?? Date()))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if !chapter.isPublic {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("日記カード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ProfileSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
    }
}

private struct ProfileEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var bio: String
    @State private var imageData: Data?
    @State private var accentColorHex: String
    @State private var selectedPhoto: PhotosPickerItem?

    let onSave: (ProfileDraft) -> Void

    init(settings: UserSettings?, onSave: @escaping (ProfileDraft) -> Void) {
        _displayName = State(initialValue: settings?.profileDisplayName ?? "")
        _bio = State(initialValue: settings?.profileBio ?? "")
        _imageData = State(initialValue: settings?.profileImageData)
        _accentColorHex = State(initialValue: settings?.profileAccentColorHex ?? "#2F80ED")
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        ProfilePhotoView(
                            displayName: displayName.isEmpty ? "L" : displayName,
                            imageData: imageData,
                            accentColor: Color(hex: accentColorHex),
                            size: 76
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Label("写真を選択", systemImage: "photo")
                            }

                            if imageData != nil {
                                Button(role: .destructive) {
                                    imageData = nil
                                } label: {
                                    Label("写真を削除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("プロフィール") {
                    TextField("名前", text: $displayName)
                        .textInputAutocapitalization(.never)

                    TextField("自己紹介", text: $bio, axis: .vertical)
                        .lineLimit(3...5)
                }

                Section("カラー") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(ProfileAccentColor.allCases) { color in
                            Button {
                                accentColorHex = color.hex
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: color.hex))
                                        .frame(width: 42, height: 42)
                                    if accentColorHex == color.hex {
                                        Image(systemName: "checkmark")
                                            .font(.headline.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("プロフィール編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        onSave(
                            ProfileDraft(
                                displayName: displayName,
                                bio: bio,
                                imageData: imageData,
                                accentColorHex: accentColorHex
                            )
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: selectedPhoto) { _, newPhoto in
                Task {
                    guard let data = try? await newPhoto?.loadTransferable(type: Data.self) else { return }
                    imageData = Self.normalizedImageData(from: data) ?? data
                }
            }
        }
    }

    private static func normalizedImageData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxDimension: CGFloat = 640
        let longestSide = max(image.size.width, image.size.height)
        let scale = longestSide > 0 ? min(1, maxDimension / longestSide) : 1
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: 0.82)
    }
}

private struct ProfileDraft {
    let displayName: String
    let bio: String
    let imageData: Data?
    let accentColorHex: String
}

private struct ProfileDayDigest: Identifiable {
    let date: Date
    let chapters: [Chapter]

    var id: Date { date }

    var totalDuration: TimeInterval {
        chapters.reduce(0) { $0 + max(0, $1.durationLive) }
    }

    var mainCategory: Category? {
        categoryDurations.max { lhs, rhs in lhs.duration < rhs.duration }?.category
    }

    var topCategories: [Category] {
        categoryDurations
            .sorted { $0.duration > $1.duration }
            .map(\.category)
    }

    var autoTitle: String {
        guard !chapters.isEmpty else { return "記録のない日" }
        let categoryName = mainCategory?.name ?? "記録"
        let hourSpread = activeHourSpread
        if totalDuration >= 8 * 3600 {
            return "\(categoryName)に浸った日"
        }
        if publicRatio < 0.4 {
            return "静かに過ごした日"
        }
        if hourSpread >= 10 {
            return "長く動いた日"
        }
        if chapters.count >= 6 {
            return "切り替え上手な日"
        }
        return "\(categoryName)が主役の日"
    }

    var summaryText: String {
        let categoryCount = Set(chapters.compactMap { $0.category?.id }).count
        if let mainCategory {
            return "\(categoryCount)カテゴリ / \(mainCategory.name)中心"
        }
        return "\(chapters.count)件の記録"
    }

    var rhythmSegments: [ProfileRhythmSegment] {
        let boundary = DayBoundary(date: date)
        let dayDuration = boundary.dayEnd.timeIntervalSince(boundary.dayStart)
        guard dayDuration > 0 else { return [] }

        return chapters.compactMap { chapter in
            guard let category = chapter.category else { return nil }
            let start = max(chapter.startTime, boundary.dayStart)
            let end = min(chapter.endTime ?? Date(), boundary.dayEnd)
            guard end > start else { return nil }
            return ProfileRhythmSegment(
                startRatio: start.timeIntervalSince(boundary.dayStart) / dayDuration,
                widthRatio: end.timeIntervalSince(start) / dayDuration,
                colorHex: category.colorHex
            )
        }
    }

    private var categoryDurations: [(category: Category, duration: TimeInterval)] {
        var durations: [UUID: (Category, TimeInterval)] = [:]
        for chapter in chapters {
            guard let category = chapter.category else { continue }
            let current = durations[category.id]?.1 ?? 0
            durations[category.id] = (category, current + max(0, chapter.durationLive))
        }
        return Array(durations.values)
    }

    private var activeHourSpread: Int {
        let hours = chapters.map { Calendar.current.component(.hour, from: $0.startTime) }
        guard let min = hours.min(), let max = hours.max() else { return 0 }
        return max - min
    }

    private var publicRatio: Double {
        guard !chapters.isEmpty else { return 0 }
        let publicCount = chapters.filter(\.isPublic).count
        return Double(publicCount) / Double(chapters.count)
    }
}

private struct ProfileRhythmSegment: Identifiable {
    let id = UUID()
    let startRatio: Double
    let widthRatio: Double
    let colorHex: String
}

private struct ProfileBadgeModel: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let tint: String
    let isUnlocked: Bool
    let progressText: String
}

private enum ProfileAccentColor: String, CaseIterable, Identifiable {
    case blue = "#2F80ED"
    case violet = "#6C5CE7"
    case green = "#27AE60"
    case orange = "#F2994A"
    case red = "#EB5757"
    case pink = "#D946EF"
    case teal = "#00A8A8"
    case gray = "#607D8B"

    var id: String { rawValue }
    var hex: String { rawValue }
}

private enum ProfileFormat {
    static func duration(_ duration: TimeInterval) -> String {
        let minutes = max(0, Int(duration / 60))
        if minutes < 60 {
            return "\(minutes)分"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)時間" : "\(hours)時間\(remainingMinutes)分"
    }

    static func monthDay(_ date: Date) -> String {
        monthDayFormatter.string(from: date)
    }

    static func fullDate(_ date: Date) -> String {
        fullDateFormatter.string(from: date)
    }

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d"
        return formatter
    }()

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "H:mm"
        return formatter
    }()
}

#Preview("Profile") {
    ProfileView()
        .liminalogPreviewEnvironment()
}
