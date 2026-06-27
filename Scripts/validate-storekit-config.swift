#!/usr/bin/env swift

import Foundation

struct ExpectedProduct {
    let productID: String
    let displayName: String
    let kind: String
    let referencePrice: String
    let subscriptionGroup: String?
    let billingPlanType: String?
    let appStoreDescription: String
    let introductoryOffer: String
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
        appStoreDescription: "統計などのPro機能とプレミアム装飾を月ごとに利用できます。",
        introductoryOffer: "-",
        kindTokens: autoRenewableSubscriptionTokens
    ),
    ExpectedProduct(
        productID: "liminalog.pro.yearly",
        displayName: "Liminalog Pro 年額",
        kind: "Auto-Renewable Subscription",
        referencePrice: "¥2,900",
        subscriptionGroup: "Liminalog Pro",
        billingPlanType: "upfront",
        appStoreDescription: "統計などのPro機能とプレミアム装飾を年ごとに利用できます。",
        introductoryOffer: "未確定（付ける場合はアプリ内文言とQA表も同時更新）",
        kindTokens: autoRenewableSubscriptionTokens
    ),
    ExpectedProduct(
        productID: "liminalog.lifetime",
        displayName: "ライフタイム",
        kind: "Non-Consumable",
        referencePrice: "¥6,800",
        subscriptionGroup: nil,
        billingPlanType: nil,
        appStoreDescription: "Pro機能を買い切りで利用できます。",
        introductoryOffer: "-",
        kindTokens: nonConsumableTokens
    ),
    ExpectedProduct(
        productID: "liminalog.decorations.monthly",
        displayName: "装飾パス 月額",
        kind: "Auto-Renewable Subscription",
        referencePrice: "¥200",
        subscriptionGroup: "Liminalog Pro",
        billingPlanType: "monthly",
        appStoreDescription: "ライフタイム所有者向けにプレミアム装飾を月ごとに利用できます。",
        introductoryOffer: "-",
        kindTokens: autoRenewableSubscriptionTokens
    ),
    ExpectedProduct(
        productID: "liminalog.decorations.yearly",
        displayName: "装飾パス 年額",
        kind: "Auto-Renewable Subscription",
        referencePrice: "¥1,500",
        subscriptionGroup: "Liminalog Pro",
        billingPlanType: "upfront",
        appStoreDescription: "ライフタイム所有者向けにプレミアム装飾を年ごとに利用できます。",
        introductoryOffer: "-",
        kindTokens: autoRenewableSubscriptionTokens
    ),
    ExpectedProduct(
        productID: "liminalog.support.small",
        displayName: "小さく応援",
        kind: "Consumable",
        referencePrice: "¥250",
        subscriptionGroup: nil,
        billingPlanType: nil,
        appStoreDescription: "機能解放なしでLiminalogを応援します。",
        introductoryOffer: "-",
        kindTokens: consumableTokens
    ),
    ExpectedProduct(
        productID: "liminalog.support.medium",
        displayName: "しっかり応援",
        kind: "Consumable",
        referencePrice: "¥600",
        subscriptionGroup: nil,
        billingPlanType: nil,
        appStoreDescription: "機能解放なしでLiminalogを応援します。",
        introductoryOffer: "-",
        kindTokens: consumableTokens
    ),
    ExpectedProduct(
        productID: "liminalog.support.large",
        displayName: "大きく応援",
        kind: "Consumable",
        referencePrice: "¥1,200",
        subscriptionGroup: nil,
        billingPlanType: nil,
        appStoreDescription: "機能解放なしでLiminalogを応援します。",
        introductoryOffer: "-",
        kindTokens: consumableTokens
    )
]

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--help") || arguments.contains("-h") {
    printUsage()
    exit(EXIT_SUCCESS)
}

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

if let storeKitQAEvidenceFlagIndex = arguments.firstIndex(of: "--validate-storekit-local-qa-complete") {
    let candidatePath = arguments.dropFirst(storeKitQAEvidenceFlagIndex + 1).first
    let path = candidatePath?.hasPrefix("-") == false ? candidatePath! : "AppStore/StoreKitLocalTesting.md"
    validateStoreKitLocalQAEvidenceComplete(at: path)
}

if let purchaseUIQAEvidenceFlagIndex = arguments.firstIndex(of: "--validate-purchase-ui-qa-complete") {
    let candidatePath = arguments.dropFirst(purchaseUIQAEvidenceFlagIndex + 1).first
    let path = candidatePath?.hasPrefix("-") == false ? candidatePath! : "AppStore/PurchaseUIQA.md"
    validatePurchaseUIQAEvidenceComplete(at: path)
}

if let statisticsProQAEvidenceFlagIndex = arguments.firstIndex(of: "--validate-statistics-pro-qa-complete") {
    let candidatePath = arguments.dropFirst(statisticsProQAEvidenceFlagIndex + 1).first
    let path = candidatePath?.hasPrefix("-") == false ? candidatePath! : "Liminalog/Views/Profile/docs/19-statistics-pro-gate.md"
    validateStatisticsProQAEvidenceComplete(at: path)
}

