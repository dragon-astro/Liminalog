import Foundation
import SwiftData

@Model
final class CategorySet {
    var id: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0
    /// 8スロット固定。`nil` は空きスロット。スロット位置 = 配列 index (0..<8) で、Home の 4列×2行グリッド左上から右下へ対応。
    var slots: [UUID?] = Array<UUID?>(repeating: nil, count: 8)
    var isDefault: Bool = false
    var createdAt: Date = Date()

    static let slotCount = 8

    init() {}

    init(name: String, sortOrder: Int = 0, slots: [UUID?] = Array<UUID?>(repeating: nil, count: 8), isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.slots = Self.normalize(slots)
        self.isDefault = isDefault
        self.createdAt = Date()
    }

    /// 配列を必ず長さ `slotCount` に揃える（短ければ nil でパディング、長ければ切り詰め）
    static func normalize(_ slots: [UUID?]) -> [UUID?] {
        var result = Array(slots.prefix(slotCount))
        while result.count < slotCount { result.append(nil) }
        return result
    }

    /// nil を除いた割り当て済みカテゴリIDの配列（順序は保持）
    var assignedIDs: [UUID] { slots.compactMap { $0 } }

    /// 割り当て済みスロット数
    var filledCount: Int { assignedIDs.count }
}
