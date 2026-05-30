import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserSettings.createdAt) private var settingsList: [UserSettings]
    @Query private var queriedChapters: [Chapter]
    @Query private var queriedPlans: [PlanBlock]
    @Query(sort: \Friend.createdAt) private var friends: [Friend]

    @State private var isShowingSettings = false
    @State private var isShowingEditProfile = false
    @State private var clock = TickClock(interval: 60)

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
        queriedChapters.sorted { $0.startTime > $1.startTime }
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
                isUnlocked: streakCount >= 7,
                progressText: "\(min(streakCount, 7))/7"
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
                        streak: streakCount,
                        totalDuration: totalRecordedDuration,
                        friendCount: acceptedFriendCount
                    )

                    ProfileCollectionSection(badges: badges)
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
            .task {
                ensureUserSettings()
                clock.start()
            }
            .onDisappear {
                clock.stop()
            }
        }
    }

    private var streakCount: Int {
        let calendar = Calendar.current
        var count = 0
        for offset in 0..<365 {
            guard let target = calendar.date(byAdding: .day, value: -offset, to: clock.now) else { break }
            let summary = scoreSummary(on: target)
            guard summary.plannedDuration > 0, summary.totalScore >= 60 else { break }
            count += 1
        }
        return count
    }

    private var acceptedFriendCount: Int {
        friends.filter { $0.status == .accepted }.count
    }

    private func scoreSummary(on date: Date) -> ScoreSummary {
        ScoreCalculator.summary(
            date: date,
            plans: plans(on: date),
            chapters: chapters(on: date),
            now: clock.now
        )
    }

    private func plans(on date: Date) -> [PlanBlock] {
        let boundary = DayBoundary(date: date)
        return queriedPlans
            .filter { $0.startTime < boundary.dayEnd && $0.endTime > boundary.dayStart }
            .sorted { $0.startTime < $1.startTime }
    }

    private func chapters(on date: Date) -> [Chapter] {
        let boundary = DayBoundary(date: date)
        return queriedChapters
            .filter { $0.startTime < boundary.dayEnd && ($0.endTime ?? clock.now) > boundary.dayStart }
            .sorted { $0.startTime < $1.startTime }
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
}

#Preview("Profile") {
    ProfileView()
        .liminalogPreviewEnvironment()
}
