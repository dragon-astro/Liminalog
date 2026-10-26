import Foundation

/// Keeps a drag's selection independent of storage updates and view redraws.
struct DiscreteSliderSelection {
    let count: Int
    private(set) var index: Int
    private(set) var position: Double

    init(index: Int, count: Int) {
        self.count = max(2, count)
        self.index = min(max(0, index), self.count - 1)
        self.position = Double(self.index)
    }

    /// A small dead band prevents repeated feedback when a finger rests on a boundary.
    mutating func update(position: Double, finishing: Bool = false) -> Int {
        guard position.isFinite else { return index }
        self.position = min(max(0, position), Double(count - 1))
        let candidate = Int(self.position.rounded())
        if finishing || abs(self.position - Double(index)) >= 0.58 {
            index = candidate
        }
        return index
    }
}
