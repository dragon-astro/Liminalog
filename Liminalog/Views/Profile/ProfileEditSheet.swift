import PhotosUI
import SwiftUI
import UIKit

struct ProfileEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var bio: String
    @State private var imageData: Data?
    @State private var badgeID: String
    @State private var iconFrameID: String
    @State private var streakIconID: String
    @State private var cardStyleID: String
    @State private var selectedPhoto: PhotosPickerItem?

    let badges: [ProfileBadgeModel]
    let unlocks: ProfileDecorationUnlocks
    let onSave: (ProfileDraft) -> Void

    init(
        settings: UserSettings?,
        badges: [ProfileBadgeModel],
        unlocks: ProfileDecorationUnlocks,
        onSave: @escaping (ProfileDraft) -> Void
    ) {
        _displayName = State(initialValue: settings?.profileDisplayName ?? "")
        _bio = State(initialValue: settings?.profileBio ?? "")
        _imageData = State(initialValue: settings?.profileImageData)
        _badgeID = State(initialValue: ProfileBadgeCatalog.equippedBadge(id: settings?.profileBadgeID, badges: badges).id)
        _iconFrameID = State(initialValue: unlocks.equippedIconFrameID(settings?.profileIconFrameID))
        _streakIconID = State(initialValue: unlocks.equippedStreakIconID(settings?.profileStreakIconID))
        _cardStyleID = State(initialValue: unlocks.equippedCardStyleID(settings?.profileCardStyleID))
        self.badges = badges
        self.unlocks = unlocks
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
                            accentColor: visualAccentColor,
                            frameStyle: ProfileIconFrameCatalog.item(for: iconFrameID),
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

                Section("装備") {
                    ProfileBadgeSelector(
                        badges: badges,
                        selectedID: $badgeID
                    )

                    ProfileFrameSelector(
                        selectedID: $iconFrameID,
                        accentColor: visualAccentColor,
                        unlockedIDs: unlocks.iconFrameIDs
                    )

                    ProfileStreakIconSelector(
                        selectedID: $streakIconID,
                        unlockedIDs: unlocks.streakIconIDs
                    )

                    ProfileCardStyleSelector(
                        selectedID: $cardStyleID,
                        accentColor: visualAccentColor,
                        unlockedIDs: unlocks.cardStyleIDs
                    )
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
                                badgeID: badgeID,
                                iconFrameID: iconFrameID,
                                streakIconID: streakIconID,
                                cardStyleID: cardStyleID
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

    private var visualAccentColor: Color {
        ProfileIconFrameCatalog.item(for: iconFrameID).primaryColor
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

private struct ProfileBadgeSelector: View {
    let badges: [ProfileBadgeModel]
    @Binding var selectedID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("バッジ")
                .font(.subheadline.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(badges) { badge in
                        ProfileSelectableBadge(badge: badge, isSelected: selectedID == badge.id) {
                            guard badge.isUnlocked else { return }
                            selectedID = badge.id
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProfileSelectableBadge: View {
    let badge: ProfileBadgeModel
    let isSelected: Bool
    let action: () -> Void

    private var tint: Color {
        Color(hex: badge.tint)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(badge.isUnlocked ? tint.opacity(0.16) : Color(.tertiarySystemGroupedBackground))
                    Image(systemName: badge.isUnlocked ? badge.systemImage : "lock.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(badge.isUnlocked ? tint : Color.secondary)
                }
                .frame(width: 44, height: 44)

                Text(badge.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 74)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? tint : .clear, lineWidth: 2)
            }
            .opacity(badge.isUnlocked ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!badge.isUnlocked)
    }
}

private struct ProfileFrameSelector: View {
    @Binding var selectedID: String
    let accentColor: Color
    let unlockedIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("アイコンフレーム")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(ProfileIconFrameCatalog.items) { item in
                    let isUnlocked = unlockedIDs.contains(item.id)
                    Button {
                        guard isUnlocked else { return }
                        selectedID = item.id
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                ProfileIconFrameView(style: item, accentColor: accentColor, size: 44)
                                if !isUnlocked {
                                    Image(systemName: "lock.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                        .padding(5)
                                        .background(Color(.secondarySystemGroupedBackground), in: Circle())
                                }
                            }
                            .frame(width: 48, height: 48)
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(selectedID == item.id ? item.primaryColor : .clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!isUnlocked)
                    .opacity(isUnlocked ? 1 : 0.48)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProfileStreakIconSelector: View {
    @Binding var selectedID: String
    let unlockedIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ストリーク")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                ForEach(ProfileStreakIconCatalog.items) { item in
                    let isUnlocked = unlockedIDs.contains(item.id)
                    Button {
                        guard isUnlocked else { return }
                        selectedID = item.id
                    } label: {
                        VStack(spacing: 7) {
                            ZStack {
                                Image(systemName: isUnlocked ? item.systemImage : "lock.fill")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(isUnlocked ? Color(hex: item.tintHex) : Color.secondary)
                                    .frame(width: 44, height: 44)
                                    .background((isUnlocked ? Color(hex: item.tintHex) : Color.secondary).opacity(0.14), in: Circle())
                            }
                            Text(item.title)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(selectedID == item.id ? Color(hex: item.tintHex) : .clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!isUnlocked)
                    .opacity(isUnlocked ? 1 : 0.48)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProfileCardStyleSelector: View {
    @Binding var selectedID: String
    let accentColor: Color
    let unlockedIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("プロフィールカード")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(ProfileCardStyleCatalog.items) { item in
                    let isUnlocked = unlockedIDs.contains(item.id)
                    Button {
                        guard isUnlocked else { return }
                        selectedID = item.id
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: isUnlocked ? item.systemImage : "lock.fill")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(isUnlocked ? item.markColor(accentColor: accentColor) : Color.secondary)
                                Spacer()
                                if selectedID == item.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(item.markColor(accentColor: accentColor))
                                }
                            }

                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)

                            ProfileCardStylePreview(style: item, accentColor: accentColor)
                        }
                        .padding(10)
                        .background(item.backgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(selectedID == item.id ? item.borderColor(accentColor: accentColor) : Color(.separator).opacity(0.12), lineWidth: selectedID == item.id ? 2 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!isUnlocked)
                    .opacity(isUnlocked ? 1 : 0.48)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProfileCardStylePreview: View {
    let style: ProfileCardStyle
    let accentColor: Color

    var body: some View {
        HStack(spacing: 4) {
            style.stripColor(accentColor: accentColor)
                .frame(width: 28)
            Color.clear
                .frame(width: 8)
            style.stripColor(accentColor: accentColor).opacity(0.45)
                .frame(width: 42)
            Color.clear
            style.stripColor(accentColor: accentColor).opacity(0.65)
                .frame(width: 24)
        }
        .frame(height: 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(Capsule())
    }
}

struct ProfileDraft {
    let displayName: String
    let bio: String
    let imageData: Data?
    let badgeID: String
    let iconFrameID: String
    let streakIconID: String
    let cardStyleID: String
}
