import SwiftUI
import UIKit

struct ProfileHero: View {
    let displayName: String
    let bio: String
    let imageData: Data?
    let accentColor: Color
    let equippedBadge: ProfileBadgeModel
    let iconFrame: ProfileIconFrameStyle
    let cardStyle: ProfileCardStyle
    let onEdit: () -> Void
    let onShare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                ProfilePhotoView(
                    displayName: displayName,
                    imageData: imageData,
                    accentColor: accentColor,
                    frameStyle: iconFrame,
                    size: 92
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(displayName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(cardStyle.textColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .padding(.trailing, 76)

                    EquippedBadgePill(badge: equippedBadge)

                    Text(bio.isEmpty ? "プロフィールを育てよう" : bio)
                        .font(.subheadline)
                        .foregroundStyle(cardStyle.secondaryTextColor)
                        .lineLimit(2)
                        .frame(minHeight: 42, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 28)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(cardStyle.backgroundColor)
                .overlay(alignment: .bottom) {
                    DecorativeAccentStrip(color: cardStyle.stripColor(accentColor: accentColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .overlay(alignment: .topTrailing) {
                    ProfileCardStyleMark(style: cardStyle, accentColor: accentColor)
                        .padding(16)
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 8) {
                        ProfileHeroActionButton(systemImage: "pencil", label: "編集", action: onEdit)
                        ProfileHeroActionButton(systemImage: "square.and.arrow.up", label: "シェア", action: onShare)
                    }
                    .padding(.top, 18)
                    .padding(.trailing, 18)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(cardStyle.borderColor(accentColor: accentColor), lineWidth: cardStyle.borderWidth)
        }
    }
}

struct ProfileCardStyleMark: View {
    let style: ProfileCardStyle
    let accentColor: Color

    var body: some View {
        Image(systemName: style.systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(style.markColor(accentColor: accentColor))
            .frame(width: 24, height: 24)
            .background(.ultraThinMaterial, in: Circle())
            .opacity(style.id == ProfileCardStyleCatalog.defaultID ? 0 : 1)
    }
}

private struct ProfileHeroActionButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .frame(width: 30, height: 30)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct EquippedBadgePill: View {
    let badge: ProfileBadgeModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: badge.systemImage)
                .font(.caption2.weight(.bold))
            Text(badge.title)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(Color(hex: badge.tint))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color(hex: badge.tint).opacity(0.12), in: Capsule())
        .lineLimit(1)
    }
}

struct ProfilePhotoView: View {
    let displayName: String
    let imageData: Data?
    let accentColor: Color
    let frameStyle: ProfileIconFrameStyle
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(accentColor.gradient)
                .frame(width: size, height: size)

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

            ProfileIconFrameView(style: frameStyle, accentColor: accentColor, size: size + 16)
        }
        .frame(width: size + 16, height: size + 16)
        .overlay {
            Circle()
                .stroke(.white.opacity(0.75), lineWidth: 2)
                .frame(width: size, height: size)
        }
        .shadow(color: accentColor.opacity(0.2), radius: 14, y: 6)
    }

    private var initial: String {
        String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }
}

struct ProfileIconFrameView: View {
    let style: ProfileIconFrameStyle
    let accentColor: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(style.secondaryColor.opacity(0.24), lineWidth: style.lineWidth + 4)

            switch style.id {
            case "signal":
                Circle()
                    .trim(from: 0.06, to: 0.38)
                    .stroke(style.primaryColor, style: StrokeStyle(lineWidth: style.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-28))
                Circle()
                    .trim(from: 0.56, to: 0.86)
                    .stroke(style.secondaryColor, style: StrokeStyle(lineWidth: style.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-28))
            case "crown":
                Circle()
                    .stroke(style.primaryColor.opacity(0.9), style: StrokeStyle(lineWidth: style.lineWidth, lineCap: .round, dash: [10, 5]))
                Image(systemName: "crown.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(style.primaryColor)
                    .padding(6)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())
                    .offset(x: size * 0.28, y: -size * 0.28)
            case "focus":
                Circle()
                    .stroke(style.primaryColor, lineWidth: style.lineWidth)
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(style.secondaryColor)
                        .frame(width: 4, height: 12)
                        .offset(y: -size * 0.47)
                        .rotationEffect(.degrees(Double(index) * 90))
                }
            default:
                Circle()
                    .stroke(style.primaryColor, lineWidth: style.lineWidth)
            }
        }
        .frame(width: size, height: size)
    }
}

struct ProfileStatsRow: View {
    let streak: Int
    let totalScore: Int
    let friendCount: Int
    let streakIcon: ProfileStreakIconStyle

    var body: some View {
        HStack(spacing: 10) {
            ProfileStatTile(title: "ストリーク", value: "\(streak)日", systemImage: streakIcon.systemImage, tint: Color(hex: streakIcon.tintHex))
            ProfileStatTile(title: "累計スコア", value: "\(totalScore)pt", systemImage: "star.fill", tint: Color(hex: "#F2994A"))
            ProfileStatTile(title: "友達", value: "\(friendCount)人", systemImage: "person.2.fill", tint: Color(hex: "#27AE60"))
        }
    }
}

