import Foundation
import Testing
import UIKit
@testable import Liminalog

@MainActor
@Suite("Category icon catalog")
struct CategoryIconCatalogTests {
    @Test("10ジャンル200件を重複なく収録する")
    func catalogHasExpectedScaleAndStableSections() {
        let items = CategoryIconCatalog.items
        let symbols = items.map(\.symbol)

        #expect(items.count == 200)
        #expect(Set(symbols).count == items.count)
        #expect(CategoryIconCatalog.sections.map(\.genre) == CategoryIconGenre.allCases)
        #expect(CategoryIconCatalog.sections.allSatisfy { $0.items.count == 20 })
        #expect(items.allSatisfy { !$0.symbol.isEmpty && !$0.label.isEmpty })
    }

    @Test("全カタログ名が実在するSF Symbol")
    func everyCatalogSymbolResolves() {
        let missing = CategoryIconCatalog.items
            .map(\.symbol)
            .filter { UIImage(systemName: $0) == nil }

        #expect(missing.isEmpty, "Unknown SF Symbols: \(missing.joined(separator: ", "))")
    }

    @Test("旧ピッカーの30候補をすべて保持する")
    func containsEveryLegacyPickerSymbol() {
        let expectedSymbols = [
            "book.closed.fill", "graduationcap.fill", "pencil.and.outline",
            "briefcase.fill", "laptopcomputer", "doc.text.fill", "checklist",
            "calendar", "clock.fill", "tram.fill", "figure.walk", "figure.run",
            "airplane", "house.fill", "wrench.and.screwdriver.fill", "cart.fill",
            "fork.knife", "cup.and.saucer.fill", "sparkles", "gamecontroller.fill",
            "music.note", "paintpalette.fill", "camera.fill", "movieclapper.fill",
            "heart.fill", "cross.case.fill", "dumbbell.fill", "bed.double.fill",
            "moon.fill", "person.2.fill",
        ]

        #expect(CategoryIconCatalog.legacySymbols == expectedSymbols)
        #expect(CategoryIconCatalog.legacyItems.map(\.symbol) == expectedSymbols)
        #expect(Set(expectedSymbols).isSubset(of: Set(CategoryIconCatalog.items.map(\.symbol))))
    }

    @Test("日本語ラベルとsymbol名の両方で検索できる")
    func searchesLabelsAndSymbolNames() {
        #expect(CategoryIconCatalog.search("読書").map(\.symbol).contains("book.closed.fill"))
        #expect(CategoryIconCatalog.search("  BOOK.CLOSED  ").map(\.symbol).contains("book.closed.fill"))
        #expect(CategoryIconCatalog.search("ＰＣ").map(\.symbol).contains("laptopcomputer"))
        #expect(CategoryIconCatalog.search("figure.pool").map(\.symbol) == ["figure.pool.swim"])
        #expect(CategoryIconCatalog.search("該当なし").isEmpty)
    }

    @Test("空検索と検索結果はカタログ順を維持する")
    func searchPreservesCatalogOrder() {
        #expect(CategoryIconCatalog.search("  ") == CategoryIconCatalog.items)

        let expected = CategoryIconCatalog.items.filter { $0.label.contains("写真") }
        #expect(CategoryIconCatalog.search("写真") == expected)
    }

    @Test("未収載iconは変換せず未収載として扱う")
    func uncataloguedSymbolIsNotNormalized() {
        let existingSymbol = "figure.skiing.crosscountry"

        #expect(UIImage(systemName: existingSymbol) != nil)
        #expect(CategoryIconCatalog.item(for: existingSymbol) == nil)
        #expect(CategoryIconCatalog.displaySymbol(for: existingSymbol) == existingSymbol)
        #expect(CategoryIconCatalog.displaySymbol(for: "not.a.real.sf.symbol") == "questionmark")
    }
}

@Suite("Category icon pin persistence", .serialized)
struct CategoryIconPinStoreTests {
    @Test("未設定時だけ既定8件を返し明示的な空配列は保持する")
    func distinguishesMissingKeyFromExplicitEmptyPins() throws {
        let suiteName = "CategoryIconPinStoreTests.missing.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(CategoryIconPinStore.load(from: defaults) == CategoryIconPinStore.defaultSymbols)

        CategoryIconPinStore.save([], to: defaults)
        #expect(CategoryIconPinStore.load(from: defaults).isEmpty)
    }

    @Test("ピンの内容と順序をUserDefaults再生成後も保持する")
    func pinnedSymbolsRoundTripInOrder() throws {
        let suiteName = "CategoryIconPinStoreTests.roundTrip.\(UUID().uuidString)"
        let writer = try #require(UserDefaults(suiteName: suiteName))
        writer.removePersistentDomain(forName: suiteName)
        defer { writer.removePersistentDomain(forName: suiteName) }
        let expected = ["moon.fill", "book.closed.fill", "figure.skiing.crosscountry"]

        CategoryIconPinStore.save(expected, to: writer)

        let reader = try #require(UserDefaults(suiteName: suiteName))
        #expect(CategoryIconPinStore.load(from: reader) == expected)
    }

    @Test("追加は末尾・解除は対象だけを除き順序を維持する")
    func toggleAppendsAndRemovesWithoutReordering() {
        let initial = ["book.closed.fill", "moon.fill"]
        let appended = CategoryIconPinStore.toggled("tram.fill", in: initial)

        #expect(appended == ["book.closed.fill", "moon.fill", "tram.fill"])
        #expect(CategoryIconPinStore.toggled("moon.fill", in: appended) == ["book.closed.fill", "tram.fill"])
        #expect(CategoryIconPinStore.toggled("  ", in: appended) == appended)
    }

    @Test("保存時は空白と重複を先勝ちで正規化し未収載iconも保持する")
    func normalizationKeepsFirstOccurrenceAndUnknownSymbols() throws {
        let suiteName = "CategoryIconPinStoreTests.normalization.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        CategoryIconPinStore.save(
            [" moon.fill ", "", "moon.fill", "figure.skiing.crosscountry"],
            to: defaults
        )

        #expect(CategoryIconPinStore.load(from: defaults) == ["moon.fill", "figure.skiing.crosscountry"])
    }

    @Test("既定ピンは全件カタログに存在する")
    func everyDefaultPinIsCatalogued() {
        let catalogSymbols = Set(CategoryIconCatalog.items.map(\.symbol))

        #expect(Set(CategoryIconPinStore.defaultSymbols).isSubset(of: catalogSymbols))
    }
}
