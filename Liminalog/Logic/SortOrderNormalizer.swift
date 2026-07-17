import Foundation

enum SortOrderNormalizer {
    @discardableResult
    static func normalize<Element: AnyObject>(
        _ items: [Element],
        sortOrder keyPath: ReferenceWritableKeyPath<Element, Int>
    ) -> Bool {
        var didChange = false
        for (index, item) in items.enumerated() where item[keyPath: keyPath] != index {
            item[keyPath: keyPath] = index
            didChange = true
        }
        return didChange
    }

    @discardableResult
    static func reorder<Element: AnyObject>(
        _ items: [Element],
        from source: IndexSet,
        to destination: Int,
        sortOrder keyPath: ReferenceWritableKeyPath<Element, Int>
    ) -> Bool {
        guard !source.isEmpty,
              source.allSatisfy({ items.indices.contains($0) }),
              (0...items.count).contains(destination)
        else { return false }

        var reordered = items
        let moving = source.map { reordered[$0] }
        for index in source.reversed() {
            reordered.remove(at: index)
        }

        let removedBeforeDestination = source.filter { $0 < destination }.count
        let insertionIndex = destination - removedBeforeDestination
        guard (0...reordered.count).contains(insertionIndex) else { return false }

        reordered.insert(contentsOf: moving, at: insertionIndex)
        normalize(reordered, sortOrder: keyPath)
        return true
    }
}
