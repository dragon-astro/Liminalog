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
    @FocusState private var focusedField: ProfileEditField?

    private enum ProfileEditField: Hashable {
        case displayName
        case bio
    }

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
    private let userID: String?

    init(
        settings: UserSettings?,
        badges: [ProfileBadgeModel],
        unlocks: ProfileDecorationUnlocks,
        onSave: @escaping (ProfileDraft) -> Bool
    ) {
        _displayName = State(initialValue: ProfileDisplayNamePolicy.limited(settings?.profileDisplayName ?? ""))
        _bio = State(initialValue: settings?.profileBio ?? "")
        _imageData = State(initialValue: settings?.profileImageData)
        _badgeID = State(initialValue: ProfileBadgeCatalog.equippedBadge(id: settings?.profileBadgeID, badges: badges).id)
        _iconFrameID = State(initialValue: unlocks.equippedIconFrameID(settings: settings))
        _streakIconID = State(initialValue: unlocks.equippedStreakIconID(settings?.profileStreakIconID))
        _cardStyleID = State(initialValue: unlocks.equippedCardStyleID(settings?.profileCardStyleID))
        let normalizedUserID = settings?.cloudUsernameNormalized.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawUserID = settings?.cloudUsername.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.userID = normalizedUserID.isEmpty ? (rawUserID.isEmpty ? nil : rawUserID) : normalizedUserID
        self.badges = badges
        self.unlocks = unlocks
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                previewHeader

                categoryTabBar

                ScrollViewReader { formProxy in
                    Form {
                        switch activeTab {
                        case .basics:
                            basicsContent
                        case .badge:
                            Section {
                                ProfileBadgeSelector(badges: badges, selectedID: $badgeID)
                            }
                            .listRowBackground(LiminalTheme.surface)
                        case .frame:
                            Section {
                                ProfileFrameSelector(
                                    selectedID: $iconFrameID,
                                    accentColor: visualAccentColor,
                                    unlockedIDs: unlocks.iconFrameIDs
                                )
                            }
                            .listRowBackground(LiminalTheme.surface)
                        case .streak:
                            Section {
                                ProfileStreakIconSelector(
                                    selectedID: $streakIconID,
                                    unlockedIDs: unlocks.streakIconIDs
                                )
                            }
                            .listRowBackground(LiminalTheme.surface)
                        case .card:
                            Section {
                                ProfileCardStyleSelector(
                                    selectedID: $cardStyleID,
                                    accentColor: visualAccentColor,
                                    unlockedIDs: unlocks.cardStyleIDs
                                )
                            }
                            .listRowBackground(LiminalTheme.surface)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .contentMargins(.top, 10, for: .scrollContent)
                    .contentMargins(.bottom, isEditingText ? 22 : 0, for: .scrollContent)
                    .scrollDismissesKeyboard(.interactively)
                    .background(LiminalTheme.canvasGradient)
                    .onChange(of: focusedField) { _, field in
                        scrollFocusedFieldIntoView(field, proxy: formProxy)
                    }
                }
            }
            .background(LiminalTheme.canvasGradient.ignoresSafeArea())
            .navigationTitle("プロフィール編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LiminalTheme.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        focusedField = nil
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

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") {
                        focusedField = nil
                    }
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: selectedPhoto) { _, newPhoto in
                Task {
                    await loadPhoto(newPhoto)
                }
            }
            .onChange(of: displayName) { _, newValue in
                let limitedName = ProfileDisplayNamePolicy.limited(newValue)
                if limitedName != newValue {
                    displayName = limitedName
                }
            }
            .onChange(of: activeTab) { _, newTab in
                if newTab != .basics {
                    focusedField = nil
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

    private var categoryTabBar: some View {
        Picker("", selection: $activeTab) {
            ForEach(EditTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(LiminalTheme.canvasGradient)
    }

    private var isEditingText: Bool {
        focusedField != nil
    }

    private var previewHeader: some View {
        Group {
            if isEditingText {
                compactPreviewHeader
            } else {
                expandedPreviewHeader
            }
        }
        .background(LiminalTheme.canvasGradient)
        .animation(.snappy(duration: 0.2), value: isEditingText)
    }

    private var expandedPreviewHeader: some View {
        VStack(spacing: 0) {
            editProfileHeroPreview

            streakChip
        }
        .padding(.horizontal, 16)
        .padding(.top, expandedPreviewTopPadding)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
    }

    private var expandedPreviewTopPadding: CGFloat {
        resolvedCardStyle.hasGeneratedArtwork ? 26 : 10
    }

    private var editProfileHeroPreview: some View {
        ProfileHero(
            displayName: previewDisplayName,
            userID: userID,
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
        .scaleEffect(editProfileHeroPreviewScale, anchor: .top)
        .frame(height: editProfileHeroPreviewHeight, alignment: .top)
        .animation(.snappy(duration: 0.28), value: previewSignature)
        .padding(.bottom, resolvedCardStyle.hasGeneratedArtwork ? -10 : 0)
    }

    private var editProfileHeroPreviewScale: CGFloat {
        0.92
    }

    private var editProfileHeroPreviewHeight: CGFloat {
        resolvedCardStyle.hasGeneratedArtwork ? 212 : 182
    }

    private var compactPreviewHeader: some View {
        HStack(spacing: 10) {
            ProfileMiniCardStyleView(style: resolvedCardStyle, accentColor: visualAccentColor)
                .frame(width: 86, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text(previewDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LiminalTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                streakChip
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
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
        .listRowBackground(LiminalTheme.surface)

        Section("プロフィール") {
            TextField("名前", text: $displayName)
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .displayName)
                .accessibilityHint("全角6文字、半角12文字まで入力できます")
                .id(ProfileEditField.displayName)

            TextField("いまの気分をひとこと", text: $bio, axis: .vertical)
                .lineLimit(3...5)
                .focused($focusedField, equals: .bio)
                .id(ProfileEditField.bio)
        }
        .listRowBackground(LiminalTheme.surface)
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
        ProfileDisplayNamePolicy.limited(displayName.trimmingCharacters(in: .whitespacesAndNewlines))
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

    private func scrollFocusedFieldIntoView(_ field: ProfileEditField?, proxy: ScrollViewProxy) {
        guard let field else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            withAnimation(.snappy(duration: 0.22)) {
                proxy.scrollTo(field, anchor: .center)
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

    private let columns = Array(repeating: GridItem(.flexible(minimum: 84), spacing: 10), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("バッジ")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(badges) { badge in
                    ProfileSelectableBadge(badge: badge, isSelected: selectedID == badge.id) {
                        guard badge.isUnlocked else { return }
                        selectedID = badge.id
                    }
                }
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
            .frame(maxWidth: .infinity, minHeight: 92)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(LiminalTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? tint : LiminalTheme.divider.opacity(0.45), lineWidth: isSelected ? 2 : 1)
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
    @State private var rankPickerGroup: ProfileFrameChoiceGroup?

    private let columns = Array(repeating: GridItem(.flexible(minimum: 84), spacing: 10), count: 3)

    private var groups: [ProfileFrameChoiceGroup] {
        ProfileFrameChoiceGroup.groups(from: ProfileIconFrameCatalog.visibleItems)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("アイコンフレーム")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(groups) { group in
                    let isUnlocked = group.isUnlocked(unlockedIDs: unlockedIDs)
                    Button {
                        guard isUnlocked else { return }
                        if group.items.count == 1, let item = group.items.first {
                            selectedID = item.id
                        } else {
                            rankPickerGroup = group
                        }
                    } label: {
                        ProfileFrameGroupTile(
                            group: group,
                            selectedID: selectedID,
                            accentColor: accentColor,
                            unlockedIDs: unlockedIDs
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isUnlocked)
                    .opacity(isUnlocked ? 1 : 0.5)
                    .accessibilityLabel(group.accessibilityLabel(selectedID: selectedID, unlockedIDs: unlockedIDs))
                }
            }
        }
        .padding(.vertical, 4)
        .sheet(item: $rankPickerGroup) { group in
            ProfileFrameRankPickerSheet(
                group: group,
                selectedID: selectedID,
                unlockedIDs: unlockedIDs
            ) { item in
                selectedID = item.id
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(LiminalTheme.canvasGradient)
        }
    }
}

private struct ProfileFrameChoiceGroup: Identifiable {
    let id: String
    let title: String
    let items: [ProfileIconFrameStyle]

    static func groups(from items: [ProfileIconFrameStyle]) -> [ProfileFrameChoiceGroup] {
        var groups: [ProfileFrameChoiceGroup] = []
        let earnedItems = items.filter { $0.id.hasPrefix("free_instrument_") }
        let earnedFamilies = Dictionary(grouping: earnedItems, by: earnedFamilyID)

        for item in items where !item.id.hasPrefix("free_instrument_") {
            groups.append(ProfileFrameChoiceGroup(id: item.id, title: item.title, items: [item]))
        }

        for familyID in ["standard", "seal", "orbit", "crest"] {
            guard let familyItems = earnedFamilies[familyID] else { continue }
            groups.append(
                ProfileFrameChoiceGroup(
                    id: "earned-\(familyID)",
                    title: earnedFamilyTitle(familyID),
                    items: familyItems.sorted(by: earnedRankSort)
                )
            )
        }

        return groups
    }

    func isUnlocked(unlockedIDs: Set<String>) -> Bool {
        items.contains { unlockedIDs.contains($0.id) }
    }

    func isSelected(_ selectedID: String) -> Bool {
        items.contains { $0.id == selectedID }
    }

    func representativeItem(selectedID: String, unlockedIDs: Set<String>) -> ProfileIconFrameStyle {
        if let selected = items.first(where: { $0.id == selectedID }) {
            return selected
        }
        if let unlocked = items.reversed().first(where: { unlockedIDs.contains($0.id) }) {
            return unlocked
        }
        return items.last ?? ProfileIconFrameCatalog.defaultItem
    }

    func accessibilityLabel(selectedID: String, unlockedIDs: Set<String>) -> String {
        var parts = [title]
        if isSelected(selectedID) {
            parts.append("選択中")
        }
        if !isUnlocked(unlockedIDs: unlockedIDs) {
            parts.append("未解放")
        } else if items.count > 1 {
            parts.append("ランクを選択")
        }
        return parts.joined(separator: "、")
    }

    nonisolated private static func earnedFamilyID(_ item: ProfileIconFrameStyle) -> String {
        let suffix = item.id.replacingOccurrences(of: "free_instrument_", with: "")
        if suffix.hasSuffix("_seal") { return "seal" }
        if suffix.hasSuffix("_orbit") { return "orbit" }
        if suffix.hasSuffix("_crest") { return "crest" }
        return "standard"
    }

    private static func earnedFamilyTitle(_ id: String) -> String {
        switch id {
        case "seal": return "印"
        case "orbit": return "軌"
        case "crest": return "冠"
        default: return "標"
        }
    }

    nonisolated private static func earnedRankSort(_ lhs: ProfileIconFrameStyle, _ rhs: ProfileIconFrameStyle) -> Bool {
        earnedRankValue(lhs.id) < earnedRankValue(rhs.id)
    }

    nonisolated static func earnedRankLabel(for item: ProfileIconFrameStyle) -> String {
        if item.id.contains("platinum") { return "白金" }
        if item.id.contains("gold") { return "金" }
        if item.id.contains("silver") { return "銀" }
        if item.id.contains("bronze") { return "銅" }
        if item.id.contains("iron") { return "鉄" }
        return item.title
    }

    nonisolated private static func earnedRankValue(_ id: String) -> Int {
        if id.contains("iron") { return 0 }
        if id.contains("bronze") { return 1 }
        if id.contains("silver") { return 2 }
        if id.contains("gold") { return 3 }
        if id.contains("platinum") { return 4 }
        return 99
    }
}

private struct ProfileFrameGroupTile: View {
    let group: ProfileFrameChoiceGroup
    let selectedID: String
    let accentColor: Color
    let unlockedIDs: Set<String>

    private var item: ProfileIconFrameStyle {
        group.representativeItem(selectedID: selectedID, unlockedIDs: unlockedIDs)
    }

    private var isSelected: Bool {
        group.isSelected(selectedID)
    }

    private var isUnlocked: Bool {
        group.isUnlocked(unlockedIDs: unlockedIDs)
    }

    var body: some View {
        GeometryReader { proxy in
            let iconSize = min(max(proxy.size.width * 0.72, 56), 96)
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

            ZStack {
                shape
                    .fill(LiminalTheme.surface)
                    .overlay(shape.fill(item.primaryColor.opacity(isSelected ? 0.14 : 0.05)))

                framePreview(size: iconSize)

                if group.items.count > 1 && isUnlocked {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(item.primaryColor)
                        .padding(6)
                        .background(LiminalTheme.elevated, in: Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(7)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(item.primaryColor)
                        .padding(6)
                        .background(LiminalTheme.elevated, in: Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(7)
                } else if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(LiminalTheme.secondaryText)
                        .padding(7)
                        .background(LiminalTheme.elevated, in: Circle())
                }
            }
            .overlay {
                shape.stroke(isSelected ? item.primaryColor : LiminalTheme.divider.opacity(0.45), lineWidth: isSelected ? 2 : 1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func framePreview(size: CGFloat) -> some View {
        if item.id == ProfileDecorationUnlocks.noIconFrameID {
            Image(systemName: item.systemImage)
                .font(.title2.weight(.bold))
                .foregroundStyle(LiminalTheme.secondaryText)
                .frame(width: size, height: size)
                .background(LiminalTheme.elevated, in: Circle())
        } else {
            ProfileIconFrameView(style: item, accentColor: item.primaryColor, size: size)
                .shadow(color: item.primaryColor.opacity(0.2), radius: 10, y: 5)
        }
    }
}

private struct ProfileFrameRankPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let group: ProfileFrameChoiceGroup
    let selectedID: String
    let unlockedIDs: Set<String>
    let onSelect: (ProfileIconFrameStyle) -> Void

    private let columns = Array(repeating: GridItem(.flexible(minimum: 86), spacing: 10), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(group.items) { item in
                        let isUnlocked = unlockedIDs.contains(item.id)
                        Button {
                            guard isUnlocked else { return }
                            onSelect(item)
                            dismiss()
                        } label: {
                            ProfileFrameRankTile(
                                item: item,
                                isSelected: selectedID == item.id,
                                isUnlocked: isUnlocked
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!isUnlocked)
                        .opacity(isUnlocked ? 1 : 0.5)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(LiminalTheme.canvasGradient.ignoresSafeArea())
            .navigationTitle("\(group.title)のランク")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LiminalTheme.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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

private struct ProfileFrameRankTile: View {
    let item: ProfileIconFrameStyle
    let isSelected: Bool
    let isUnlocked: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ProfileIconFrameView(style: item, accentColor: item.primaryColor, size: 76)

                if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LiminalTheme.secondaryText)
                        .padding(6)
                        .background(LiminalTheme.elevated, in: Circle())
                }
            }
            .frame(width: 86, height: 86)

            Text(ProfileFrameChoiceGroup.earnedRankLabel(for: item))
                .font(.caption.weight(.semibold))
                .foregroundStyle(LiminalTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(LiminalTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? item.primaryColor : LiminalTheme.divider.opacity(0.45), lineWidth: isSelected ? 2 : 1)
        }
    }
}

private struct ProfileStreakIconSelector: View {
    @Binding var selectedID: String
    let unlockedIDs: Set<String>

    private let columns = Array(repeating: GridItem(.flexible(minimum: 84), spacing: 10), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ストリーク")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: columns, spacing: 10) {
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
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: 92)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                        .background(LiminalTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(selectedID == item.id ? Color(hex: item.tintHex) : LiminalTheme.divider.opacity(0.45), lineWidth: selectedID == item.id ? 2 : 1)
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
                        .frame(minHeight: 116, alignment: .topLeading)
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
            .frame(maxWidth: .infinity)
            .frame(height: cardBaseHeight)
            .scaleEffect(cardScale, anchor: .center)
            .padding(.horizontal, previewHorizontalInset)
            .frame(maxWidth: .infinity)
            .frame(height: previewFrameHeight)
    }

    private var cardBaseHeight: CGFloat {
        style.hasGeneratedArtwork ? 46 : 48
    }

    private var cardScale: CGFloat {
        style.hasGeneratedArtwork ? 0.84 : 0.90
    }

    private var previewFrameHeight: CGFloat {
        style.hasGeneratedArtwork ? 60 : 56
    }

    private var previewHorizontalInset: CGFloat {
        style.hasGeneratedArtwork ? 10 : 8
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
