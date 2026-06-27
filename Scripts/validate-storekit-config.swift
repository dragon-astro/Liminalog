#!/usr/bin/env swift

import Foundation

struct ExpectedProduct {
    let productID: String
    let displayName: String
    let kind: String
    let referencePrice: String
    let subscriptionGroup: String?
    let kindTokens: [String]
}

let autoRenewableSubscriptionTokens = [
    "Auto-Renewable Subscription",
    "RecurringSubscription",
    "auto-renewable-subscription",
    "com.apple.dt.storekit.auto-renewable-subscription"
]
let nonConsumableTokens = [
    "Non-Consumable",
    "Non-Consumable In-App Purchase",
    "NonConsumable",
    "non-consumable",
    "com.apple.dt.storekit.product.non-consumable"
]
let consumableTokens = [
    "Consumable",
    "Consumable In-App Purchase",
    "consumable",
    "com.apple.dt.storekit.product.consumable"
]

let expectedProducts: [ExpectedProduct] = [
    ExpectedProduct(
        productID: "liminalog.pro.monthly",
        displayName: "Liminalog Pro 月額",
        kind: "Auto-Renewable Subscription",
        referencePrice: "¥400",
        subscriptionGroup: "Liminalog Pro",
        kindTokens: autoRenewableSubscriptionTokens
    ),
    ExpectedProduct(
        productID: "liminalog.pro.yearly",
        displayName: "Liminalog Pro 年額",
        kind: "Auto-Renewable Subscription",
        referencePrice: "¥2,900",
        subscriptionGroup: "Liminalog Pro",
        kindTokens: autoRenewableSubscriptionTokens
    ),
    ExpectedProduct(
        productID: "liminalog.lifetime",
        displayName: "ライフタイム",
        kind: "Non-Consumable",
        referencePrice: "¥6,800",
        subscriptionGroup: nil,
        kindTokens: nonConsumableTokens
    ),
    ExpectedProduct(
        productID: "liminalog.decorations.monthly",
        displayName: "装飾パス 月額",
        kind: "Auto-Renewable Subscription",
        referencePrice: "¥200",
        subscriptionGroup: "Liminalog Pro",
        kindTokens: autoRenewableSubscriptionTokens
    ),
    ExpectedProduct(
        productID: "liminalog.decorations.yearly",
        displayName: "装飾パス 年額",
        kind: "Auto-Renewable Subscription",
        referencePrice: "¥1,500",
        subscriptionGroup: "Liminalog Pro",
        kindTokens: autoRenewableSubscriptionTokens
    ),
    ExpectedProduct(
        productID: "liminalog.support.small",
        displayName: "小さく応援",
        kind: "Consumable",
        referencePrice: "¥250",
        subscriptionGroup: nil,
        kindTokens: consumableTokens
    ),
    ExpectedProduct(
        productID: "liminalog.support.medium",
        displayName: "しっかり応援",
        kind: "Consumable",
        referencePrice: "¥600",
        subscriptionGroup: nil,
        kindTokens: consumableTokens
    ),
    ExpectedProduct(
        productID: "liminalog.support.large",
        displayName: "大きく応援",
        kind: "Consumable",
        referencePrice: "¥1,200",
        subscriptionGroup: nil,
        kindTokens: consumableTokens
    )
]

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--expected") {
    printExpectedProducts()
    exit(EXIT_SUCCESS)
}

if arguments.contains("--app-store-connect-tsv") {
    printAppStoreConnectTSV()
    exit(EXIT_SUCCESS)
}

if let docsFlagIndex = arguments.firstIndex(of: "--validate-products-doc") {
    let path = arguments.dropFirst(docsFlagIndex + 1).first ?? "AppStore/PurchaseProducts.md"
    validatePurchaseProductsDocument(at: path)
}

if let safetyFlagIndex = arguments.firstIndex(of: "--validate-release-safety") {
    let path = arguments.dropFirst(safetyFlagIndex + 1).first ?? "Liminalog/Stores/PurchaseConfiguration.swift"
    validateReleaseSafetyConfiguration(at: path)
}

guard let path = arguments.first, !path.hasPrefix("-") else {
    printUsage()
    exit(EXIT_FAILURE)
}

let fileURL = URL(fileURLWithPath: path)
guard FileManager.default.fileExists(atPath: fileURL.path) else {
    print("error: StoreKit configuration not found at \(fileURL.path)")
    printUsage()
    exit(EXIT_FAILURE)
}

