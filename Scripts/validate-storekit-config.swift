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

private func printUsage() {
    print("""
    usage:
      swift Scripts/validate-storekit-config.swift <path-to-liminalog.storekit>
      swift Scripts/validate-storekit-config.swift --expected

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
