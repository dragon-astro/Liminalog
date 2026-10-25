#if DEBUG
import Foundation
import SwiftData

@MainActor
extension PreviewSupport {
    /// Opt-in development data. A completed import is not repeated after the user
    /// renames or deletes a sample. Previews and isolated tests can omit defaults.
    @discardableResult
    static func seedEditingSamplesIfNeeded(in context: ModelContext, defaults: UserDefaults? = .standard) -> Bool {
        let importKey = "LiminalogDebugEditingSamples.v1"
        guard defaults?.bool(forKey: importKey) != true else { return false }
        let categoryStore = CategoryStore(modelContext: context)
        _ = CategorySetStore(modelContext: context, categoryStore: categoryStore).seedDefaultCategorySetsIfNeeded()
        do {
            var categories = try context.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortOrder)]))
            var sets = try context.fetch(FetchDescriptor<CategorySet>(sortBy: [SortDescriptor(\.sortOrder)]))
            var presets = try context.fetch(FetchDescriptor<PlanPreset>(sortBy: [SortDescriptor(\.sortOrder)]))
            var days = try context.fetch(FetchDescriptor<DayPreset>(sortBy: [SortDescriptor(\.sortOrder)]))
            let categorySpecs = [
                ("運動", "#269C88", "figure.run"), ("食事", "#D68A35", "fork.knife"),
                ("買い物", "#BC739B", "basket.fill"), ("読書", "#668BBC", "books.vertical.fill"),
                ("通院", "#D16C77", "cross.case.fill"), ("交流", "#CB9560", "person.2.fill"),
                ("創作", "#9A76C1", "paintbrush.pointed.fill"), ("片付け", "#579DA3", "archivebox.fill")
            ]
            for (name, hex, icon) in categorySpecs where !categories.contains(where: { $0.name == name }) {
                let category = Category(name: name, colorHex: hex, icon: icon,
                    sortOrder: (categories.map(\.sortOrder).max() ?? -1) + 1)
                context.insert(category)
                categories.append(category)
            }
            let byName = Dictionary(categories.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
            let boards = [
                ("からだと暮らし", ["睡眠", "食事", "運動", "通院", "休憩", "買い物", "家事", "片付け"]),
                ("学びと創作", ["勉強", "読書", "創作", "仕事", "趣味", "交流", "移動", "自由時間"])
            ]
            for (name, names) in boards where !sets.contains(where: { $0.name == name }) {
                let set = CategorySet(name: name, sortOrder: (sets.map(\.sortOrder).max() ?? -1) + 1,
                    slots: names.map { byName[$0]?.id })
                context.insert(set)
                sets.append(set)
            }
            func snapshot(_ title: String, _ category: String, _ start: Int, _ end: Int,
                          memo: Bool = false, allDay: Bool = false, important: Bool = false) -> PlanTemplateSnapshot {
                PlanTemplateSnapshot(title: title, categoryID: byName[category]?.id,
                    startMinute: start, endMinute: end, isAllDay: allDay, isImportant: important,
                    isPublic: false, isMemo: memo)
            }
            let planSamples: [(PlanTemplateSnapshot, PlanPresetPlacementMode)] = [
                (snapshot("通勤", "移動", 480, 540), .fixedTime),
                (snapshot("集中作業", "仕事", 540, 660), .fixedTime),
                (snapshot("昼休み", "食事", 720, 780), .fixedTime),
                (snapshot("勉強", "勉強", 1140, 1200), .duration),
                (snapshot("読書", "読書", 1200, 1230), .duration),
                (snapshot("朝の運動", "運動", 420, 450), .duration),
                (snapshot("ジム", "運動", 1080, 1170), .duration),
                (snapshot("買い物", "買い物", 1020, 1065), .duration),
                (snapshot("掃除", "家事", 540, 570), .duration),
                (snapshot("友達とごはん", "交流", 1080, 1200), .fixedTime),
                (snapshot("通院", "通院", 900, 960, important: true), .fixedTime),
                (snapshot("休日", "自由時間", 0, 1440, allDay: true), .fixedTime),
                (snapshot("宅配の受け取り", "買い物", 600, 720, memo: true), .fixedTime),
                (snapshot("折り返しの電話", "交流", 780, 795, memo: true), .duration),
                (snapshot("持ち物チェック", "家事", 465, 480, memo: true), .fixedTime),
                (snapshot("散歩", "運動", 960, 990), .duration)
            ]
            for (item, mode) in planSamples where !presets.contains(where: { $0.name == item.title }) {
                let preset = PlanPreset(name: item.title, title: item.title, categoryID: item.categoryID,
                    startMinute: item.startMinute, endMinute: item.endMinute, isAllDay: item.isAllDay,
                    isImportant: item.isImportant, isPublic: false, placementMode: mode,
                    sortOrder: (presets.map(\.sortOrder).max() ?? -1) + 1)
                context.insert(preset)
                presets.append(preset)
            }
            let daySamples: [(String, String, String, [PlanTemplateSnapshot])] = [
                ("平日のルーティン", "#668BBC", "briefcase.fill", [
                    snapshot("朝の準備", "家事", 420, 480), snapshot("通勤", "移動", 480, 540),
                    snapshot("午前の仕事", "仕事", 540, 720), snapshot("昼休み", "食事", 720, 780),
                    snapshot("午後の仕事", "仕事", 780, 1020), snapshot("帰宅", "移動", 1020, 1080),
                    snapshot("夕食", "食事", 1140, 1200), snapshot("読書", "読書", 1260, 1290)]),
                ("在宅で集中", "#9A76C1", "laptopcomputer", [
                    snapshot("朝の散歩", "運動", 480, 510), snapshot("集中作業", "仕事", 540, 720),
                    snapshot("昼休み", "食事", 720, 780), snapshot("制作", "創作", 780, 900),
                    snapshot("休憩", "休憩", 900, 930), snapshot("仕上げ", "仕事", 930, 1020),
                    snapshot("宅配の受け取り", "買い物", 600, 720, memo: true)]),
                ("学習メインの一日", "#2F80ED", "book.closed.fill", [
                    snapshot("予習", "勉強", 540, 630), snapshot("休憩", "休憩", 630, 660),
                    snapshot("課題", "勉強", 660, 720), snapshot("昼食", "食事", 720, 780),
                    snapshot("図書館で読書", "読書", 780, 900), snapshot("運動", "運動", 960, 1020),
                    snapshot("復習", "勉強", 1140, 1200)]),
                ("ゆっくり休日", "#269C88", "cup.and.saucer.fill", [
                    snapshot("朝ごはん", "食事", 540, 600), snapshot("片付け", "片付け", 600, 660),
                    snapshot("お昼ごはん", "食事", 720, 780), snapshot("好きなこと", "趣味", 780, 960),
                    snapshot("買い物", "買い物", 960, 1020), snapshot("夕食", "食事", 1140, 1200)]),
                ("お出かけの日", "#D68A35", "tram.fill", [
                    snapshot("支度", "家事", 420, 480), snapshot("移動", "移動", 480, 600),
                    snapshot("街歩き", "趣味", 600, 720), snapshot("ランチ", "食事", 720, 780),
                    snapshot("友達と過ごす", "交流", 780, 1020), snapshot("帰りの移動", "移動", 1020, 1140),
                    snapshot("持ち物チェック", "家事", 450, 465, memo: true)])
            ]
            for (name, color, icon, items) in daySamples where !days.contains(where: { $0.name == name }) {
                let day = DayPreset(name: name, itemsData: try DayPresetItemsCodec.encode(items),
                    itemCount: items.count, colorHex: color, icon: icon,
                    sortOrder: (days.map(\.sortOrder).max() ?? -1) + 1)
                context.insert(day)
                days.append(day)
            }
            try context.save()
            defaults?.set(true, forKey: importKey)
            return true
        } catch {
            context.rollback()
            NSLog("Liminalog: skipped editing sample import: \(error)")
            return false
        }
    }
}
#endif