do {
    let data = try Data(contentsOf: fileURL)
    let configuration = try loadConfiguration(from: data)
    let allStrings = collectStrings(configuration)
    let dictionaries = collectDictionaries(configuration)
    var failures: [String] = []
    var warnings: [String] = []

    for product in expectedProducts {
        guard allStrings.contains(product.productID) else {
            failures.append("missing product ID: \(product.productID) (\(product.displayName))")
            continue
        }

        if let productDictionary = dictionaries.first(where: { collectStrings($0).contains(product.productID) }) {
            let productStrings = collectStrings(productDictionary)
            if !product.kindTokens.contains(where: productStrings.contains) {
                warnings.append("could not confirm StoreKit kind for \(product.productID); expected \(product.kind)")
            }
        } else {
            warnings.append("could not locate product block for \(product.productID)")
        }
    }

    let expectedGroups = Set(expectedProducts.compactMap(\.subscriptionGroup))
    for group in expectedGroups where !allStrings.contains(group) {
        failures.append("missing subscription group: \(group)")
    }

    if failures.isEmpty {
        print("StoreKit configuration contains all planned Liminalog product IDs.")
    } else {
        for failure in failures {
            print("error: \(failure)")
        }
    }

    for warning in warnings {
        print("warning: \(warning)")
    }

    exit(failures.isEmpty ? EXIT_SUCCESS : EXIT_FAILURE)
} catch {
    print("error: failed to read StoreKit configuration: \(error.localizedDescription)")
    exit(EXIT_FAILURE)
}

private func loadConfiguration(from data: Data) throws -> Any {
    if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
        return json
    }
    return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
}

private func collectStrings(_ value: Any) -> Set<String> {
    var strings = Set<String>()

    func walk(_ value: Any) {
        if let string = value as? String {
            strings.insert(string)
        } else if let array = value as? [Any] {
            array.forEach(walk)
        } else if let dictionary = value as? [String: Any] {
            dictionary.keys.forEach { strings.insert($0) }
            dictionary.values.forEach(walk)
        }
    }

    walk(value)
    return strings
}

private func collectDictionaries(_ value: Any) -> [[String: Any]] {
    var dictionaries: [[String: Any]] = []

    func walk(_ value: Any) {
        if let dictionary = value as? [String: Any] {
            dictionaries.append(dictionary)
            dictionary.values.forEach(walk)
        } else if let array = value as? [Any] {
            array.forEach(walk)
        }
    }

    walk(value)
    return dictionaries
}

private func validatePurchaseProductsDocument(at path: String) -> Never {
    let fileURL = URL(fileURLWithPath: path)
    guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
        print("error: purchase products document not found at \(fileURL.path)")
        exit(EXIT_FAILURE)
    }

    let rows = productRows(in: text)
    var failures: [String] = []

    if rows.count != expectedProducts.count {
        failures.append("expected \(expectedProducts.count) product rows, found \(rows.count)")
    }

    for (index, expected) in expectedProducts.enumerated() {
        guard rows.indices.contains(index) else { continue }
        let row = rows[index]

        if row.productID != expected.productID {
            failures.append("row \(index + 1) product ID mismatch: expected \(expected.productID), found \(row.productID)")
        }
        if row.referenceName != expected.displayName {
            failures.append("row \(index + 1) reference name mismatch for \(expected.productID): expected \(expected.displayName), found \(row.referenceName)")
        }
        if row.type != expected.kind {
            failures.append("row \(index + 1) type mismatch for \(expected.productID): expected \(expected.kind), found \(row.type)")
        }
        if row.price != expected.referencePrice {
            failures.append("row \(index + 1) price mismatch for \(expected.productID): expected \(expected.referencePrice), found \(row.price)")
        }
        if row.subscriptionGroup != expected.subscriptionGroup {
            let expectedGroup = expected.subscriptionGroup ?? "-"
            let foundGroup = row.subscriptionGroup ?? "-"
            failures.append("row \(index + 1) group mismatch for \(expected.productID): expected \(expectedGroup), found \(foundGroup)")
        }
    }

    let expectedGroupNames = Set(expectedProducts.compactMap(\.subscriptionGroup))
    for groupName in expectedGroupNames where !text.contains(groupName) {
        failures.append("missing subscription group text: \(groupName)")
    }

    if failures.isEmpty {
        print("Purchase products document matches planned Liminalog product specifications.")
        exit(EXIT_SUCCESS)
    }

    for failure in failures {
        print("error: \(failure)")
    }
    exit(EXIT_FAILURE)
}

