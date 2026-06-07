#if DEBUG
import Foundation
import SwiftData

@MainActor
extension PreviewSupport {
    static let devDataFlagKey = "LiminalogSeedDevData"
    static let previewDataFlagKey = "LiminalogSeedPreviewData"

    struct RuntimeSeedRequest: Equatable {
        var shouldSeedPreviewPlans: Bool
        var shouldSeedDevData: Bool
    }

    static func runtimeSeedRequest(
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RuntimeSeedRequest {
        let shouldSeedDevData = runtimeFlagEnabled(
            devDataFlagKey,
            defaults: defaults,
            arguments: arguments,
            environment: environment
        )
        let shouldSeedPreviewPlans = shouldSeedDevData || runtimeFlagEnabled(
            previewDataFlagKey,
            defaults: defaults,
            arguments: arguments,
            environment: environment
        )

        return RuntimeSeedRequest(
            shouldSeedPreviewPlans: shouldSeedPreviewPlans,
            shouldSeedDevData: shouldSeedDevData
        )
    }

    @discardableResult
    static func seedPreviewPlansIfNeeded(
        in modelContext: ModelContext,
        clock: any LiminalogClock = SystemClock()
    ) -> Bool {
        let categoryStore = CategoryStore(modelContext: modelContext)
        let categorySetStore = CategorySetStore(modelContext: modelContext, categoryStore: categoryStore)
        let planStore = PlanStore(modelContext: modelContext, clock: clock)
        let didBootstrapCategories = categorySetStore.seedDefaultCategorySetsIfNeeded()

        let calendar = Calendar.current
        let today = DayBoundary.dayStart(for: clock.now, calendar: calendar)
        guard let month = monthInterval(containing: today, calendar: calendar) else {
            return didBootstrapCategories
        }

        let seedInterval = expandedInterval(month, leadingDays: 1, trailingDays: 1, calendar: calendar) ?? month
        guard let seedPlans = planStore.plannedBlocksIfAvailable(from: seedInterval.start, to: seedInterval.end),
              let allCategories = categoryStore.allCategoriesIfAvailable()
        else {
            NSLog("Liminalog: skipped preview plan seed because existing data could not be fetched")
            return didBootstrapCategories
        }
        let debugSeedPlans = seedPlans.filter(Self.isDebugPreviewPlan)
        let hasCurrentSeedVersion = UserDefaults.standard.integer(forKey: previewPlanSeedVersionKey) >= currentPreviewPlanSeedVersion

        if hasCurrentSeedVersion && monthHasCompleteShowcasePlans(debugSeedPlans, in: seedInterval, calendar: calendar) {
            return didBootstrapCategories
        }

        let categories = categoryLookupByName(allCategories)

        for plan in debugSeedPlans {
            modelContext.delete(plan)
        }

        for day in days(in: seedInterval, calendar: calendar) {
            for (index, segment) in previewPlanSegments(for: day, calendar: calendar) {
                guard
                    let category = categories[segment.categoryName],
                    let start = calendar.date(byAdding: .minute, value: segment.startMinute, to: day),
                    let end = calendar.date(byAdding: .minute, value: segment.durationMinutes, to: start)
                else { continue }

                let plan = PlanBlock(
                    category: category,
                    title: segment.title,
                    startTime: start,
                    endTime: end,
                    isImportant: segment.isImportant,
                    note: segment.note,
                    isPublic: true
                )
                plan.sourceEventID = "debug.preview.plan.\(dateKey(for: day, calendar: calendar)).\(index)"
                modelContext.insert(plan)
            }
        }

        insertShowcaseImportantPlans(monthStart: month.start, calendar: calendar, categories: categories, in: modelContext)

        guard save(modelContext) else { return didBootstrapCategories }
        UserDefaults.standard.set(currentPreviewPlanSeedVersion, forKey: previewPlanSeedVersionKey)
        return true
    }

    @discardableResult
    static func seedDevSampleChaptersIfNeeded(
        in modelContext: ModelContext,
        clock: any LiminalogClock = SystemClock()
    ) -> Bool {
        let categoryStore = CategoryStore(modelContext: modelContext)
        let didBootstrapCategories = categoryStore.seedDefaultCategoriesIfNeeded()

        let calendar = Calendar.current
        let now = clock.now
        let today = DayBoundary.dayStart(for: now, calendar: calendar)
        let todayKey = dateKey(for: today, calendar: calendar)
        guard let month = monthInterval(containing: today, calendar: calendar) else {
            return didBootstrapCategories
        }
        let seedInterval = expandedInterval(month, leadingDays: 1, trailingDays: 1, calendar: calendar) ?? month

        let chapterDescriptor = FetchDescriptor<Chapter>()
        let existingChapters: [Chapter]
        do {
            existingChapters = try modelContext.fetch(chapterDescriptor)
        } catch {
            NSLog("Liminalog: skipped dev chapter seed because existing chapters could not be fetched: \(String(describing: error))")
            return didBootstrapCategories
        }
        let existingDebugChapters = existingChapters.filter(Self.isDebugDevChapter)
        let hasCurrentSeedVersion = UserDefaults.standard.integer(
            forKey: devSampleChapterSeedVersionKey
        ) >= currentDevSampleChapterSeedVersion
        let hasCurrentAnchorDay = UserDefaults.standard.string(
            forKey: devSampleChapterSeedAnchorDayKey
        ) == todayKey

        if hasCurrentSeedVersion && hasCurrentAnchorDay && !existingDebugChapters.isEmpty {
            return didBootstrapCategories
        }

        if !existingDebugChapters.isEmpty {
            existingDebugChapters.forEach { modelContext.delete($0) }
            _ = save(modelContext)
        }

        guard let allCategories = categoryStore.allCategoriesIfAvailable() else {
            NSLog("Liminalog: skipped dev chapter seed because categories could not be fetched")
            return didBootstrapCategories
        }
        let categoriesByName = categoryLookupByName(allCategories)

        insertDevSleepChapters(in: seedInterval, now: now, calendar: calendar, categories: categoriesByName, into: modelContext)
        insertDevDaytimeChapters(in: seedInterval, now: now, calendar: calendar, categories: categoriesByName, into: modelContext)

        guard save(modelContext) else { return didBootstrapCategories }
        UserDefaults.standard.set(
            currentDevSampleChapterSeedVersion,
            forKey: devSampleChapterSeedVersionKey
        )
        UserDefaults.standard.set(todayKey, forKey: devSampleChapterSeedAnchorDayKey)
        return true
    }

    @discardableResult
    static func removeRuntimeSeedData(in modelContext: ModelContext) -> Bool {
        var didChange = false

        do {
            let plans = try modelContext.fetch(FetchDescriptor<PlanBlock>())
            for plan in plans where isDebugPreviewPlan(plan) {
                modelContext.delete(plan)
                didChange = true
            }
        } catch {
            NSLog("Liminalog: skipped removing preview plan seed because plans could not be fetched: \(String(describing: error))")
        }

        do {
            let chapters = try modelContext.fetch(FetchDescriptor<Chapter>())
            for chapter in chapters where isDebugDevChapter(chapter) {
                modelContext.delete(chapter)
                didChange = true
            }
        } catch {
            NSLog("Liminalog: skipped removing dev chapter seed because chapters could not be fetched: \(String(describing: error))")
        }

        UserDefaults.standard.removeObject(forKey: previewPlanSeedVersionKey)
        UserDefaults.standard.removeObject(forKey: devSampleChapterSeedVersionKey)
        UserDefaults.standard.removeObject(forKey: devSampleChapterSeedAnchorDayKey)

        guard didChange else { return false }
        return save(modelContext)
    }

    private static var previewPlanSeedVersionKey: String { "LiminalogPreviewPlanSeedVersion" }
    private static var currentPreviewPlanSeedVersion: Int { 7 }
    private static var devSampleChapterSeedVersionKey: String { "LiminalogDevSampleChapterSeedVersion" }
    private static var devSampleChapterSeedAnchorDayKey: String { "LiminalogDevSampleChapterSeedAnchorDay" }
    private static var currentDevSampleChapterSeedVersion: Int { 4 }
    private static var debugDevChapterMarker: String { "liminalog.debug.dev-chapter" }

    private static func isDebugPreviewPlan(_ plan: PlanBlock) -> Bool {
        guard let sourceEventID = plan.sourceEventID else { return false }
        return sourceEventID.hasPrefix("debug.preview.")
    }

    private static func isDebugDevChapter(_ chapter: Chapter) -> Bool {
        chapter.photoLocalIdentifier == debugDevChapterMarker
    }

    private static func runtimeFlagEnabled(
        _ key: String,
        defaults: UserDefaults,
        arguments: [String],
        environment: [String: String]
    ) -> Bool {
        if defaults.bool(forKey: key) {
            return true
        }

        if truthValue(environment[key] ?? "") == true {
            return true
        }

        let flag = "-\(key)"
        for index in arguments.indices {
            let argument = arguments[index]

            if argument == flag {
                let nextIndex = arguments.index(after: index)
                guard nextIndex < arguments.endIndex else { return true }
                let next = arguments[nextIndex]
                guard !next.hasPrefix("-") else { return true }
                return truthValue(next) ?? true
            }

            if argument.hasPrefix("\(flag)=") {
                let value = String(argument.dropFirst(flag.count + 1))
                return truthValue(value) ?? true
            }

            if argument.hasPrefix("\(flag) ") {
                let value = String(argument.dropFirst(flag.count + 1))
                return truthValue(value) ?? true
            }
        }

        return false
    }

    private static func truthValue(_ rawValue: String) -> Bool? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on":
            true
        case "0", "false", "no", "n", "off":
            false
        default:
            nil
        }
    }

    private static func save(_ modelContext: ModelContext) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            return false
        }
    }

    private static func categoryLookupByName(_ categories: [Category]) -> [String: Category] {
        categories.reduce(into: [:]) { partialResult, category in
            partialResult[category.name] = category
        }
    }

    private static func monthInterval(containing date: Date, calendar: Calendar) -> DateInterval? {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard
            let start = calendar.date(from: components),
            let end = calendar.date(byAdding: .month, value: 1, to: start),
            end > start
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    private static func expandedInterval(_ interval: DateInterval, leadingDays: Int, trailingDays: Int, calendar: Calendar) -> DateInterval? {
        guard
            let start = calendar.date(byAdding: .day, value: -leadingDays, to: interval.start),
            let end = calendar.date(byAdding: .day, value: trailingDays, to: interval.end),
            end > start
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    private static func days(in interval: DateInterval, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var cursor = interval.start
        while cursor < interval.end {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private static func monthHasCompleteShowcasePlans(_ plans: [PlanBlock], in month: DateInterval, calendar: Calendar) -> Bool {
        let timedPlans = plans.filter { !$0.isAllDay }
        let allDaysCovered = days(in: month, calendar: calendar).allSatisfy {
            plansCoverFullDay(timedPlans, on: $0)
        }
        guard allDaysCovered else { return false }

        let hasTimedImportant = plans.contains { $0.isImportant && !$0.isAllDay }
        let hasMultiDayImportant = plans.contains {
            $0.isImportant && $0.isAllDay && $0.endTime.timeIntervalSince($0.startTime) >= 2 * 24 * 60 * 60
        }
        return hasTimedImportant && hasMultiDayImportant
    }

    private struct DemoPlanSegment {
        var categoryName: String
        var startMinute: Int
        var durationMinutes: Int
        var title: String
        var isImportant: Bool = false
        var note: String? = nil
    }

    private static func previewPlanSegments(for day: Date, calendar: Calendar) -> [(Int, DemoPlanSegment)] {
        let dayNumber = calendar.component(.day, from: day)
        let weekday = calendar.component(.weekday, from: day)
        let isWeekend = weekday == 1 || weekday == 7
        var segments = isWeekend
            ? weekendPreviewPlanSegments(dayNumber: dayNumber)
            : weekdayPreviewPlanSegments(dayNumber: dayNumber)
        applyTimedImportantOverrides(to: &segments, dayNumber: dayNumber)
        return Array(segments.enumerated())
    }

    private static func weekdayPreviewPlanSegments(dayNumber: Int) -> [DemoPlanSegment] {
        let morningFocus = dayNumber.isMultiple(of: 3) ? "仕事" : "勉強"
        let afternoonFocus = dayNumber.isMultiple(of: 2) ? "勉強" : "仕事"
        let morningTitle = morningFocus == "勉強" ? "英語と課題" : "制作作業"
        let afternoonTitle = afternoonFocus == "勉強" ? "演習と復習" : "プロダクト作業"

        return [
            DemoPlanSegment(categoryName: "睡眠", startMinute: 0, durationMinutes: 420, title: "睡眠"),
            DemoPlanSegment(categoryName: "休憩", startMinute: 420, durationMinutes: 60, title: "朝の準備"),
            DemoPlanSegment(categoryName: "移動", startMinute: 480, durationMinutes: 60, title: "移動"),
            DemoPlanSegment(categoryName: morningFocus, startMinute: 540, durationMinutes: 180, title: morningTitle),
            DemoPlanSegment(categoryName: "休憩", startMinute: 720, durationMinutes: 60, title: "昼休み"),
            DemoPlanSegment(categoryName: afternoonFocus, startMinute: 780, durationMinutes: 180, title: afternoonTitle),
            DemoPlanSegment(categoryName: "休憩", startMinute: 960, durationMinutes: 30, title: "休憩"),
            DemoPlanSegment(categoryName: "勉強", startMinute: 990, durationMinutes: 90, title: "復習"),
            DemoPlanSegment(categoryName: "移動", startMinute: 1080, durationMinutes: 60, title: "帰宅"),
            DemoPlanSegment(categoryName: "趣味", startMinute: 1140, durationMinutes: 150, title: "自由時間"),
            DemoPlanSegment(categoryName: "休憩", startMinute: 1290, durationMinutes: 60, title: "夜の休憩"),
            DemoPlanSegment(categoryName: "睡眠", startMinute: 1350, durationMinutes: 90, title: "睡眠"),
        ]
    }

    private static func weekendPreviewPlanSegments(dayNumber: Int) -> [DemoPlanSegment] {
        let afternoonCategory = dayNumber.isMultiple(of: 2) ? "趣味" : "仕事"
        let afternoonTitle = afternoonCategory == "趣味" ? "創作と散歩" : "集中制作"

        return [
            DemoPlanSegment(categoryName: "睡眠", startMinute: 0, durationMinutes: 480, title: "睡眠"),
            DemoPlanSegment(categoryName: "休憩", startMinute: 480, durationMinutes: 90, title: "朝の余白"),
            DemoPlanSegment(categoryName: "趣味", startMinute: 570, durationMinutes: 150, title: "好きなこと"),
            DemoPlanSegment(categoryName: "休憩", startMinute: 720, durationMinutes: 60, title: "昼休み"),
            DemoPlanSegment(categoryName: afternoonCategory, startMinute: 780, durationMinutes: 180, title: afternoonTitle),
            DemoPlanSegment(categoryName: "移動", startMinute: 960, durationMinutes: 60, title: "外出"),
            DemoPlanSegment(categoryName: "趣味", startMinute: 1020, durationMinutes: 120, title: "友達と予定"),
            DemoPlanSegment(categoryName: "休憩", startMinute: 1140, durationMinutes: 120, title: "夜ごはん"),
            DemoPlanSegment(categoryName: "趣味", startMinute: 1260, durationMinutes: 90, title: "リラックス"),
            DemoPlanSegment(categoryName: "睡眠", startMinute: 1350, durationMinutes: 90, title: "睡眠"),
        ]
    }

    private static func applyTimedImportantOverrides(to segments: inout [DemoPlanSegment], dayNumber: Int) {
        let highlights: [Int: (startMinute: Int, title: String, categoryName: String, note: String)] = [
            1: (1140, "THMC", "趣味", "月カレンダーで時間つき重要予定として見せるサンプル"),
            2: (780, "講師レビュー", "仕事", "週末の重要予定サンプル"),
            8: (780, "中間発表", "仕事", "重要予定が通常の24時間予定に混ざる例"),
            13: (990, "歯医者", "移動", "時間つきでも重要なら月カレンダーに表示"),
            20: (780, "遠出MTG", "仕事", "平日の大きな予定"),
            26: (1140, "デイリー共有", "趣味", "夜の短め重要予定"),
            29: (1140, "信頼関係の話", "仕事", "夕方以降の重要予定"),
            31: (780, "カメラ研修", "仕事", "月末の重要予定")
        ]
        guard let highlight = highlights[dayNumber],
              let index = segments.firstIndex(where: { $0.startMinute == highlight.startMinute })
        else { return }

        segments[index].categoryName = highlight.categoryName
        segments[index].title = highlight.title
        segments[index].isImportant = true
        segments[index].note = highlight.note
    }

    private struct DemoImportantPlan {
        var categoryName: String
        var title: String
        var startDayOffset: Int
        var endDayOffsetExclusive: Int
        var note: String
    }

    private static func insertShowcaseImportantPlans(
        monthStart: Date,
        calendar: Calendar,
        categories: [String: Category],
        in modelContext: ModelContext
    ) {
        let importantPlans = [
            DemoImportantPlan(categoryName: "趣味", title: "連休プロジェクト", startDayOffset: -2, endDayOffsetExclusive: 2, note: "月をまたぐ重要予定の表示確認"),
            DemoImportantPlan(categoryName: "休憩", title: "憲法記念日", startDayOffset: 2, endDayOffsetExclusive: 3, note: "終日の重要予定"),
            DemoImportantPlan(categoryName: "趣味", title: "こどもの日", startDayOffset: 4, endDayOffsetExclusive: 5, note: "祝日/イベントのサンプル"),
            DemoImportantPlan(categoryName: "勉強", title: "集中制作週間", startDayOffset: 7, endDayOffsetExclusive: 12, note: "週をまたぐ横長バーのサンプル"),
            DemoImportantPlan(categoryName: "移動", title: "合宿", startDayOffset: 14, endDayOffsetExclusive: 17, note: "複数日にまたがる重要予定"),
            DemoImportantPlan(categoryName: "仕事", title: "展示準備", startDayOffset: 20, endDayOffsetExclusive: 24, note: "友達共有で見せたい大きめの予定"),
            DemoImportantPlan(categoryName: "仕事", title: "リリース準備", startDayOffset: 29, endDayOffsetExclusive: 33, note: "翌月まで続く重要予定")
        ]

        for (index, important) in importantPlans.enumerated() {
            guard
                let start = calendar.date(byAdding: .day, value: important.startDayOffset, to: monthStart),
                let end = calendar.date(byAdding: .day, value: important.endDayOffsetExclusive, to: monthStart)
            else { continue }
            let plan = PlanBlock(
                category: categories[important.categoryName],
                title: important.title,
                startTime: start,
                endTime: end,
                isAllDay: true,
                isImportant: true,
                note: important.note,
                isPublic: true
            )
            plan.sourceEventID = "debug.preview.important.\(index)"
            modelContext.insert(plan)
        }
    }

    private static func plansCoverFullDay(_ plans: [PlanBlock], on date: Date) -> Bool {
        let calendar = Calendar.current
        let dayStart = DayBoundary.dayStart(for: date, calendar: calendar)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        let sorted = plans
            .filter { $0.startTime < dayEnd && $0.endTime > dayStart }
            .sorted { $0.startTime < $1.startTime }

        guard !sorted.isEmpty else { return false }
        var cursor = dayStart
        let tolerance: TimeInterval = 1

        for plan in sorted {
            let start = max(plan.startTime, dayStart)
            let end = min(plan.endTime, dayEnd)
            if start.timeIntervalSince(cursor) > tolerance {
                return false
            }
            cursor = max(cursor, end)
            if cursor >= dayEnd {
                return true
            }
        }

        return dayEnd.timeIntervalSince(cursor) <= tolerance
    }

    private struct DemoChapterSegment {
        var categoryName: String
        var startMinute: Int
        var durationMinutes: Int
        var note: String?
        var mood: String?
        var location: String?
        var isPublic: Bool
    }

    private static func insertDevSleepChapters(
        in interval: DateInterval,
        now: Date,
        calendar: Calendar,
        categories: [String: Category],
        into modelContext: ModelContext
    ) {
        guard
            let sleep = categories["睡眠"],
            let previousDay = calendar.date(byAdding: .day, value: -1, to: interval.start),
            let firstNightStart = calendar.date(byAdding: .minute, value: 22 * 60 + 30, to: previousDay)
        else { return }

        var nightStart = firstNightStart
        while nightStart < now && nightStart < interval.end {
            guard let plannedEnd = calendar.date(byAdding: .minute, value: 8 * 60 + 30, to: nightStart) else { break }
            if plannedEnd > interval.start {
                let chapter = Chapter(category: sleep, startTime: nightStart)
                chapter.endTime = plannedEnd <= now ? plannedEnd : nil
                chapter.mood = "😴"
                chapter.isPublic = false
                chapter.photoLocalIdentifier = debugDevChapterMarker
                modelContext.insert(chapter)
            }
            guard let nextNightStart = calendar.date(byAdding: .day, value: 1, to: nightStart) else { break }
            nightStart = nextNightStart
        }
    }

    private static func insertDevDaytimeChapters(
        in interval: DateInterval,
        now: Date,
        calendar: Calendar,
        categories: [String: Category],
        into modelContext: ModelContext
    ) {
        var didInsertActive = false
        for day in days(in: interval, calendar: calendar) {
            guard day <= now, !didInsertActive else { break }
            for segment in devDaytimeChapterSegments(for: day, calendar: calendar) {
                guard
                    let category = categories[segment.categoryName],
                    let start = calendar.date(byAdding: .minute, value: segment.startMinute, to: day),
                    start <= now,
                    let plannedEnd = calendar.date(byAdding: .minute, value: segment.durationMinutes, to: start)
                else { continue }

                let chapter = Chapter(category: category, startTime: start)
                chapter.endTime = plannedEnd <= now ? plannedEnd : nil
                chapter.note = segment.note
                chapter.mood = segment.mood
                chapter.locationName = segment.location
                chapter.isPublic = segment.isPublic
                chapter.photoLocalIdentifier = debugDevChapterMarker
                modelContext.insert(chapter)

                if plannedEnd > now {
                    didInsertActive = true
                    break
                }
            }
        }
    }

    private static func devDaytimeChapterSegments(for day: Date, calendar: Calendar) -> [DemoChapterSegment] {
        let dayNumber = calendar.component(.day, from: day)
        let weekday = calendar.component(.weekday, from: day)
        if weekday == 1 || weekday == 7 {
            return weekendDevDaytimeSegments(dayNumber: dayNumber)
        }
        if dayNumber.isMultiple(of: 5) {
            return driftDevDaytimeSegments(dayNumber: dayNumber)
        }
        return weekdayDevDaytimeSegments(dayNumber: dayNumber)
    }

    private static func weekdayDevDaytimeSegments(dayNumber: Int) -> [DemoChapterSegment] {
        let morningFocus = dayNumber.isMultiple(of: 3) ? "仕事" : "勉強"
        let afternoonFocus = dayNumber.isMultiple(of: 2) ? "勉強" : "仕事"
        return [
            DemoChapterSegment(categoryName: "休憩", startMinute: 420, durationMinutes: 60, note: "朝の準備", mood: nil, location: nil, isPublic: false),
            DemoChapterSegment(categoryName: "移動", startMinute: 480, durationMinutes: 60, note: nil, mood: nil, location: "電車", isPublic: true),
            DemoChapterSegment(categoryName: morningFocus, startMinute: 540, durationMinutes: 165, note: morningFocus == "勉強" ? "英語の復習" : "UI整理", mood: "💪", location: morningFocus == "勉強" ? "図書館" : nil, isPublic: true),
            DemoChapterSegment(categoryName: "移動", startMinute: 705, durationMinutes: 15, note: nil, mood: nil, location: "移動中", isPublic: true),
            DemoChapterSegment(categoryName: "休憩", startMinute: 720, durationMinutes: 60, note: "昼休み", mood: "🍱", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: afternoonFocus, startMinute: 780, durationMinutes: 180, note: afternoonFocus == "勉強" ? "演習" : "資料作成", mood: "🔥", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "休憩", startMinute: 960, durationMinutes: 30, note: "コーヒー", mood: "☕️", location: "カフェ", isPublic: false),
            DemoChapterSegment(categoryName: "勉強", startMinute: 990, durationMinutes: 90, note: "復習", mood: nil, location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "移動", startMinute: 1080, durationMinutes: 60, note: nil, mood: nil, location: "電車", isPublic: true),
            DemoChapterSegment(categoryName: "趣味", startMinute: 1140, durationMinutes: 150, note: "アプリの試作", mood: "🤩", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "休憩", startMinute: 1290, durationMinutes: 60, note: "夜の休憩", mood: nil, location: nil, isPublic: false)
        ]
    }

    private static func driftDevDaytimeSegments(dayNumber: Int) -> [DemoChapterSegment] {
        [
            DemoChapterSegment(categoryName: "休憩", startMinute: 420, durationMinutes: 75, note: "ゆっくり朝", mood: nil, location: nil, isPublic: false),
            DemoChapterSegment(categoryName: "移動", startMinute: 495, durationMinutes: 45, note: nil, mood: nil, location: "電車", isPublic: true),
            DemoChapterSegment(categoryName: "勉強", startMinute: 540, durationMinutes: 120, note: "予定より短め", mood: "📚", location: "学校", isPublic: true),
            DemoChapterSegment(categoryName: "仕事", startMinute: 660, durationMinutes: 60, note: "急ぎ対応", mood: nil, location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "休憩", startMinute: 720, durationMinutes: 90, note: "長めの昼休み", mood: "🍱", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "仕事", startMinute: 810, durationMinutes: 150, note: "作業調整", mood: "📝", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "休憩", startMinute: 960, durationMinutes: 30, note: "休憩", mood: nil, location: nil, isPublic: false),
            DemoChapterSegment(categoryName: "趣味", startMinute: 990, durationMinutes: 90, note: "予定外の制作", mood: "✨", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "移動", startMinute: 1080, durationMinutes: 60, note: nil, mood: nil, location: "電車", isPublic: true),
            DemoChapterSegment(categoryName: "勉強", startMinute: 1140, durationMinutes: 90, note: "夜の巻き返し", mood: "💪", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "休憩", startMinute: 1230, durationMinutes: 120, note: "リカバリー", mood: nil, location: nil, isPublic: false)
        ]
    }

    private static func weekendDevDaytimeSegments(dayNumber: Int) -> [DemoChapterSegment] {
        let afternoonCategory = dayNumber.isMultiple(of: 2) ? "趣味" : "仕事"
        return [
            DemoChapterSegment(categoryName: "休憩", startMinute: 420, durationMinutes: 90, note: "ゆっくり朝", mood: nil, location: nil, isPublic: false),
            DemoChapterSegment(categoryName: "趣味", startMinute: 510, durationMinutes: 150, note: "散歩と創作", mood: "✨", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "勉強", startMinute: 660, durationMinutes: 60, note: "軽い復習", mood: "📚", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "休憩", startMinute: 720, durationMinutes: 60, note: "昼休み", mood: "🍱", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: afternoonCategory, startMinute: 780, durationMinutes: 180, note: afternoonCategory == "趣味" ? "友達と予定" : "集中制作", mood: afternoonCategory == "趣味" ? "🎮" : "🔥", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "移動", startMinute: 960, durationMinutes: 60, note: nil, mood: nil, location: "街", isPublic: true),
            DemoChapterSegment(categoryName: "趣味", startMinute: 1020, durationMinutes: 120, note: "自由時間", mood: "🤩", location: nil, isPublic: true),
            DemoChapterSegment(categoryName: "休憩", startMinute: 1140, durationMinutes: 120, note: "夜ごはん", mood: nil, location: nil, isPublic: false),
            DemoChapterSegment(categoryName: "趣味", startMinute: 1260, durationMinutes: 90, note: "リラックス", mood: nil, location: nil, isPublic: true)
        ]
    }

    private static func dateKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
#endif
