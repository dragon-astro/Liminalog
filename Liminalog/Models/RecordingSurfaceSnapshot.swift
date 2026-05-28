import Foundation

struct RecordingSurfaceSnapshot: Codable, Hashable {
    struct Cell: Codable, Hashable, Identifiable {
        let id: UUID
        let name: String
        let colorHex: String
        let icon: String?
    }

    let selectedCategorySetID: UUID?
    let categorySetName: String
    let cells: [Cell?]

    var categories: [Cell] {
        cells.compactMap { $0 }
    }
}