private func validateReleaseSafetyConfiguration(at path: String) -> Never {
    let fileURL = URL(fileURLWithPath: path)
    guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
        print("error: purchase configuration source not found at \(fileURL.path)")
        exit(EXIT_FAILURE)
    }

    guard let currentConfiguration = purchaseConfigurationCurrentBlock(in: text) else {
        print("error: could not locate PurchaseConfiguration.current in \(fileURL.path)")
        exit(EXIT_FAILURE)
    }

    let requiredSnippets: [(label: String, snippet: String)] = [
        ("StoreKit product IDs remain code-owned", "productIDs: PurchaseProductID.storeKitProductIDs"),
        ("App Store Connect product confirmation remains off", "productIDsAreConfirmedForAppStoreConnect: false"),
        ("subscription group remains unset", "subscriptionGroupName: nil"),
        ("terms URL remains unset", "termsOfUseURL: nil"),
        ("privacy URL points to the published LP", #"privacyPolicyURL: URL(string: "https://liminalog-lp.vercel.app/privacy")"#),
        ("purchase entry point remains off", "purchaseEntryPointIsEnabled: false"),
        ("feature restrictions remain off", "featureRestrictionsAreEnabled: false"),
        ("background entitlement refresh remains off", "backgroundEntitlementRefreshIsEnabled: false")
    ]

    let failures = requiredSnippets.compactMap { requirement -> String? in
        currentConfiguration.contains(requirement.snippet)
            ? nil
            : "missing safety setting: \(requirement.label)"
    }

    if failures.isEmpty {
        print("Release purchase safety configuration is closed for current Liminalog builds.")
        exit(EXIT_SUCCESS)
    }

    for failure in failures {
        print("error: \(failure)")
    }
    exit(EXIT_FAILURE)
}

private func purchaseConfigurationCurrentBlock(in source: String) -> String? {
    let marker = "static let current = PurchaseConfiguration("
    guard let markerRange = source.range(of: marker) else { return nil }

    var depth = 1
    var index = markerRange.upperBound

    while index < source.endIndex {
        let character = source[index]
        if character == "(" {
            depth += 1
        } else if character == ")" {
            depth -= 1
            if depth == 0 {
                return String(source[markerRange.lowerBound...index])
            }
        }
        index = source.index(after: index)
    }

    return nil
}

private struct ProductDocumentRow {
    var productID: String
    var referenceName: String
    var type: String
    var price: String
    var subscriptionGroup: String?
}

private func productRows(in markdown: String) -> [ProductDocumentRow] {
    markdown
        .split(separator: "\n", omittingEmptySubsequences: false)
        .compactMap { rawLine -> ProductDocumentRow? in
            let line = String(rawLine)
            guard line.hasPrefix("| `liminalog.") else { return nil }
            let columns = line
                .split(separator: "|", omittingEmptySubsequences: false)
                .dropFirst()
                .dropLast()
                .map { normalizeMarkdownCell(String($0)) }
            guard columns.count == 5 else { return nil }
            return ProductDocumentRow(
                productID: columns[0],
                referenceName: columns[1],
                type: columns[2],
                price: columns[3],
                subscriptionGroup: columns[4] == "-" ? nil : columns[4]
            )
        }
}

private func normalizeMarkdownCell(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "`", with: "")
}

private func printUsage() {
    print("""
    usage:
      swift Scripts/validate-storekit-config.swift <path-to-liminalog.storekit>
      swift Scripts/validate-storekit-config.swift --expected
      swift Scripts/validate-storekit-config.swift --app-store-connect-tsv
      swift Scripts/validate-storekit-config.swift --validate-products-doc [path-to-PurchaseProducts.md]
      swift Scripts/validate-storekit-config.swift --validate-release-safety [path-to-PurchaseConfiguration.swift]

    Create the StoreKit configuration in Xcode first, then run this validator.
    """)
}

private func printExpectedProducts() {
    print("Expected Liminalog StoreKit products:")
    for product in expectedProducts {
        let group = product.subscriptionGroup ?? "-"
        print("- \(product.productID) | \(product.kind) | \(product.referencePrice) | group: \(group)")
    }
}

private func printAppStoreConnectTSV() {
    print("Product ID\tReference Name\tType\tReference Price\tSubscription Group\tNotes")
    for product in expectedProducts {
        let group = product.subscriptionGroup ?? "-"
        let notes = appStoreConnectNotes(for: product)
        print("\(product.productID)\t\(product.displayName)\t\(product.kind)\t\(product.referencePrice)\t\(group)\t\(notes)")
    }
}

private func appStoreConnectNotes(for product: ExpectedProduct) -> String {
    switch product.productID {
    case "liminalog.pro.yearly":
        return "7日無料体験は未確定。確定後にアプリ内文言へ反映する。"
    case "liminalog.decorations.monthly", "liminalog.decorations.yearly":
        return "アプリ側ではライフタイム所有者向けに表示制御する。"
    case "liminalog.support.small", "liminalog.support.medium", "liminalog.support.large":
        return "機能解放ではなく任意支援。恒久権利を付けない。"
    default:
        return ""
    }
}
