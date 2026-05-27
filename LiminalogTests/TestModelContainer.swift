import Foundation
import SwiftData
@testable import Liminalog

@MainActor
enum TestModelContainer {
    static func make() throws -> ModelContainer {
        let schema = Schema(LiminalogSchemaV1.models)
        let configuration = ModelConfiguration(
            "Tests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

extension Calendar {
    static var liminalogTest: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "ja_JP")
        return calendar
    }
}

final class MutableTestClock: LiminalogClock, @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}
