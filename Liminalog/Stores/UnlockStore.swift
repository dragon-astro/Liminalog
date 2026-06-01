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
        var items = fetchItems()
        var didChange = false

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
            try? modelContext.save()
        }
        return fetchItems()
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
        try? modelContext.save()
        return newlyUnlocked
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
        let descriptor = FetchDescriptor<UnlockItem>(
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt)
            ]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
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
