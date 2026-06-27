#!/usr/bin/env swift

import Foundation

struct ExpectedProduct {
    let productID: String
    let displayName: String
    let kind: String
    let referencePrice: String
    let subscriptionGroup: String?
    let billingPlanType: String?
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
        billingPlanType: "monthly",
        kindTokens: autoRenewableSubscriptionTokens
    ),
    ExpectedProduct(
        productID: "liminalog.pro.yearly",
        displayName: "Liminalog Pro 年額",
        kind: "Auto-Renewable Subscription",
        referencePrice: "¥2,900",
        subscriptionGroup: "Liminalog Pro",
        billingPlanType: "upfront",
        kindTokens: autoRenewableSubscriptionTokens
    ),
    ExpectedProduct(
        productID: "liminalog.lifetime",
        displayName: "ライフタイム",
        kind: "Non-Consumable",
        referencePrice: "¥6,800",
        subscriptionGroup: nil,
        billingPlanType: nil,
        kindTokens: nonConsumableTokens
    ),
    ExpectedProduct(
        productID: "liminalog.decorations.monthly",
        displayName: "装飾パス 月額",
        kind: "Auto-Renewable Subscription",
        referencePrice: "¥200",
        subscriptionGroup: "Liminalog Pro",
        billingPlanType: "monthly",
        kindTokens: autoRenewableSubscriptionTokens
    ),
    ExpectedProduct(
        productID: "liminalog.decorations.yearly",
        displayName: "装飾パス 年額",
        kind: "Auto-Renewable Subscription",
        referencePrice: "¥1,500",
        subscriptionGroup: "Liminalog Pro",
        billingPlanType: "upfront",
        kindTokens: autoRenewableSubscriptionTokens
    ),
    ExpectedProduct(
        productID: "liminalog.support.small",
        displayName: "小さく応援",
        kind: "Consumable",
        referencePrice: "¥250",
        subscriptionGroup: nil,
        billingPlanType: nil,
        kindTokens: consumableTokens
    ),
    ExpectedProduct(
        productID: "liminalog.support.medium",
        displayName: "しっかり応援",
        kind: "Consumable",
        referencePrice: "¥600",
        subscriptionGroup: nil,
        billingPlanType: nil,
        kindTokens: consumableTokens
    ),
    ExpectedProduct(
        productID: "liminalog.support.large",
        displayName: "大きく応援",
        kind: "Consumable",
        referencePrice: "¥1,200",
        subscriptionGroup: nil,
        billingPlanType: nil,
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

if arguments.contains("--app-store-connect-confirmation-md") {
    printAppStoreConnectConfirmationMarkdown()
    exit(EXIT_SUCCESS)
}

if let confirmationTemplateFlagIndex = arguments.firstIndex(of: "--validate-app-store-connect-confirmation-template") {
    let candidatePath = arguments.dropFirst(confirmationTemplateFlagIndex + 1).first
    let path = candidatePath?.hasPrefix("-") == false ? candidatePath! : "AppStore/AppStoreConnectProductConfirmation.md"
    validateAppStoreConnectConfirmationTemplate(at: path)
}

if let confirmationCompleteFlagIndex = arguments.firstIndex(of: "--validate-app-store-connect-confirmation-complete") {
    let candidatePath = arguments.dropFirst(confirmationCompleteFlagIndex + 1).first
    let path = candidatePath?.hasPrefix("-") == false ? candidatePath! : "AppStore/AppStoreConnectProductConfirmation.md"
    validateAppStoreConnectConfirmationComplete(at: path)
}

if let docsFlagIndex = arguments.firstIndex(of: "--validate-products-doc") {
    let path = arguments.dropFirst(docsFlagIndex + 1).first ?? "AppStore/PurchaseProducts.md"
    validatePurchaseProductsDocument(at: path)
}

if let productSourceFlagIndex = arguments.firstIndex(of: "--validate-product-source") {
    let candidatePath = arguments.dropFirst(productSourceFlagIndex + 1).first
    let path = candidatePath?.hasPrefix("-") == false ? candidatePath! : "Liminalog/Stores/PurchaseProduct.swift"
    validatePurchaseProductSource(at: path)
}

if let premiumDecorationDocsFlagIndex = arguments.firstIndex(of: "--validate-premium-decoration-products-doc") {
    let candidatePath = arguments.dropFirst(premiumDecorationDocsFlagIndex + 1).first
    let path = candidatePath?.hasPrefix("-") == false ? candidatePath! : "AppStore/PurchaseProducts.md"
    validatePremiumDecorationProductsDocument(
        at: path,
        catalogPath: "Liminalog/Stores/PremiumDecorationCatalog.swift"
    )
}

if let premiumDecorationInactiveFlagIndex = arguments.firstIndex(of: "--validate-premium-decoration-inactive") {
    let candidatePath = arguments.dropFirst(premiumDecorationInactiveFlagIndex + 1).first
    let path = candidatePath?.hasPrefix("-") == false ? candidatePath! : "liminalog.storekit"
    validatePremiumDecorationProductsInactive(
        in: path,
        catalogPath: "Liminalog/Stores/PremiumDecorationCatalog.swift"
    )
}

if let safetyFlagIndex = arguments.firstIndex(of: "--validate-release-safety") {
    let path = arguments.dropFirst(safetyFlagIndex + 1).first ?? "Liminalog/Stores/PurchaseConfiguration.swift"
    validateReleaseSafetyConfiguration(at: path)
}

if let schemeFlagIndex = arguments.firstIndex(of: "--validate-xcode-scheme-storekit") {
    let path = arguments.dropFirst(schemeFlagIndex + 1).first ?? "Liminalog.xcodeproj/xcshareddata/xcschemes/Liminalog.xcscheme"
    validateXcodeSchemeStoreKitReference(at: path)
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

        if let productDictionary = productDictionary(for: product.productID, in: dictionaries) {
            let productStrings = collectStrings(productDictionary)
            if !product.kindTokens.contains(where: productStrings.contains) {
                warnings.append("could not confirm StoreKit kind for \(product.productID); expected \(product.kind)")
            }
            if let billingPlanType = product.billingPlanType {
                validateBillingPlan(
                    in: productDictionary,
                    product: product,
                    expectedType: billingPlanType,
                    failures: &failures
                )
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

private func productDictionary(for productID: String, in dictionaries: [[String: Any]]) -> [String: Any]? {
    if let directProduct = dictionaries.first(where: { ($0["productID"] as? String) == productID }) {
        return directProduct
    }
    return dictionaries.first(where: { collectStrings($0).contains(productID) })
}

private func validateBillingPlan(
    in productDictionary: [String: Any],
    product: ExpectedProduct,
    expectedType: String,
    failures: inout [String]
) {
    guard let billingPlans = productDictionary["billingPlans"] as? [[String: Any]], !billingPlans.isEmpty else {
        failures.append("missing billingPlans for recurring subscription: \(product.productID)")
        return
    }

    let hasExpectedType = billingPlans.contains { plan in
        (plan["billingPlanType"] as? String) == expectedType
    }
    if !hasExpectedType {
        failures.append("missing billingPlanType \(expectedType) for \(product.productID)")
    }

    let hasDisplayPrice = billingPlans.contains { plan in
        guard let displayPrice = plan["displayPrice"] as? String else { return false }
        return !displayPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    if !hasDisplayPrice {
        failures.append("missing billing plan displayPrice for \(product.productID)")
    }
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

private func validatePurchaseProductSource(at path: String) -> Never {
    let fileURL = URL(fileURLWithPath: path)
    guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else {
        print("error: purchase product source not found at \(fileURL.path)")
        exit(EXIT_FAILURE)
    }

    let sourceProducts = purchaseProductSourceSpecs(in: source)
    var failures: [String] = []

    if sourceProducts.isEmpty {
        failures.append("could not parse PurchaseProductID.appStoreConnectSpecifications inputs from \(path)")
    }

    if sourceProducts.count != expectedProducts.count {
        failures.append("expected \(expectedProducts.count) source products, found \(sourceProducts.count)")
    }

    for (index, expected) in expectedProducts.enumerated() {
        guard sourceProducts.indices.contains(index) else { continue }
        let sourceProduct = sourceProducts[index]

        if sourceProduct.productID != expected.productID {
            failures.append("source row \(index + 1) product ID mismatch: expected \(expected.productID), found \(sourceProduct.productID)")
        }
        if sourceProduct.displayName != expected.displayName {
            failures.append("source row \(index + 1) display name mismatch for \(expected.productID): expected \(expected.displayName), found \(sourceProduct.displayName)")
        }
        if sourceProduct.kind != expected.kind {
            failures.append("source row \(index + 1) type mismatch for \(expected.productID): expected \(expected.kind), found \(sourceProduct.kind)")
        }
        if sourceProduct.referencePrice != expected.referencePrice {
            failures.append("source row \(index + 1) price mismatch for \(expected.productID): expected \(expected.referencePrice), found \(sourceProduct.referencePrice)")
        }
        if sourceProduct.subscriptionGroup != expected.subscriptionGroup {
            let expectedGroup = expected.subscriptionGroup ?? "-"
            let foundGroup = sourceProduct.subscriptionGroup ?? "-"
            failures.append("source row \(index + 1) group mismatch for \(expected.productID): expected \(expectedGroup), found \(foundGroup)")
        }
    }

    if failures.isEmpty {
        print("Purchase product source matches planned Liminalog product specifications.")
        exit(EXIT_SUCCESS)
    }

    for failure in failures {
        print("error: \(failure)")
    }
    exit(EXIT_FAILURE)
}

private func validateAppStoreConnectConfirmationTemplate(at path: String) -> Never {
    let fileURL = URL(fileURLWithPath: path)
    guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
        print("error: App Store Connect confirmation template not found at \(fileURL.path)")
        exit(EXIT_FAILURE)
    }

    let failures = appStoreConnectConfirmationTemplateFailures(in: text)

    if failures.isEmpty {
        print("App Store Connect confirmation template matches planned Liminalog product specifications.")
        exit(EXIT_SUCCESS)
    }

    for failure in failures {
        print("error: \(failure)")
    }
    exit(EXIT_FAILURE)
}

private func validateAppStoreConnectConfirmationComplete(at path: String) -> Never {
    let fileURL = URL(fileURLWithPath: path)
    guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
        print("error: App Store Connect confirmation sheet not found at \(fileURL.path)")
        exit(EXIT_FAILURE)
    }

    var failures = appStoreConnectConfirmationTemplateFailures(in: text)

    let metadata = metadataRows(in: markdownSection(named: "Confirmation Metadata", in: text))
    if metadata["Confirmed by", default: ""].isEmpty {
        failures.append("confirmation metadata is missing Confirmed by")
    }
    if metadata["Confirmation date", default: ""].isEmpty {
        failures.append("confirmation metadata is missing Confirmation date")
    }
    if metadata["App Store Connect app"] != "Liminalog" {
        failures.append("confirmation metadata App Store Connect app must be Liminalog")
    }

    failures.append(contentsOf: uncheckedConfirmationRows(
        in: markdownSection(named: "Subscription Group", in: text),
        label: "subscription group"
    ))
    failures.append(contentsOf: uncheckedConfirmationRows(
        in: markdownSection(named: "Products", in: text),
        label: "product"
    ))

    if failures.isEmpty {
        print("App Store Connect confirmation sheet is complete.")
        exit(EXIT_SUCCESS)
    }

    for failure in failures {
        print("error: \(failure)")
    }
    exit(EXIT_FAILURE)
}

private func appStoreConnectConfirmationTemplateFailures(in text: String) -> [String] {
    let rows = appStoreConnectConfirmationRows(in: text)
    var failures: [String] = []

    if rows.count != expectedProducts.count {
        failures.append("expected \(expectedProducts.count) confirmation product rows, found \(rows.count)")
    }

    for (index, expected) in expectedProducts.enumerated() {
        guard rows.indices.contains(index) else { continue }
        let row = rows[index]

        if row.productID != expected.productID {
            failures.append("confirmation row \(index + 1) product ID mismatch: expected \(expected.productID), found \(row.productID)")
        }
        if row.referenceName != expected.displayName {
            failures.append("confirmation row \(index + 1) reference name mismatch for \(expected.productID): expected \(expected.displayName), found \(row.referenceName)")
        }
        if row.type != expected.kind {
            failures.append("confirmation row \(index + 1) type mismatch for \(expected.productID): expected \(expected.kind), found \(row.type)")
        }
        if row.price != expected.referencePrice {
            failures.append("confirmation row \(index + 1) price mismatch for \(expected.productID): expected \(expected.referencePrice), found \(row.price)")
        }
        if row.subscriptionGroup != expected.subscriptionGroup {
            let expectedGroup = expected.subscriptionGroup ?? "-"
            let foundGroup = row.subscriptionGroup ?? "-"
            failures.append("confirmation row \(index + 1) group mismatch for \(expected.productID): expected \(expectedGroup), found \(foundGroup)")
        }
        if row.notes != appStoreConnectNotes(for: expected) {
            failures.append("confirmation row \(index + 1) notes mismatch for \(expected.productID)")
        }
    }

    if !text.contains("Group Reference Name") || !text.contains("Liminalog Pro") {
        failures.append("missing Liminalog Pro subscription group confirmation")
    }

    return failures
}

private func validatePremiumDecorationProductsDocument(at path: String, catalogPath: String) -> Never {
    let fileURL = URL(fileURLWithPath: path)
    guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
        print("error: purchase products document not found at \(fileURL.path)")
        exit(EXIT_FAILURE)
    }

    let catalogURL = URL(fileURLWithPath: catalogPath)
    guard let catalogSource = try? String(contentsOf: catalogURL, encoding: .utf8) else {
        print("error: premium decoration catalog source not found at \(catalogURL.path)")
        exit(EXIT_FAILURE)
    }

    let expectedRows = premiumDecorationCatalogItems(in: catalogSource)
    let rows = productRows(in: text, sectionName: "Premium Decoration Single Products")
    var failures: [String] = []

    if expectedRows.isEmpty {
        failures.append("could not parse premium decoration products from \(catalogPath)")
    }

    if rows.count != expectedRows.count {
        failures.append("expected \(expectedRows.count) premium decoration rows, found \(rows.count)")
    }

    for (index, expected) in expectedRows.enumerated() {
        guard rows.indices.contains(index) else { continue }
        let row = rows[index]

        if row.productID != expected.productID {
            failures.append("premium row \(index + 1) product ID mismatch: expected \(expected.productID), found \(row.productID)")
        }
        if row.referenceName != expected.displayName {
            failures.append("premium row \(index + 1) reference name mismatch for \(expected.productID): expected \(expected.displayName), found \(row.referenceName)")
        }
        if row.type != "Non-Consumable" {
            failures.append("premium row \(index + 1) type mismatch for \(expected.productID): expected Non-Consumable, found \(row.type)")
        }
        if row.price != "¥120" {
            failures.append("premium row \(index + 1) price mismatch for \(expected.productID): expected ¥120, found \(row.price)")
        }
        if row.subscriptionGroup != nil {
            let foundGroup = row.subscriptionGroup ?? "-"
            failures.append("premium row \(index + 1) group mismatch for \(expected.productID): expected -, found \(foundGroup)")
        }
    }

    if failures.isEmpty {
        print("Premium decoration product document matches PremiumDecorationCatalog.")
        exit(EXIT_SUCCESS)
    }

    for failure in failures {
        print("error: \(failure)")
    }
    exit(EXIT_FAILURE)
}

private func validatePremiumDecorationProductsInactive(in storeKitPath: String, catalogPath: String) -> Never {
    let storeKitURL = URL(fileURLWithPath: storeKitPath)
    guard let data = try? Data(contentsOf: storeKitURL) else {
        print("error: StoreKit configuration not found at \(storeKitURL.path)")
        exit(EXIT_FAILURE)
    }

    let catalogURL = URL(fileURLWithPath: catalogPath)
    guard let catalogSource = try? String(contentsOf: catalogURL, encoding: .utf8) else {
        print("error: premium decoration catalog source not found at \(catalogURL.path)")
        exit(EXIT_FAILURE)
    }

    let premiumItems = premiumDecorationCatalogItems(in: catalogSource)
    guard !premiumItems.isEmpty else {
        print("error: could not parse premium decoration products from \(catalogPath)")
        exit(EXIT_FAILURE)
    }

    do {
        let configuration = try loadConfiguration(from: data)
        let allStrings = collectStrings(configuration)
        let activeProductIDs = premiumItems
            .map(\.productID)
            .filter { allStrings.contains($0) }

        if activeProductIDs.isEmpty {
            print("Premium decoration single products are not active in \(storeKitPath).")
            exit(EXIT_SUCCESS)
        }

        for productID in activeProductIDs {
            print("error: premium decoration product is active before UI connection: \(productID)")
        }
        exit(EXIT_FAILURE)
    } catch {
        print("error: failed to read StoreKit configuration: \(error.localizedDescription)")
        exit(EXIT_FAILURE)
    }
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

private func validateXcodeSchemeStoreKitReference(at path: String) -> Never {
    let fileURL = URL(fileURLWithPath: path)
    guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
        print("error: Xcode scheme not found at \(fileURL.path)")
        exit(EXIT_FAILURE)
    }

    let requiredSnippets: [(label: String, snippet: String)] = [
        ("StoreKit configuration reference", "StoreKitConfigurationFileReference"),
        ("liminalog.storekit scheme link", #"identifier = "container:liminalog.storekit""#)
    ]

    let failures = requiredSnippets.compactMap { requirement -> String? in
        text.contains(requirement.snippet)
            ? nil
            : "missing scheme setting: \(requirement.label)"
    }

    if failures.isEmpty {
        print("Xcode scheme is linked to liminalog.storekit for local StoreKit QA.")
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

private struct ProductSourceRow {
    var productID: String
    var displayName: String
    var kind: String
    var referencePrice: String
    var subscriptionGroup: String?
}

private struct ConfirmationProductRow {
    var productID: String
    var referenceName: String
    var type: String
    var price: String
    var subscriptionGroup: String?
    var notes: String
}

private struct PremiumDecorationSourceItem {
    var productID: String
    var displayName: String
}

private func productRows(in markdown: String, sectionName: String = "Products") -> [ProductDocumentRow] {
    markdownSection(named: sectionName, in: markdown)
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

private func appStoreConnectConfirmationRows(in markdown: String) -> [ConfirmationProductRow] {
    markdownSection(named: "Products", in: markdown)
        .split(separator: "\n", omittingEmptySubsequences: false)
        .compactMap { rawLine -> ConfirmationProductRow? in
            let line = String(rawLine)
            guard line.contains("| `liminalog.") else { return nil }
            let columns = line
                .split(separator: "|", omittingEmptySubsequences: false)
                .dropFirst()
                .dropLast()
                .map { normalizeMarkdownCell(String($0)) }
            guard columns.count == 7 else { return nil }
            return ConfirmationProductRow(
                productID: columns[1],
                referenceName: columns[2],
                type: columns[3],
                price: columns[4],
                subscriptionGroup: columns[5] == "-" ? nil : columns[5],
                notes: columns[6]
            )
        }
}

private func purchaseProductSourceSpecs(in source: String) -> [ProductSourceRow] {
    let productIDsByCase = purchaseProductEnumCases(in: source)
    let displayNames = stringSwitchValues(in: source, marker: "var displayName: String {")
    let prices = stringSwitchValues(in: source, marker: "var referencePriceText: String {")
    let productKinds = enumSwitchValues(in: source, marker: "var kind: PurchaseProductKind {")
    let order = primaryDisplayOrder(in: source)

    return order.compactMap { caseName in
        guard
            let productID = productIDsByCase[caseName],
            let displayName = displayNames[caseName],
            let referencePrice = prices[caseName],
            let productKind = productKinds[caseName],
            let storeKitKind = storeKitKindName(forProductKind: productKind)
        else {
            return nil
        }

        return ProductSourceRow(
            productID: productID,
            displayName: displayName,
            kind: storeKitKind,
            referencePrice: referencePrice,
            subscriptionGroup: productKindUsesSubscriptionGroup(productKind) ? "Liminalog Pro" : nil
        )
    }
}

private func purchaseProductEnumCases(in source: String) -> [String: String] {
    let pattern = #"\bcase\s+([A-Za-z0-9_]+)\s*=\s*"([^"]+)""#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return [:]
    }
    let nsSource = source as NSString
    let range = NSRange(location: 0, length: nsSource.length)
    return Dictionary(uniqueKeysWithValues: regex.matches(in: source, range: range).map { match in
        (
            nsSource.substring(with: match.range(at: 1)),
            nsSource.substring(with: match.range(at: 2))
        )
    })
}

private func primaryDisplayOrder(in source: String) -> [String] {
    let pattern = #"static let primaryDisplayOrder:\s*\[PurchaseProductID\]\s*=\s*\[(.*?)\]"#
    guard
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
        let match = regex.firstMatch(in: source, range: NSRange(location: 0, length: (source as NSString).length))
    else {
        return []
    }

    let nsSource = source as NSString
    let block = nsSource.substring(with: match.range(at: 1))
    return dotCaseNames(in: block)
}

private func stringSwitchValues(in source: String, marker: String) -> [String: String] {
    guard let block = sourceBlock(in: source, startingAt: marker) else {
        return [:]
    }

    let pattern = #"case\s+([^:]+):\s*"([^"]+)""#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
        return [:]
    }

    let nsBlock = block as NSString
    let range = NSRange(location: 0, length: nsBlock.length)
    var values: [String: String] = [:]
    for match in regex.matches(in: block, range: range) {
        let caseList = nsBlock.substring(with: match.range(at: 1))
        let value = nsBlock.substring(with: match.range(at: 2))
        for caseName in dotCaseNames(in: caseList) {
            values[caseName] = value
        }
    }
    return values
}

private func enumSwitchValues(in source: String, marker: String) -> [String: String] {
    guard let block = sourceBlock(in: source, startingAt: marker) else {
        return [:]
    }

    let pattern = #"case\s+([^:]+):\s*\.([A-Za-z0-9_]+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
        return [:]
    }

    let nsBlock = block as NSString
    let range = NSRange(location: 0, length: nsBlock.length)
    var values: [String: String] = [:]
    for match in regex.matches(in: block, range: range) {
        let caseList = nsBlock.substring(with: match.range(at: 1))
        let value = nsBlock.substring(with: match.range(at: 2))
        for caseName in dotCaseNames(in: caseList) {
            values[caseName] = value
        }
    }
    return values
}

private func sourceBlock(in source: String, startingAt marker: String) -> String? {
    guard let markerRange = source.range(of: marker),
          let openingBrace = source[markerRange.lowerBound...].firstIndex(of: "{")
    else {
        return nil
    }

    var depth = 0
    var index = openingBrace

    while index < source.endIndex {
        let character = source[index]
        if character == "{" {
            depth += 1
        } else if character == "}" {
            depth -= 1
            if depth == 0 {
                return String(source[openingBrace...index])
            }
        }
        index = source.index(after: index)
    }

    return nil
}

private func dotCaseNames(in text: String) -> [String] {
    text
        .split(separator: ",")
        .map {
            $0
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ".", with: "")
        }
        .filter { !$0.isEmpty }
}

private func storeKitKindName(forProductKind productKind: String) -> String? {
    switch productKind {
    case "proSubscription", "decorationSubscription":
        return "Auto-Renewable Subscription"
    case "lifetime", "premiumDecoration":
        return "Non-Consumable"
    case "supportTip":
        return "Consumable"
    default:
        return nil
    }
}

private func productKindUsesSubscriptionGroup(_ productKind: String) -> Bool {
    switch productKind {
    case "proSubscription", "decorationSubscription":
        return true
    default:
        return false
    }
}

private func premiumDecorationCatalogItems(in source: String) -> [PremiumDecorationSourceItem] {
    let pattern = #"\.(iconFrame|cardStyle)\(\s*productID:\s*"([^"]+)",\s*targetID:\s*"([^"]+)",\s*displayName:\s*"([^"]+)",\s*sortOrder:\s*\d+\s*\)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return []
    }

    let nsSource = source as NSString
    let range = NSRange(location: 0, length: nsSource.length)
    return regex.matches(in: source, range: range).map { match in
        PremiumDecorationSourceItem(
            productID: nsSource.substring(with: match.range(at: 2)),
            displayName: nsSource.substring(with: match.range(at: 4))
        )
    }
}

private func markdownSection(named heading: String, in markdown: String) -> String {
    let marker = "## \(heading)"
    guard let startRange = markdown.range(of: marker) else {
        return markdown
    }

    let contentStart = startRange.upperBound
    let remaining = markdown[contentStart...]
    if let nextHeadingRange = remaining.range(of: "\n## ") {
        return String(remaining[..<nextHeadingRange.lowerBound])
    }
    return String(remaining)
}

private func metadataRows(in markdown: String) -> [String: String] {
    var rows: [String: String] = [:]
    for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(rawLine)
        guard line.hasPrefix("| "), !line.contains("---") else { continue }
        let columns = line
            .split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst()
            .dropLast()
            .map { normalizeMarkdownCell(String($0)) }
        guard columns.count == 2 else { continue }
        rows[columns[0]] = columns[1]
    }
    return rows
}

private func uncheckedConfirmationRows(in markdown: String, label: String) -> [String] {
    markdown
        .split(separator: "\n", omittingEmptySubsequences: false)
        .compactMap { rawLine -> String? in
            let line = String(rawLine)
            guard line.hasPrefix("| [") else { return nil }
            if line.hasPrefix("| [x]") || line.hasPrefix("| [X]") {
                return nil
            }
            let columns = line
                .split(separator: "|", omittingEmptySubsequences: false)
                .dropFirst()
                .dropLast()
                .map { normalizeMarkdownCell(String($0)) }
            let detail = columns.dropFirst().first ?? "unknown"
            return "\(label) confirmation is not checked: \(detail)"
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
      swift Scripts/validate-storekit-config.swift --app-store-connect-confirmation-md
      swift Scripts/validate-storekit-config.swift --validate-app-store-connect-confirmation-template [path-to-AppStoreConnectProductConfirmation.md]
      swift Scripts/validate-storekit-config.swift --validate-app-store-connect-confirmation-complete [path-to-AppStoreConnectProductConfirmation.md]
      swift Scripts/validate-storekit-config.swift --validate-products-doc [path-to-PurchaseProducts.md]
      swift Scripts/validate-storekit-config.swift --validate-product-source [path-to-PurchaseProduct.swift]
      swift Scripts/validate-storekit-config.swift --validate-premium-decoration-products-doc [path-to-PurchaseProducts.md]
      swift Scripts/validate-storekit-config.swift --validate-premium-decoration-inactive [path-to-liminalog.storekit]
      swift Scripts/validate-storekit-config.swift --validate-release-safety [path-to-PurchaseConfiguration.swift]
      swift Scripts/validate-storekit-config.swift --validate-xcode-scheme-storekit [path-to-Liminalog.xcscheme]

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

private func printAppStoreConnectConfirmationMarkdown() {
    print("""
    # App Store Connect Product Confirmation

    App Store Connect で商品を作成した後、この表を確認する。すべて確認できるまで `PurchaseConfiguration.current.productIDsAreConfirmedForAppStoreConnect` は `true` にしない。

    ## Subscription Group

    | Check | Field | Expected |
    |---|---|---|
    | [ ] | Group Reference Name | `Liminalog Pro` |
    | [ ] | Contains Products | Proサブと装飾パスが同じグループに入っている |

    ## Products

    | Check | Product ID | Reference Name | Type | Reference Price | Subscription Group | Notes |
    |---|---|---|---|---:|---|---|
    """)

    for product in expectedProducts {
        let group = product.subscriptionGroup ?? "-"
        let notes = appStoreConnectNotes(for: product)
        print("| [ ] | `\(product.productID)` | \(product.displayName) | \(product.kind) | \(product.referencePrice) | \(group) | \(notes) |")
    }

    print("""

    ## Gate 1 App Code Change After Confirmation

    ```swift
    productIDsAreConfirmedForAppStoreConnect: true
    subscriptionGroupName: "Liminalog Pro"
    legalLinks: PurchaseLegalLinks(
        termsOfUseURL: URL(string: "https://liminalog-lp.vercel.app/terms"),
        privacyPolicyURL: URL(string: "https://liminalog-lp.vercel.app/privacy")
    )
    purchaseEntryPointIsEnabled: false
    featureRestrictionsAreEnabled: false
    backgroundEntitlementRefreshIsEnabled: false
    ```

    Gate 1 では購入導線をまだ出さない。`purchaseEntryPointIsEnabled` と `featureRestrictionsAreEnabled` は `false` のままにする。
    """)
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
