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
    @State private var pendingCropImage: ProfilePhotoCropDraft?
    @State private var photoLoadError: String?
    @State private var saveError: String?
    @State private var activeTab: EditTab = .basics

    enum EditTab: String, CaseIterable, Identifiable {
        case basics, badge, frame, streak, card
        var id: String { rawValue }
        var title: String {
            switch self {
            case .basics: return "基本"
            case .badge: return "バッジ"
            case .frame: return "フレーム"
            case .streak: return "ストリーク"
            case .card: return "カード"
            }
        }
    }

    let badges: [ProfileBadgeModel]
    let unlocks: ProfileDecorationUnlocks
    let onSave: (ProfileDraft) -> Bool

    init(
        settings: UserSettings?,
        badges: [ProfileBadgeModel],
        unlocks: ProfileDecorationUnlocks,
        onSave: @escaping (ProfileDraft) -> Bool
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
            VStack(spacing: 0) {
                previewHeader

                Picker("", selection: $activeTab) {
                    ForEach(EditTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                Form {
                    switch activeTab {
                    case .basics:
                        basicsContent
                    case .badge:
                        Section {
                            ProfileBadgeSelector(badges: badges, selectedID: $badgeID)
                        }
                    case .frame:
                        Section {
                            ProfileFrameSelector(
                                selectedID: $iconFrameID,
                                accentColor: visualAccentColor,
                                unlockedIDs: unlocks.iconFrameIDs
                            )
                        }
                    case .streak:
                        Section {
                            ProfileStreakIconSelector(
                                selectedID: $streakIconID,
                                unlockedIDs: unlocks.streakIconIDs
                            )
                        }
                    case .card:
                        Section {
                            ProfileCardStyleSelector(
                                selectedID: $cardStyleID,
                                accentColor: visualAccentColor,
                                unlockedIDs: unlocks.cardStyleIDs
                            )
                        }
                    }
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
                        let didSave = onSave(
                            ProfileDraft(
                                displayName: trimmedDisplayName,
                                bio: trimmedBio,
                                imageData: imageData,
                                badgeID: badgeID,
                                iconFrameID: iconFrameID,
                                streakIconID: streakIconID,
                                cardStyleID: cardStyleID
                            )
                        )
                        if didSave {
                            dismiss()
                        } else {
                            saveError = "時間をおいてもう一度試してください。"
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: selectedPhoto) { _, newPhoto in
                Task {
                    await loadPhoto(newPhoto)
                }
            }
            .fullScreenCover(item: $pendingCropImage) { draft in
                ProfilePhotoCropView(
                    image: draft.image,
                    accentColor: visualAccentColor,
                    frameStyle: ProfileIconFrameCatalog.item(for: iconFrameID)
                ) { croppedData in
                    imageData = croppedData
                    pendingCropImage = nil
                    selectedPhoto = nil
                } onCancel: {
                    pendingCropImage = nil
                    selectedPhoto = nil
                }
            }
            .alert("保存できませんでした", isPresented: saveErrorPresented) {
                Button("OK", role: .cancel) {
                    saveError = nil
                }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var previewHeader: some View {
        VStack(spacing: 12) {
            ProfileHero(
                displayName: previewDisplayName,
                bio: trimmedBio,
                imageData: imageData,
                accentColor: visualAccentColor,
                equippedBadge: resolvedBadge,
                iconFrame: ProfileIconFrameCatalog.item(for: iconFrameID),
                cardStyle: resolvedCardStyle,
                showsActions: false,
                onEdit: {},
                onShare: {}
            )
            .animation(.snappy(duration: 0.28), value: previewSignature)

            streakChip
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(LiminalTheme.canvasGradient)
    }

    private var streakChip: some View {
        let style = ProfileStreakIconCatalog.item(for: streakIconID)
        return HStack(spacing: 7) {
            Image(systemName: style.systemImage)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color(hex: style.tintHex))
            Text("ストリーク・\(style.title)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LiminalTheme.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(LiminalTheme.surface, in: Capsule())
        .animation(.snappy(duration: 0.28), value: streakIconID)
    }

    @ViewBuilder
    private var basicsContent: some View {
        Section {
            HStack(spacing: 16) {
                ProfilePhotoView(
                    displayName: previewDisplayName,
                    imageData: imageData,
                    accentColor: visualAccentColor,
                    frameStyle: ProfileIconFrameCatalog.item(for: iconFrameID),
                    size: 76
                )

                VStack(alignment: .leading, spacing: 10) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("写真を選択", systemImage: "photo")
                    }

                    if let photoLoadError {
                        Text(photoLoadError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if imageData != nil {
                        Button(role: .destructive) {
                            imageData = nil
                            photoLoadError = nil
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
    }

    private var resolvedBadge: ProfileBadgeModel {
        ProfileBadgeCatalog.equippedBadge(id: badgeID, badges: badges)
    }

    private var resolvedCardStyle: ProfileCardStyle {
        ProfileCardStyleCatalog.item(for: cardStyleID)
    }

    private var previewSignature: String {
        "\(badgeID)|\(iconFrameID)|\(cardStyleID)"
    }

    private var visualAccentColor: Color {
        ProfileIconFrameCatalog.item(for: iconFrameID).primaryColor
    }

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedBio: String {
        bio.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var previewDisplayName: String {
        trimmedDisplayName.isEmpty ? "L" : trimmedDisplayName
    }

    private var saveErrorPresented: Binding<Bool> {
        Binding {
            saveError != nil
        } set: { isPresented in
            if !isPresented {
                saveError = nil
            }
        }
    }

    @MainActor
    private func loadPhoto(_ photo: PhotosPickerItem?) async {
        photoLoadError = nil
        guard let photo else { return }

        do {
            guard let data = try await photo.loadTransferable(type: Data.self) else {
                photoLoadError = "写真を読み込めませんでした"
                return
            }
            guard let image = Self.preparedImage(from: data) else {
                photoLoadError = "写真を読み込めませんでした"
                return
            }
            pendingCropImage = ProfilePhotoCropDraft(image: image)
        } catch {
            NSLog("Liminalog: failed to load profile photo: \(String(describing: error))")
            photoLoadError = "写真を読み込めませんでした"
        }
    }

    private static func preparedImage(from data: Data) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        let maxDimension: CGFloat = 1600
        let longestSide = max(image.size.width, image.size.height)
        let scale = longestSide > 0 ? min(1, maxDimension / longestSide) : 1
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private struct ProfilePhotoCropDraft: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ProfilePhotoCropView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let accentColor: Color
    let frameStyle: ProfileIconFrameStyle
    let onUse: (Data) -> Void
    let onCancel: () -> Void

    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1

    private let cropDiameter: CGFloat = 292
    private let outputSide: CGFloat = 640
    private let minZoom: CGFloat = 1
    private let maxZoom: CGFloat = 4
    private var frameDiameter: CGFloat { cropDiameter + max(16, cropDiameter * 0.16) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 26) {
                Spacer(minLength: 12)

                cropSurface

                HStack(spacing: 14) {
                    Image(systemName: "minus.magnifyingglass")
                        .foregroundStyle(LiminalTheme.secondaryText)
                    Slider(value: zoomBinding, in: minZoom...maxZoom)
                    Image(systemName: "plus.magnifyingglass")
                        .foregroundStyle(LiminalTheme.secondaryText)
                }
                .padding(.horizontal, 28)

                Button {
                    resetCrop()
                } label: {
                    Label("リセット", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .tint(LiminalTheme.accent)

                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LiminalTheme.canvasGradient.ignoresSafeArea())
            .navigationTitle("写真を調整")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") {
                        onCancel()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("適用") {
                        guard let data = croppedImageData() else { return }
                        onUse(data)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var cropSurface: some View {
        ZStack {
            ZStack {
                Circle()
                    .fill(LiminalTheme.elevated)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: displayedSize.width, height: displayedSize.height)
                    .scaleEffect(zoom)
                    .offset(offset)

                Circle()
                    .stroke(.white.opacity(0.76), lineWidth: 2)
            }
            .frame(width: cropDiameter, height: cropDiameter)
            .clipShape(Circle())
            .contentShape(Circle())
            .gesture(cropGesture)

            Circle()
                .stroke(LiminalTheme.divider.opacity(0.55), lineWidth: 1)
                .frame(width: cropDiameter, height: cropDiameter)

            if frameStyle.id != ProfileDecorationUnlocks.noIconFrameID {
                ProfileIconFrameView(style: frameStyle, accentColor: accentColor, size: frameDiameter)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: frameDiameter, height: frameDiameter)
        .contentShape(Circle())
        .shadow(color: accentColor.opacity(0.22), radius: 18, y: 8)
    }

    private var cropGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = clampedOffset(
                    CGSize(
                        width: committedOffset.width + value.translation.width,
                        height: committedOffset.height + value.translation.height
                    ),
                    zoom: zoom
                )
            }
            .onEnded { _ in
                offset = clampedOffset(offset, zoom: zoom)
                committedOffset = offset
            }
            .simultaneously(with:
                MagnificationGesture()
                    .onChanged { value in
                        zoom = clampedZoom(committedZoom * value)
                        offset = clampedOffset(offset, zoom: zoom)
                    }
                    .onEnded { _ in
                        zoom = clampedZoom(zoom)
                        offset = clampedOffset(offset, zoom: zoom)
                        committedZoom = zoom
                        committedOffset = offset
                    }
            )
    }

    private var zoomBinding: Binding<CGFloat> {
        Binding {
            zoom
        } set: { newValue in
            zoom = clampedZoom(newValue)
            offset = clampedOffset(offset, zoom: zoom)
            committedZoom = zoom
            committedOffset = offset
        }
    }

    private var displayedSize: CGSize {
        let baseScale = max(cropDiameter / image.size.width, cropDiameter / image.size.height)
        return CGSize(width: image.size.width * baseScale, height: image.size.height * baseScale)
    }

    private var transformedDisplayedSize: CGSize {
        CGSize(width: displayedSize.width * zoom, height: displayedSize.height * zoom)
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, minZoom), maxZoom)
    }

    private func clampedOffset(_ proposed: CGSize, zoom: CGFloat) -> CGSize {
        let size = CGSize(width: displayedSize.width * zoom, height: displayedSize.height * zoom)
        let maxX = max(0, (size.width - cropDiameter) / 2)
        let maxY = max(0, (size.height - cropDiameter) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func resetCrop() {
        withAnimation(.snappy(duration: 0.22)) {
            zoom = 1
            committedZoom = 1
            offset = .zero
            committedOffset = .zero
        }
    }

    private func croppedImageData() -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: outputSide, height: outputSide),
            format: format
        )
        let output = renderer.image { context in
            UIColor.systemBackground.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: outputSide, height: outputSide))

            let factor = outputSide / cropDiameter
            let size = transformedDisplayedSize
            let origin = CGPoint(
                x: (cropDiameter - size.width) / 2 + offset.width,
                y: (cropDiameter - size.height) / 2 + offset.height
            )
            let drawRect = CGRect(
                x: origin.x * factor,
                y: origin.y * factor,
                width: size.width * factor,
                height: size.height * factor
            )
            image.draw(in: drawRect)
        }
        return output.jpegData(compressionQuality: 0.86)
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
                        .fill(badge.isUnlocked ? tint.opacity(0.16) : LiminalTheme.elevated)
                    Image(systemName: badge.isUnlocked ? badge.systemImage : "lock.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(badge.isUnlocked ? tint : LiminalTheme.secondaryText)
                }
                .frame(width: 44, height: 44)

                Text(badge.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 74)
            .padding(.vertical, 8)
            .background(LiminalTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                ForEach(ProfileIconFrameCatalog.visibleItems) { item in
                    let isUnlocked = unlockedIDs.contains(item.id)
                    Button {
                        guard isUnlocked else { return }
                        selectedID = item.id
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                if item.id == ProfileDecorationUnlocks.noIconFrameID {
                                    Image(systemName: item.systemImage)
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(LiminalTheme.secondaryText)
                                        .frame(width: 44, height: 44)
                                        .background(LiminalTheme.elevated, in: Circle())
                                } else {
                                    ProfileIconFrameView(style: item, accentColor: accentColor, size: 44)
                                }
                                if !isUnlocked {
                                    Image(systemName: "lock.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(LiminalTheme.secondaryText)
                                        .padding(5)
                                        .background(LiminalTheme.surface, in: Circle())
                                }
                            }
                            .frame(width: 48, height: 48)
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10)
                        .background(LiminalTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                ForEach(ProfileStreakIconCatalog.equippableItems) { item in
                    let isUnlocked = unlockedIDs.contains(item.id)
                    Button {
                        guard isUnlocked else { return }
                        selectedID = item.id
                    } label: {
                        VStack(spacing: 7) {
                            ZStack {
                                Image(systemName: isUnlocked ? item.systemImage : "lock.fill")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(isUnlocked ? Color(hex: item.tintHex) : LiminalTheme.secondaryText)
                                    .frame(width: 44, height: 44)
                                    .background((isUnlocked ? Color(hex: item.tintHex) : LiminalTheme.secondaryText).opacity(0.14), in: Circle())
                            }
                            Text(item.title)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(LiminalTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                ForEach(ProfileCardStyleCatalog.visibleItems) { item in
                    let isUnlocked = unlockedIDs.contains(item.id)
                    Button {
                        guard isUnlocked else { return }
                        selectedID = item.id
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(item.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                if selectedID == item.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(item.markColor(accentColor: accentColor))
                                } else if !isUnlocked {
                                    Image(systemName: "lock.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(LiminalTheme.secondaryText)
                                }
                            }

                            ProfileCardStylePreview(style: item, accentColor: accentColor)
                        }
                        .padding(10)
                        .background(item.backgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(selectedID == item.id ? item.borderColor(accentColor: accentColor) : LiminalTheme.divider.opacity(0.45), lineWidth: selectedID == item.id ? 2 : 1)
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
        ProfileMiniCardStyleView(style: style, accentColor: accentColor)
            .frame(height: 48)
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