struct ProfileStatTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(alignment: .topTrailing) {
            tint.opacity(0.18)
                .frame(width: 26, height: 4)
                .clipShape(Capsule())
                .padding(10)
        }
    }
}

struct ProfileNextUnlockSection: View {
    let targets: [ProfileUnlockTarget]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("次の解放")
                .font(.headline)

            if targets.isEmpty {
                ProfileAllUnlockedCard()
            } else {
                VStack(spacing: 10) {
                    ForEach(targets) { target in
                        ProfileUnlockTargetRow(target: target)
                    }
                }
            }
        }
    }
}

private struct ProfileUnlockTargetRow: View {
    let target: ProfileUnlockTarget

    private var tint: Color {
        Color(hex: target.tintHex)
    }

    private var progressLabel: String {
        "\(target.progressPercent)%"
    }

    private var remainingLabel: String {
        target.remainingText
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                Image(systemName: target.systemImageName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(target.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(target.kindTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.12), in: Capsule())
                }

                ProgressView(value: target.progress)
                    .tint(tint)

                HStack {
                    Text(remainingLabel)
                    Spacer(minLength: 8)
                    Text(progressLabel)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ProfileAllUnlockedCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color(hex: "#27AE60"))
                .frame(width: 42, height: 42)
                .background(Color(hex: "#27AE60").opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("全解放済み")
                    .font(.subheadline.weight(.semibold))
                Text("今の装備を磨ける状態")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ProfileCollectionSection: View {
    let badges: [ProfileBadgeModel]
    let equippedBadge: ProfileBadgeModel
    let iconFrame: ProfileIconFrameStyle
    let streakIcon: ProfileStreakIconStyle
    let cardStyle: ProfileCardStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("装備とコレクション")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ProfileEquipmentTile(title: "バッジ", value: equippedBadge.title, systemImage: equippedBadge.systemImage, tint: Color(hex: equippedBadge.tint))
                ProfileEquipmentFrameTile(title: "フレーム", value: iconFrame.title, frameStyle: iconFrame)
                ProfileEquipmentCardStyleTile(title: "カード", value: cardStyle.title, cardStyle: cardStyle, accentColor: iconFrame.primaryColor)
                ProfileEquipmentTile(title: "連続", value: streakIcon.title, systemImage: streakIcon.systemImage, tint: Color(hex: streakIcon.tintHex))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(badges) { badge in
                        ProfileCollectionBadge(badge: badge, isEquipped: badge.id == equippedBadge.id)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct ProfileCollectionBadge: View {
    let badge: ProfileBadgeModel
    let isEquipped: Bool

    private var tint: Color {
        Color(hex: badge.tint)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(badge.isUnlocked ? tint.opacity(0.18) : Color(.secondarySystemGroupedBackground))
                Circle()
                    .stroke(
                        isEquipped ? tint : (badge.isUnlocked ? tint.opacity(0.65) : Color(.separator).opacity(0.4)),
                        lineWidth: isEquipped ? 2 : 1
                    )
                Image(systemName: badge.isUnlocked ? badge.systemImage : "lock.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(badge.isUnlocked ? tint : Color.secondary)
            }
            .frame(width: 62, height: 62)
            .overlay(alignment: .bottomTrailing) {
                if isEquipped {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                        .background(Color(.secondarySystemGroupedBackground), in: Circle())
                }
            }

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

struct ProfileEquipmentTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        ProfileEquipmentTileShell(title: title, value: value) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
                .frame(height: 20)
        }
    }
}

struct ProfileEquipmentFrameTile: View {
    let title: String
    let value: String
    let frameStyle: ProfileIconFrameStyle

    var body: some View {
        ProfileEquipmentTileShell(title: title, value: value) {
            ZStack {
                Circle()
                    .fill(frameStyle.primaryColor.opacity(0.14))
                    .frame(width: 22, height: 22)

                ProfileIconFrameView(style: frameStyle, accentColor: frameStyle.primaryColor, size: 28)
            }
            .frame(width: 32, height: 24, alignment: .leading)
        }
    }
}

struct ProfileEquipmentCardStyleTile: View {
    let title: String
    let value: String
    let cardStyle: ProfileCardStyle
    let accentColor: Color

    var body: some View {
        ProfileEquipmentTileShell(title: title, value: value) {
            ProfileMiniCardStyleView(style: cardStyle, accentColor: accentColor)
                .frame(width: 42, height: 24)
        }
    }
}

struct ProfileEquipmentTileShell<Preview: View>: View {
    let title: String
    let value: String
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            preview()
                .frame(height: 24, alignment: .leading)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .frame(minHeight: 78, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ProfileMiniCardStyleView: View {
    let style: ProfileCardStyle
    let accentColor: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(style.backgroundColor)
            .overlay(alignment: .bottom) {
                DecorativeAccentStrip(color: style.stripColor(accentColor: accentColor), height: 7)
            }
            .overlay(alignment: .topTrailing) {
                ProfileCardStyleMark(style: style, accentColor: accentColor)
                    .scaleEffect(0.48)
                    .frame(width: 12, height: 12)
                    .padding(3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(style.borderColor(accentColor: accentColor), lineWidth: max(1, style.borderWidth))
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