if let docsFlagIndex = arguments.firstIndex(of: "--validate-products-doc") {
    let path = arguments.dropFirst(docsFlagIndex + 1).first ?? "AppStore/PurchaseProducts.md"
    validatePurchaseProductsDocument(at: path)
}

if let monetizationDocFlagIndex = arguments.firstIndex(of: "--validate-monetization-doc") {
    let candidatePath = arguments.dropFirst(monetizationDocFlagIndex + 1).first
    let path = candidatePath?.hasPrefix("-") == false ? candidatePath! : "Liminalog/Views/Profile/docs/17-monetization.md"
    validateMonetizationDocument(at: path)
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

if let premiumDecorationUIDisconnectedFlagIndex = arguments.firstIndex(of: "--validate-premium-decoration-ui-disconnected") {
    let candidatePath = arguments.dropFirst(premiumDecorationUIDisconnectedFlagIndex + 1).first
    let path = candidatePath?.hasPrefix("-") == false ? candidatePath! : "Liminalog/Views/Profile"
    validatePremiumDecorationUIDisconnected(in: path)
}

if let safetyFlagIndex = arguments.firstIndex(of: "--validate-release-safety") {
    let path = arguments.dropFirst(safetyFlagIndex + 1).first ?? "Liminalog/Stores/PurchaseConfiguration.swift"
    validateReleaseSafetyConfiguration(at: path)
}

if let gateStateFlagIndex = arguments.firstIndex(of: "--validate-release-gate-state") {
    let candidateState = arguments.dropFirst(gateStateFlagIndex + 1).first
    guard let state = candidateState, !state.hasPrefix("-") else {
        print("error: --validate-release-gate-state requires one of: closed, gate1, gate2, gate3")
        exit(EXIT_FAILURE)
    }
    let candidatePath = arguments.dropFirst(gateStateFlagIndex + 2).first
    let path = candidatePath?.hasPrefix("-") == false ? candidatePath! : "Liminalog/Stores/PurchaseConfiguration.swift"
    validateReleaseGateConfiguration(at: path, expectedState: state)
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
    var failures: [String] = []
    var warnings: [String] = []

    if let configurationDictionary = configuration as? [String: Any],
       configurationDictionary.keys.contains("subscriptionOffersKeyPair"),
       !containsConfiguredSubscriptionOffer(in: configurationDictionary) {
        failures.append("subscriptionOffersKeyPair is present without configured subscription offers")
    }
    let allStrings = collectStrings(configuration)
    let dictionaries = collectDictionaries(configuration)

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

private func containsConfiguredSubscriptionOffer(in configuration: [String: Any]) -> Bool {
    let offerKeys = [
        "adHocOffers",
        "codeOffers",
        "introductoryOffers",
        "winbackOffers"
    ]
    return collectDictionaries(configuration).contains { dictionary in
        offerKeys.contains { key in
            guard let offers = dictionary[key] as? [Any] else { return false }
            return !offers.isEmpty
        }
    }
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

    let localizationRows = productLocalizationRows(in: text)
    if fileURL.lastPathComponent == "AppStoreConnectProductSetup.md", localizationRows.isEmpty {
        failures.append("missing App Store product localization table")
    }
    if !localizationRows.isEmpty {
        if localizationRows.count != expectedProducts.count {
            failures.append("expected \(expectedProducts.count) localization rows, found \(localizationRows.count)")
        }
        for (index, expected) in expectedProducts.enumerated() {
            guard localizationRows.indices.contains(index) else { continue }
            let row = localizationRows[index]
            if row.productID != expected.productID {
                failures.append("localization row \(index + 1) product ID mismatch: expected \(expected.productID), found \(row.productID)")
            }
            if row.displayName != expected.displayName {
                failures.append("localization row \(index + 1) display name mismatch for \(expected.productID): expected \(expected.displayName), found \(row.displayName)")
            }
            if row.description != expected.appStoreDescription {
                failures.append("localization row \(index + 1) description mismatch for \(expected.productID)")
            }
        }
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

private func validateMonetizationDocument(at path: String) -> Never {
    let fileURL = URL(fileURLWithPath: path)
    guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
        print("error: monetization document not found at \(fileURL.path)")
        exit(EXIT_FAILURE)
    }

    var failures: [String] = []
    let lifetimePrice = expectedProducts.first { $0.productID == "liminalog.lifetime" }?.referencePrice ?? "¥6,800"
    let yearlyRows = text
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
        .filter { $0.hasPrefix("| 年額サブスク |") }

    if yearlyRows.count != 1 {
        failures.append("expected one yearly subscription pricing row, found \(yearlyRows.count)")
    } else if let yearlyRow = yearlyRows.first {
        if yearlyRow.contains("入口。7日無料") || yearlyRow.contains("7日無料。") {
            failures.append("yearly subscription pricing row presents 7-day trial as decided")
        }
        if !yearlyRow.contains("無料体験は未確定") {
            failures.append("yearly subscription pricing row must keep the free-trial decision undecided")
        }
    }

    if text.contains("¥5,800") {
        failures.append("monetization document still contains stale lifetime price ¥5,800")
    }
    if !text.contains(lifetimePrice) {
        failures.append("monetization document must mention current lifetime reference price \(lifetimePrice)")
    }
    if !text.contains("無料体験：年額Proに7日無料を付けるかは未確定") {
        failures.append("monetization document must keep yearly Pro 7-day trial undecided until App Store Connect confirmation")
    }

    if failures.isEmpty {
        print("Monetization document matches current purchase product decisions.")
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

    var failures = appStoreConnectConfirmationTemplateFailures(in: text, requiresTemplateNotes: false)

    let metadata = metadataRows(in: markdownSection(named: "Confirmation Metadata", in: text))
    if isPlaceholderMetadataValue(metadata["Confirmed by"]) {
        failures.append("confirmation metadata is missing Confirmed by")
    }
    if isPlaceholderMetadataValue(metadata["Confirmation date"]) {
        failures.append("confirmation metadata is missing Confirmation date")
    }
    if metadata["App Store Connect app"] != "Liminalog" {
        failures.append("confirmation metadata App Store Connect app must be Liminalog")
    }

    for row in appStoreConnectConfirmationRows(in: text) where containsUnresolvedCompletionMarker(row.notes) {
        failures.append("confirmation product notes still contain unresolved decision text: \(row.productID)")
    }

    failures.append(contentsOf: uncheckedConfirmationRows(
        in: markdownSection(named: "Subscription Group", in: text),
        label: "subscription group"
    ))
    failures.append(contentsOf: uncheckedConfirmationRows(
        in: markdownSection(named: "Products", in: text),
        label: "product"
    ))
    failures.append(contentsOf: uncheckedConfirmationRows(
        in: markdownSection(named: "Creation Metadata", in: text),
        label: "creation metadata"
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

private func validateStoreKitLocalQAEvidenceComplete(at path: String) -> Never {
    let fileURL = URL(fileURLWithPath: path)
    guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
        print("error: StoreKit local QA evidence sheet not found at \(fileURL.path)")
        exit(EXIT_FAILURE)
    }

    let section = markdownSection(named: "6. Local StoreKit QA Evidence Sheet", in: text)
    let metadata = metadataRows(in: section)
    let evidenceRows = storeKitQAEvidenceRows(in: section)
    var rowsByCase: [String: StoreKitQAEvidenceRow] = [:]
    var duplicateCases: [String] = []
    for row in evidenceRows {
        if rowsByCase[row.caseName] != nil {
            duplicateCases.append(row.caseName)
        }
        rowsByCase[row.caseName] = row
    }
    let requiredMetadataFields = [
        "Git SHA",
        "Build",
        "Device / OS",
        "Run Path",
        "Xcode",
        "StoreKit Configuration",
        "StoreKit Config Validation",
        "DEBUG Product Diagnostics",
        "Tester",
        "Date"
    ]
    let requiredCases = [
        "商品取得",
        "Pro月額購入",
        "Pro年額購入",
        "ライフタイム購入",
        "ライフタイム後の装飾パス表示",
        "装飾パス購入",
        "支援チップ購入",
        "購入キャンセル",
        "復元なし",
        "復元あり",
        "サブスク期限切れ",
        "サブスク管理",
        "既存機能スモーク",
        "商品種別不一致防止"
    ]

    var failures: [String] = []

    for field in requiredMetadataFields {
        if isPlaceholderMetadataValue(metadata[field]) {
            failures.append("StoreKit QA metadata is missing \(field)")
        }
    }
    if metadata["StoreKit Configuration"] != "liminalog.storekit" {
        failures.append("StoreKit QA metadata StoreKit Configuration must be liminalog.storekit")
    }
    if metadata["StoreKit Config Validation"]?.lowercased() != "pass" {
        failures.append("StoreKit QA metadata StoreKit Config Validation must be pass")
    }
    if metadata["Run Path"] != "Xcode normal Run" {
        failures.append("StoreKit QA metadata Run Path must be Xcode normal Run")
    }
    if !storeKitDiagnosticsConfirmAllProductsLoaded(metadata["DEBUG Product Diagnostics"]) {
        failures.append("StoreKit QA metadata DEBUG Product Diagnostics must confirm requested 8, loaded 8, and valid 8")
    }

    if evidenceRows.count != requiredCases.count {
        failures.append("expected \(requiredCases.count) StoreKit QA evidence rows, found \(evidenceRows.count)")
    }
    for duplicateCase in duplicateCases {
        failures.append("duplicate StoreKit QA evidence case: \(duplicateCase)")
    }

    for caseName in requiredCases {
        guard let row = rowsByCase[caseName] else {
            failures.append("missing StoreKit QA evidence case: \(caseName)")
            continue
        }
        if isPlaceholderEvidenceValue(row.evidence) {
            failures.append("StoreKit QA evidence is missing concrete proof for \(caseName)")
        }
        if row.result.lowercased() != "pass" {
            failures.append("StoreKit QA result must be pass for \(caseName)")
        }
    }

    if failures.isEmpty {
        print("StoreKit local QA evidence sheet is complete.")
        exit(EXIT_SUCCESS)
    }

    for failure in failures {
        print("error: \(failure)")
    }
    exit(EXIT_FAILURE)
}

private func storeKitDiagnosticsConfirmAllProductsLoaded(_ value: String?) -> Bool {
    guard let value else { return false }
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if isPlaceholderMetadataValue(trimmedValue) || trimmedValue == "requested 8 / loaded 8 / valid 8" {
        return false
    }

    let normalized = value
        .lowercased()
        .replacingOccurrences(of: "requestedcount", with: "requested")
        .replacingOccurrences(of: "loadedcount", with: "loaded")
        .replacingOccurrences(of: "validcount", with: "valid")
        .replacingOccurrences(of: "要求id", with: "requested")
        .replacingOccurrences(of: "要求", with: "requested")
        .replacingOccurrences(of: "取得", with: "loaded")
        .replacingOccurrences(of: "有効", with: "valid")
        .replacingOccurrences(of: "：", with: ":")

    return metadataDiagnosticValue(in: normalized, label: "requested") == 8
        && metadataDiagnosticValue(in: normalized, label: "loaded") == 8
        && metadataDiagnosticValue(in: normalized, label: "valid") == 8
}

private func metadataDiagnosticValue(in text: String, label: String) -> Int? {
    let pattern = #"\b\#(label)\b\s*[:=]?\s*(\d+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return nil
    }
    let nsText = text as NSString
    let range = NSRange(location: 0, length: nsText.length)
    guard let match = regex.firstMatch(in: text, range: range) else {
        return nil
    }
    return Int(nsText.substring(with: match.range(at: 1)))
}

private func validatePurchaseUIQAEvidenceComplete(at path: String) -> Never {
    let fileURL = URL(fileURLWithPath: path)
    guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
        print("error: Purchase UI QA evidence sheet not found at \(fileURL.path)")
        exit(EXIT_FAILURE)
    }

    let section = markdownSection(named: "Gate 2 Purchase UI QA Evidence Sheet", in: text)
    let metadata = metadataRows(in: section)
    let evidenceRows = storeKitQAEvidenceRows(in: section)
    var rowsByCase: [String: StoreKitQAEvidenceRow] = [:]
    var duplicateCases: [String] = []
    for row in evidenceRows {
        if rowsByCase[row.caseName] != nil {
            duplicateCases.append(row.caseName)
        }
        rowsByCase[row.caseName] = row
    }
    let requiredMetadataFields = [
        "Git SHA",
        "Build",
        "Device / OS",
        "StoreKit Source",
        "Purchase Entry",
        "Feature Restrictions",
        "Tester",
        "Date"
    ]
    let requiredCases = [
        "Release購入入口",
        "商品取得と診断",
        "購入画面表示",
        "復元とサブスク管理",
        "既存タブスモーク",
        "既存機能の無料維持",
        "疑似課金状態リセット",
        "実機データ安全"
    ]

    var failures: [String] = []

    for field in requiredMetadataFields {
        if isPlaceholderMetadataValue(metadata[field]) {
            failures.append("Purchase UI QA metadata is missing \(field)")
        }
    }
    if metadata["Purchase Entry"]?.lowercased() != "visible" {
        failures.append("Purchase UI QA metadata Purchase Entry must be visible")
    }
    if metadata["Feature Restrictions"]?.lowercased() != "off" {
        failures.append("Purchase UI QA metadata Feature Restrictions must be off")
    }
    if metadata["Build"]?.contains("/") == true {
        failures.append("Purchase UI QA metadata Build must be a concrete build type, not the template options")
    }
    if metadata["StoreKit Source"]?.contains("/") == true {
        failures.append("Purchase UI QA metadata StoreKit Source must be a concrete source, not the template options")
    }
    if metadata["StoreKit Source"]?.lowercased() == "none" {
        failures.append("Purchase UI QA metadata StoreKit Source must not be none for Gate 2")
    }

    if evidenceRows.count != requiredCases.count {
        failures.append("expected \(requiredCases.count) Purchase UI QA evidence rows, found \(evidenceRows.count)")
    }
    for duplicateCase in duplicateCases {
        failures.append("duplicate Purchase UI QA evidence case: \(duplicateCase)")
    }

    for caseName in requiredCases {
        guard let row = rowsByCase[caseName] else {
            failures.append("missing Purchase UI QA evidence case: \(caseName)")
            continue
        }
        if isPlaceholderEvidenceValue(row.evidence) {
            failures.append("Purchase UI QA evidence is missing concrete proof for \(caseName)")
        }
        if row.result.lowercased() != "pass" {
            failures.append("Purchase UI QA result must be pass for \(caseName)")
        }
    }

    if failures.isEmpty {
        print("Purchase UI QA evidence sheet is complete.")
        exit(EXIT_SUCCESS)
    }

    for failure in failures {
        print("error: \(failure)")
    }
    exit(EXIT_FAILURE)
}

private func validateStatisticsProQAEvidenceComplete(at path: String) -> Never {
    let fileURL = URL(fileURLWithPath: path)
    guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
        print("error: Statistics Pro QA evidence sheet not found at \(fileURL.path)")
        exit(EXIT_FAILURE)
    }

    let section = markdownSection(named: "Gate 3 QA Evidence Sheet", in: text)
    let metadata = metadataRows(in: section)
    let evidenceRows = storeKitQAEvidenceRows(in: section)
    var rowsByCase: [String: StoreKitQAEvidenceRow] = [:]
    var duplicateCases: [String] = []
    for row in evidenceRows {
        if rowsByCase[row.caseName] != nil {
            duplicateCases.append(row.caseName)
        }
        rowsByCase[row.caseName] = row
    }
    let requiredMetadataFields = [
        "Git SHA",
        "Build",
        "Device / OS",
        "Tester",
        "Date",
        "Purchase Entry Point",
        "Feature Restrictions"
    ]
    let requiredCases = [
        "Release未準備",
        "購入導線ONのみ",
        "機能制限ON + 無料",
        "機能制限ON + Proサブ",
        "機能制限ON + ライフタイム",
        "機能制限ON + 装飾パスのみ",
        "無料維持機能",
        "購入画面統一",
        "回帰テスト",
        "Release build"
    ]

    var failures: [String] = []

    for field in requiredMetadataFields {
        if isPlaceholderMetadataValue(metadata[field]) {
            failures.append("Statistics Pro QA metadata is missing \(field)")
        }
    }
    if metadata["Build"]?.lowercased() != "release" {
        failures.append("Statistics Pro QA metadata Build must be Release")
    }
    if metadata["Purchase Entry Point"]?.lowercased() != "enabled" {
        failures.append("Statistics Pro QA metadata Purchase Entry Point must be enabled")
    }
    if metadata["Feature Restrictions"]?.lowercased() != "enabled" {
        failures.append("Statistics Pro QA metadata Feature Restrictions must be enabled")
    }

    if evidenceRows.count != requiredCases.count {
        failures.append("expected \(requiredCases.count) Statistics Pro QA evidence rows, found \(evidenceRows.count)")
    }
    for duplicateCase in duplicateCases {
        failures.append("duplicate Statistics Pro QA evidence case: \(duplicateCase)")
    }

    for caseName in requiredCases {
        guard let row = rowsByCase[caseName] else {
            failures.append("missing Statistics Pro QA evidence case: \(caseName)")
            continue
        }
        if isPlaceholderEvidenceValue(row.evidence) {
            failures.append("Statistics Pro QA evidence is missing concrete proof for \(caseName)")
        }
        if row.result.lowercased() != "pass" {
            failures.append("Statistics Pro QA result must be pass for \(caseName)")
        }
    }

    if failures.isEmpty {
        print("Statistics Pro QA evidence sheet is complete.")
        exit(EXIT_SUCCESS)
    }

    for failure in failures {
        print("error: \(failure)")
    }
    exit(EXIT_FAILURE)
}

private func appStoreConnectConfirmationTemplateFailures(
    in text: String,
    requiresTemplateNotes: Bool = true
) -> [String] {
    let rows = appStoreConnectConfirmationRows(in: text)
    var failures: [String] = []

    if rows.count != expectedProducts.count {
        failures.append("expected \(expectedProducts.count) confirmation product rows, found \(rows.count)")
    }

    let confirmationMetadataSection = markdownSection(named: "Confirmation Metadata", in: text)
    let requiredConfirmationMetadataFields = [
        "Confirmed by",
        "Confirmation date",
        "App Store Connect app",
        "Notes"
    ]
    if confirmationMetadataSection.isEmpty {
        failures.append("missing confirmation metadata")
    }
    for field in requiredConfirmationMetadataFields where !confirmationMetadataSection.contains(field) {
        failures.append("missing confirmation metadata row: \(field)")
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
        if requiresTemplateNotes && row.notes != appStoreConnectNotes(for: expected) {
            failures.append("confirmation row \(index + 1) notes mismatch for \(expected.productID)")
        }
    }

    if !text.contains("Group Reference Name") || !text.contains("Liminalog Pro") {
        failures.append("missing Liminalog Pro subscription group confirmation")
    }
    let subscriptionGroupSection = markdownSection(named: "Subscription Group", in: text)
    let requiredSubscriptionGroupChecks = [
        "Group Reference Name",
        "Contains Products",
        "Subscription Relationship"
    ]
    for check in requiredSubscriptionGroupChecks where !subscriptionGroupSection.contains(check) {
        failures.append("missing subscription group confirmation row: \(check)")
    }

    let creationMetadataSection = markdownSection(named: "Creation Metadata", in: text)
    let requiredCreationMetadataChecks = [
        "Product Edit Permission",
        "Product Metadata",
        "Introductory Offer Decision",
        "Review Information",
        "Sandbox Propagation"
    ]
    if creationMetadataSection.isEmpty {
        failures.append("missing creation metadata confirmation")
    }
    for check in requiredCreationMetadataChecks where !creationMetadataSection.contains(check) {
        failures.append("missing creation metadata confirmation row: \(check)")
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

private func validatePremiumDecorationUIDisconnected(in path: String) -> Never {
    let rootURL = URL(fileURLWithPath: path)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        print("error: premium decoration UI scan root not found at \(rootURL.path)")
        exit(EXIT_FAILURE)
    }

    let forbiddenTokens = [
        "PremiumDecorationCatalog",
        "PremiumDecorationAccessPolicy",
        "PremiumDecorationEquippingPolicy",
        "DecorationAccessDisplayPolicy",
        "DecorationAccessDisplayState",
        "DecorationAccessDisplayItem",
        "liminalog.decoration."
    ]
    let swiftFiles = swiftSourceFiles(in: rootURL)
    var failures: [String] = []

    if swiftFiles.isEmpty {
        failures.append("no Swift files found under \(rootURL.path)")
    }

    for fileURL in swiftFiles {
        guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else {
            failures.append("could not read \(fileURL.path)")
            continue
        }
        let matchedTokens = forbiddenTokens.filter(source.contains)
        guard !matchedTokens.isEmpty else { continue }

        let relativePath = fileURL.path.replacingOccurrences(of: FileManager.default.currentDirectoryPath + "/", with: "")
        failures.append("premium decoration UI is connected in \(relativePath): \(matchedTokens.joined(separator: ", "))")
    }

    if failures.isEmpty {
        print("Premium decoration UI remains disconnected under \(path).")
        exit(EXIT_SUCCESS)
    }

    for failure in failures {
        print("error: \(failure)")
    }
    exit(EXIT_FAILURE)
}

private func validateReleaseSafetyConfiguration(at path: String) -> Never {
    validateReleaseGateConfiguration(at: path, expectedState: "closed")
}

private func validateReleaseGateConfiguration(at path: String, expectedState: String) -> Never {
    let fileURL = URL(fileURLWithPath: path)
    guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
        print("error: purchase configuration source not found at \(fileURL.path)")
        exit(EXIT_FAILURE)
    }

    guard let currentConfiguration = purchaseConfigurationCurrentBlock(in: text) else {
        print("error: could not locate PurchaseConfiguration.current in \(fileURL.path)")
        exit(EXIT_FAILURE)
    }

    let expectedGate = ReleaseGateExpectation(rawValue: expectedState)
    guard let expectedGate else {
        print("error: unknown release gate state: \(expectedState)")
        print("error: expected one of: closed, gate1, gate2, gate3")
        exit(EXIT_FAILURE)
    }

    let requiredSnippets = expectedGate.requiredSnippets

    let failures = requiredSnippets.compactMap { requirement -> String? in
        currentConfiguration.contains(requirement.snippet)
            ? nil
            : "missing expected release gate setting for \(expectedGate.displayName): \(requirement.label) (expected `\(requirement.snippet)`)"
    }

    if failures.isEmpty {
        print("Release purchase configuration matches expected state: \(expectedGate.displayName).")
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

    var failures: [String] = []

    if !text.contains("StoreKitConfigurationFileReference") {
        failures.append("missing scheme setting: StoreKit configuration reference")
    }

    let acceptedIdentifiers = [
        #"identifier = "container:liminalog.storekit""#,
        #"identifier = "../../liminalog.storekit""#
    ]
    if !acceptedIdentifiers.contains(where: text.contains) {
        failures.append("missing scheme setting: liminalog.storekit scheme link")
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

private func swiftSourceFiles(in rootURL: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else { return [] }

    return enumerator.compactMap { entry -> URL? in
        guard let fileURL = entry as? URL, fileURL.pathExtension == "swift" else {
            return nil
        }
        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile == true ? fileURL : nil
    }
    .sorted { $0.path < $1.path }
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

private struct ProductLocalizationRow {
    var productID: String
    var displayName: String
    var description: String
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

private struct StoreKitQAEvidenceRow {
    var caseName: String
    var requiredResult: String
    var evidence: String
    var result: String
    var notes: String
}

private enum ReleaseGateExpectation: String {
    case closed
    case gate1
    case gate2
    case gate3

    var displayName: String {
        switch self {
        case .closed:
            return "closed"
        case .gate1:
            return "gate1 metadata ready"
        case .gate2:
            return "gate2 purchase entry point ready"
        case .gate3:
            return "gate3 feature restrictions ready"
        }
    }

    var requiredSnippets: [(label: String, snippet: String)] {
        switch self {
        case .closed:
            return commonProductSnippets + [
                ("App Store Connect product confirmation remains off", "productIDsAreConfirmedForAppStoreConnect: false"),
                ("subscription group remains unset", "subscriptionGroupName: nil"),
                ("terms URL points to the published LP", #"termsOfUseURL: URL(string: "https://liminalog-lp.vercel.app/terms")"#),
                privacyURLSnippet,
                ("purchase entry point remains off", "purchaseEntryPointIsEnabled: false"),
                ("feature restrictions remain off", "featureRestrictionsAreEnabled: false"),
                ("background entitlement refresh remains off", "backgroundEntitlementRefreshIsEnabled: false")
            ]
        case .gate1:
            return metadataReadySnippets + [
                ("purchase entry point remains off for Gate 1", "purchaseEntryPointIsEnabled: false"),
                ("feature restrictions remain off for Gate 1", "featureRestrictionsAreEnabled: false"),
                ("background entitlement refresh remains off for Gate 1", "backgroundEntitlementRefreshIsEnabled: false")
            ]
        case .gate2:
            return metadataReadySnippets + [
                ("purchase entry point is enabled for Gate 2", "purchaseEntryPointIsEnabled: true"),
                ("feature restrictions remain off for Gate 2", "featureRestrictionsAreEnabled: false"),
                ("background entitlement refresh is enabled for Gate 2", "backgroundEntitlementRefreshIsEnabled: true")
            ]
        case .gate3:
            return metadataReadySnippets + [
                ("purchase entry point is enabled for Gate 3", "purchaseEntryPointIsEnabled: true"),
                ("feature restrictions are enabled for Gate 3", "featureRestrictionsAreEnabled: true"),
                ("background entitlement refresh is enabled for Gate 3", "backgroundEntitlementRefreshIsEnabled: true")
            ]
        }
    }

    private var commonProductSnippets: [(label: String, snippet: String)] {
        [
            ("StoreKit product IDs remain code-owned", "productIDs: PurchaseProductID.storeKitProductIDs")
        ]
    }

    private var metadataReadySnippets: [(label: String, snippet: String)] {
        commonProductSnippets + [
            ("App Store Connect product confirmation is on", "productIDsAreConfirmedForAppStoreConnect: true"),
            ("subscription group is configured", #"subscriptionGroupName: "Liminalog Pro""#),
            ("terms URL points to the published LP", #"termsOfUseURL: URL(string: "https://liminalog-lp.vercel.app/terms")"#),
            privacyURLSnippet
        ]
    }

    private var privacyURLSnippet: (label: String, snippet: String) {
        ("privacy URL points to the published LP", #"privacyPolicyURL: URL(string: "https://liminalog-lp.vercel.app/privacy")"#)
    }
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

private func productLocalizationRows(in markdown: String) -> [ProductLocalizationRow] {
    markdownSection(named: "App Store Localization", in: markdown)
        .split(separator: "\n", omittingEmptySubsequences: false)
        .compactMap { rawLine -> ProductLocalizationRow? in
            let line = String(rawLine)
            guard line.hasPrefix("| `liminalog.") else { return nil }
            let columns = line
                .split(separator: "|", omittingEmptySubsequences: false)
                .dropFirst()
                .dropLast()
                .map { normalizeMarkdownCell(String($0)) }
            guard columns.count == 3 else { return nil }
            return ProductLocalizationRow(
                productID: columns[0],
                displayName: columns[1],
                description: columns[2]
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

private func storeKitQAEvidenceRows(in markdown: String) -> [StoreKitQAEvidenceRow] {
    markdown
        .split(separator: "\n", omittingEmptySubsequences: false)
        .compactMap { rawLine -> StoreKitQAEvidenceRow? in
            let line = String(rawLine)
            guard line.hasPrefix("| "), !line.contains("---") else { return nil }
            let columns = line
                .split(separator: "|", omittingEmptySubsequences: false)
                .dropFirst()
                .dropLast()
                .map { normalizeMarkdownCell(String($0)) }
            guard columns.count == 5, columns[0] != "Case" else { return nil }
            return StoreKitQAEvidenceRow(
                caseName: columns[0],
                requiredResult: columns[1],
                evidence: columns[2],
                result: columns[3],
                notes: columns[4]
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

private func isPlaceholderMetadataValue(_ value: String?) -> Bool {
    guard let value else { return true }
    let normalized = normalizeMarkdownCell(value).lowercased()
    if normalized.isEmpty {
        return true
    }

    let placeholderValues: Set<String> = [
        "fill manually",
        "tbd",
        "todo",
        "-"
    ]
    return placeholderValues.contains(normalized)
        || normalized.contains("fill manually")
}

private func isPlaceholderEvidenceValue(_ value: String) -> Bool {
    let normalized = normalizeMarkdownCell(value).lowercased()
    if normalized.isEmpty {
        return true
    }

    let placeholderValues: Set<String> = [
        "screenshot / note",
        "command output",
        "fill manually",
        "tbd",
        "todo",
        "-"
    ]
    return placeholderValues.contains(normalized)
        || normalized.contains("fill manually")
}

private func containsUnresolvedCompletionMarker(_ value: String) -> Bool {
    let normalized = normalizeMarkdownCell(value).lowercased()
    return normalized.contains("未確定")
        || normalized.contains("tbd")
        || normalized.contains("todo")
        || normalized.contains("fill manually")
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
      swift Scripts/validate-storekit-config.swift --validate-storekit-local-qa-complete [path-to-StoreKitLocalTesting.md]
      swift Scripts/validate-storekit-config.swift --validate-purchase-ui-qa-complete [path-to-PurchaseUIQA.md]
      swift Scripts/validate-storekit-config.swift --validate-statistics-pro-qa-complete [path-to-19-statistics-pro-gate.md]
      swift Scripts/validate-storekit-config.swift --validate-products-doc [path-to-PurchaseProducts.md]
      swift Scripts/validate-storekit-config.swift --validate-monetization-doc [path-to-17-monetization.md]
      swift Scripts/validate-storekit-config.swift --validate-product-source [path-to-PurchaseProduct.swift]
      swift Scripts/validate-storekit-config.swift --validate-premium-decoration-products-doc [path-to-PurchaseProducts.md]
      swift Scripts/validate-storekit-config.swift --validate-premium-decoration-inactive [path-to-liminalog.storekit]
      swift Scripts/validate-storekit-config.swift --validate-premium-decoration-ui-disconnected [path-to-profile-views]
      swift Scripts/validate-storekit-config.swift --validate-release-safety [path-to-PurchaseConfiguration.swift]
      swift Scripts/validate-storekit-config.swift --validate-release-gate-state <closed|gate1|gate2|gate3> [path-to-PurchaseConfiguration.swift]
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
    print("Product ID\tReference Name\tType\tReference Price\tSubscription Group\tDisplay Name\tDescription\tIntroductory Offer\tNotes")
    for product in expectedProducts {
        let group = product.subscriptionGroup ?? "-"
        let notes = appStoreConnectNotes(for: product)
        print("\(product.productID)\t\(product.displayName)\t\(product.kind)\t\(product.referencePrice)\t\(group)\t\(product.displayName)\t\(product.appStoreDescription)\t\(product.introductoryOffer)\t\(notes)")
    }
}

private func printAppStoreConnectConfirmationMarkdown() {
    print("""
    # App Store Connect Product Confirmation

    App Store Connect で課金商品を作成した後に埋める確認表。すべて確認できるまで `PurchaseConfiguration.current.productIDsAreConfirmedForAppStoreConnect` は `true` にしない。

    ## Source Of Truth

    - 商品ID、表示名、種別、価格、サブスクリプショングループの転記元は `PurchaseProductID.appStoreConnectSpecifications`。
    - この表の構造は `Scripts/validate-storekit-config.swift --validate-app-store-connect-confirmation-template` で検査する。
    - App Store Connect 作成後、Gate 1 に進む直前に `Scripts/validate-storekit-config.swift --validate-app-store-connect-confirmation-complete` を通す。
    - 完了検査では `fill manually`、`TBD`、`TODO`、`未確定` が残っている確認表を未完了扱いにする。
    - 単品プレミアム装飾は `AppStore/PurchaseProducts.md` の別表を使う。購入UIに入れない段階では `PurchaseConfiguration.current.productIDs` に追加しない。

    ## Confirmation Metadata

    | Field | Value |
    |---|---|
    | Confirmed by |  |
    | Confirmation date |  |
    | App Store Connect app | Liminalog |
    | Notes |  |

    ## Subscription Group

    | Check | Field | Expected |
    |---|---|---|
    | [ ] | Group Reference Name | `Liminalog Pro` |
    | [ ] | Contains Products | Proサブと装飾パスが同じグループに入っている |
    | [ ] | Subscription Relationship | 同じグループ内の代替プランとして、Proサブと装飾パスの期間、表示順、レベル/アップグレード関係が意図と矛盾しない |

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

    ## Creation Metadata

    | Check | Field | Expected |
    |---|---|---|
    | [ ] | Product Edit Permission | The App Store Connect account used for setup can add and edit in-app purchase products |
    | [ ] | Product Metadata | Display names, descriptions, durations, prices, and availability are filled for all App Store Connect products |
    | [ ] | Introductory Offer Decision | 年額Proの無料体験を付ける/付けないを確定し、付ける場合はアプリ内文言とQA表も同時更新している |
    | [ ] | Review Information | Review screenshot and review notes are attached for products submitted to App Review |
    | [ ] | Sandbox Propagation | After metadata edits, allow up to 1 hour before treating Sandbox product fetch failures as app bugs |

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
