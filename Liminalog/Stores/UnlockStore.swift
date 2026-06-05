import Foundation
import SwiftData

@MainActor
final class UnlockStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func seedMasterItems(now: Date = Date()) -> [UnlockItem] {
        guard var items = fetchItemsIfAvailable() else {
            NSLog("Liminalog: skipped unlock master seed because unlock items could not be fetched")
            return []
        }
        var didChange = false

        if migrateLegacyBuiltInItems(in: &items, now: now) {
            didChange = true
        }

        if removeRetiredBuiltInItems(in: &items) {
            didChange = true
        }

        for seed in UnlockCatalog.items {
            if let existing = items.first(where: { $0.key == seed.key }) {
                if apply(seed, to: existing, now: now) {
                    didChange = true
                }
            } else {
                let item = UnlockItem(seed: seed, now: now)
                modelContext.insert(item)
                items.append(item)
                didChange = true
            }
        }

        if consolidateDuplicates(in: items, now: now) {
            didChange = true
        }

        if didChange {
            _ = saveChanges("unlock master items")
        }
        return fetchItemsIfAvailable() ?? items.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.createdAt < $1.createdAt
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    @discardableResult
    func refresh(cumulativeScore: Int, now: Date = Date()) -> [UnlockItem] {
        refresh(metrics: .score(cumulativeScore), now: now)
    }

    @discardableResult
    func refresh(metrics: UnlockMetrics, now: Date = Date()) -> [UnlockItem] {
        let items = seedMasterItems(now: now)
        let newlyUnlocked = UnlockRules.itemsToUnlock(
            metrics: metrics,
            items: items
        )

        guard !newlyUnlocked.isEmpty else { return [] }
        for item in newlyUnlocked {
            item.unlockedAt = now
            item.updatedAt = now
        }
        return saveChanges("unlock refresh") ? newlyUnlocked : []
    }

    func allItems() -> [UnlockItem] {
        seedMasterItems()
    }

    func nextLockedItem(cumulativeScore: Int) -> UnlockItem? {
        nextLockedItem(metrics: .score(cumulativeScore))
    }

    func nextLockedItem(metrics: UnlockMetrics) -> UnlockItem? {
        UnlockRules.nextLockedItem(
            metrics: metrics,
            items: allItems()
        )
    }

    private func fetchItems() -> [UnlockItem] {
        fetchItemsIfAvailable() ?? []
    }

    private func fetchItemsIfAvailable() -> [UnlockItem]? {
        let descriptor = FetchDescriptor<UnlockItem>(
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt)
            ]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            NSLog("Liminalog: failed to fetch unlock items: \(String(describing: error))")
            return nil
        }
    }

    @discardableResult
    private func saveChanges(_ action: String) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            NSLog("Liminalog: failed to save \(action): \(String(describing: error))")
            modelContext.rollback()
            return false
        }
    }

    @discardableResult
    private func apply(_ seed: UnlockCatalogItem, to item: UnlockItem, now: Date) -> Bool {
        var didChange = false

        func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<UnlockItem, Value>, to value: Value) {
            if item[keyPath: keyPath] != value {
                item[keyPath: keyPath] = value
                didChange = true
            }
        }

        update(\.kindRawValue, to: seed.kind.rawValue)
        update(\.requiredCumulativeScore, to: seed.requiredCumulativeScore)
        update(\.requirementKindRawValue, to: seed.requirementKind.rawValue)
        update(\.requiredValue, to: seed.requiredValue)
        update(\.displayName, to: seed.displayName)
        update(\.systemImageName, to: seed.systemImageName)
        update(\.tintHex, to: seed.tintHex)
        update(\.targetID, to: seed.targetID)
        update(\.sortOrder, to: seed.sortOrder)
        update(\.isBuiltIn, to: true)

        if didChange {
            item.updatedAt = now
        }
        return didChange
    }

    private func migrateLegacyBuiltInItems(in items: inout [UnlockItem], now: Date) -> Bool {
        var didChange = false
        let seedsByKey = Dictionary(uniqueKeysWithValues: UnlockCatalog.items.map { ($0.key, $0) })

        for item in items where item.isBuiltIn {
            guard
                let replacementKey = UnlockCatalog.legacyKeyReplacements[item.key],
                let replacementSeed = seedsByKey[replacementKey]
            else { continue }

            if let existing = items.first(where: { $0 !== item && $0.key == replacementKey }) {
                if existing.unlockedAt == nil || (item.unlockedAt.map { $0 < (existing.unlockedAt ?? $0) } ?? false) {
                    existing.unlockedAt = item.unlockedAt
                }
                if existing.thumbnailName == nil {
                    existing.thumbnailName = item.thumbnailName
                }
                existing.updatedAt = now
                modelContext.delete(item)
                didChange = true
            } else {
                item.key = replacementKey
                if apply(replacementSeed, to: item, now: now) {
                    didChange = true
                } else {
                    item.updatedAt = now
                    didChange = true
                }
            }
        }

        if didChange {
            if let refreshedItems = fetchItemsIfAvailable() {
                items = refreshedItems
            } else {
                NSLog("Liminalog: could not refresh unlock items after migration")
            }
        }
        return didChange
    }

    private func removeRetiredBuiltInItems(in items: inout [UnlockItem]) -> Bool {
        let currentKeys = Set(UnlockCatalog.items.map(\.key))
        var didChange = false

        for item in items where item.isBuiltIn && !currentKeys.contains(item.key) {
            modelContext.delete(item)
            didChange = true
        }

        if didChange {
            if let refreshedItems = fetchItemsIfAvailable() {
                items = refreshedItems
            } else {
                NSLog("Liminalog: could not refresh unlock items after retired decoration cleanup")
            }
        }
        return didChange
    }

    private func consolidateDuplicates(in items: [UnlockItem], now: Date) -> Bool {
        var didChange = false
        let groups = Dictionary(grouping: items.filter { !$0.key.isEmpty }) { $0.key }

        for group in groups.values where group.count > 1 {
            guard let primary = group.sorted(by: { $0.createdAt < $1.createdAt }).first else { continue }
            let earliestUnlock = group.compactMap(\.unlockedAt).min()

            for duplicate in group where duplicate !== primary {
                if primary.thumbnailName == nil {
                    primary.thumbnailName = duplicate.thumbnailName
                }
                modelContext.delete(duplicate)
                didChange = true
            }

            if primary.unlockedAt != earliestUnlock {
                primary.unlockedAt = earliestUnlock
                didChange = true
            }
            if didChange {
                primary.updatedAt = now
            }
        }

        return didChange
    }
}
