import SwiftUI
import UIKit

struct ProfileBadgeModel: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: String
    let isUnlocked: Bool
    let progressText: String
}

enum ProfileBadgeCatalog {
    static let defaultBadge = ProfileBadgeModel(
        id: ProfileDecorationUnlocks.defaultNameBadgeID,
        title: "ルーキー",
        systemImage: "person.crop.circle.fill.badge.checkmark",
        tint: "#2F80ED",
        isUnlocked: true,
        progressText: "初期"
    )

    static func items(metrics: UnlockMetrics, unlockItems: [UnlockItem]) -> [ProfileBadgeModel] {
        let unlockedIDs = ProfileDecorationUnlocks(unlockItems: unlockItems).nameBadgeIDs
        let unlockBadges = unlockItems
            .filter { $0.kind == .nameBadge }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.key < $1.key
                }
                return $0.sortOrder < $1.sortOrder
            }
            .map { item in
                ProfileBadgeModel(
                    id: item.targetID,
                    title: item.displayName,
                    systemImage: item.systemImageName,
                    tint: item.tintHex,
                    isUnlocked: unlockedIDs.contains(item.targetID),
                    progressText: progressText(metrics: metrics, item: item)
                )
            }
        return [defaultBadge] + unlockBadges
    }

    static func equippedBadge(id: String?, badges: [ProfileBadgeModel]) -> ProfileBadgeModel {
        if let id, let selected = badges.first(where: { $0.id == id && $0.isUnlocked }) {
            return selected
        }
        if let unlocked = badges.first(where: \.isUnlocked) {
            return unlocked
        }
        return badges.first ?? defaultBadge
    }

    private static func progressText(metrics: UnlockMetrics, item: UnlockItem) -> String {
        if item.unlockedAt != nil {
            return "達成"
        }
        guard item.requiredValue > 0 else { return "0%" }
        let percent = Int((UnlockRules.progress(metrics: metrics, toward: item) * 100).rounded(.down))
        return "\(percent)%"
    }
}

struct ProfileIconFrameStyle: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let primaryHex: String
    let secondaryHex: String
    let lineWidth: CGFloat

    var primaryColor: Color { Color(hex: primaryHex) }
    var secondaryColor: Color { Color(hex: secondaryHex) }
}

enum ProfileIconFrameCatalog {
    static let defaultID = "halo"
    static let items: [ProfileIconFrameStyle] = [
        ProfileIconFrameStyle(id: "halo", title: "Halo", systemImage: "circle", primaryHex: "#2F80ED", secondaryHex: "#8AB4FF", lineWidth: 3),
        ProfileIconFrameStyle(id: "signal", title: "Signal", systemImage: "dot.radiowaves.left.and.right", primaryHex: "#00A8A8", secondaryHex: "#F2994A", lineWidth: 4),
        ProfileIconFrameStyle(id: "crown", title: "Crown", systemImage: "crown.fill", primaryHex: "#F2C94C", secondaryHex: "#6C5CE7", lineWidth: 3),
        ProfileIconFrameStyle(id: "focus", title: "Focus", systemImage: "scope", primaryHex: "#EB5757", secondaryHex: "#27AE60", lineWidth: 3)
    ]

    static func item(for id: String?) -> ProfileIconFrameStyle {
        items.first { $0.id == id } ?? items[0]
    }
}

struct ProfileStreakIconStyle: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tintHex: String
}

enum ProfileStreakIconCatalog {
    static let defaultID = "flame"
    static let items: [ProfileStreakIconStyle] = [
        ProfileStreakIconStyle(id: "flame", title: "赤い炎", systemImage: "flame.fill", tintHex: "#EB5757"),
        ProfileStreakIconStyle(id: "bolt", title: "金の炎", systemImage: "flame.fill", tintHex: "#F2C94C"),
        ProfileStreakIconStyle(id: "sun", title: "橙の炎", systemImage: "flame.fill", tintHex: "#F2994A"),
        ProfileStreakIconStyle(id: "spark", title: "紫の炎", systemImage: "flame.fill", tintHex: "#6C5CE7")
    ]

    static func item(for id: String?) -> ProfileStreakIconStyle {
        items.first { $0.id == id } ?? items[0]
    }
}

@MainActor
struct ProfileCardStyle: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let lightBackgroundHex: String
    let darkBackgroundHex: String
    let markHex: String?
    let stripOpacity: Double
    let borderWidth: CGFloat

    var backgroundColor: Color {
        Color(
            UIColor { traits in
                UIColor(liminalHex: traits.userInterfaceStyle == .light ? lightBackgroundHex : darkBackgroundHex)
            }
        )
    }

    var textColor: Color {
        Color(
            UIColor { traits in
                UIColor(liminalHex: traits.userInterfaceStyle == .light ? "#2A2440" : "#ECE8F5")
            }
        )
    }

    var secondaryTextColor: Color {
        Color(
            UIColor { traits in
                UIColor(liminalHex: traits.userInterfaceStyle == .light ? "#6A6388" : "#C8C1DA")
            }
        )
    }

    func markColor(accentColor: Color) -> Color {
        markHex.map(Color.init(hex:)) ?? accentColor
    }

    func stripColor(accentColor: Color) -> Color {
        markColor(accentColor: accentColor).opacity(stripOpacity)
    }

    func borderColor(accentColor: Color) -> Color {
        markColor(accentColor: accentColor).opacity(borderWidth > 1 ? 0.55 : 0.18)
    }
}

enum ProfileCardStyleCatalog {
    static let defaultID = "clean"
    static let items: [ProfileCardStyle] = [
        ProfileCardStyle(id: "clean", title: "Clean", systemImage: "rectangle", lightBackgroundHex: "#FFFFFF", darkBackgroundHex: "#1F1A38", markHex: nil, stripOpacity: 0.35, borderWidth: 1),
        ProfileCardStyle(id: "glass", title: "Glass", systemImage: "sparkle.magnifyingglass", lightBackgroundHex: "#F7FBFF", darkBackgroundHex: "#221B3A", markHex: "#2F80ED", stripOpacity: 0.38, borderWidth: 1),
        ProfileCardStyle(id: "dawn", title: "Dawn", systemImage: "sunrise.fill", lightBackgroundHex: "#FFF8F0", darkBackgroundHex: "#2A2032", markHex: "#F2994A", stripOpacity: 0.42, borderWidth: 1),
        ProfileCardStyle(id: "mint", title: "Mint", systemImage: "leaf.fill", lightBackgroundHex: "#F2FBF6", darkBackgroundHex: "#18312B", markHex: "#27AE60", stripOpacity: 0.38, borderWidth: 1)
    ]

    static func item(for id: String?) -> ProfileCardStyle {
        items.first { $0.id == id } ?? items[0]
    }
}

enum ProfileFormat {
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
