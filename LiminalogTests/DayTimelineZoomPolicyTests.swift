import CoreGraphics
import Foundation
import Testing
@testable import Liminalog

@Suite("DayTimelineZoomPolicy")
struct DayTimelineZoomPolicyTests {
    @Test("対応scaleは0.75・1・1.5・2・3で基準hourHeightは38pt")
    func supportedScalesAndHourHeights() {
        #expect(DayTimelineZoomPolicy.supportedScales == [0.75, 1, 1.5, 2, 3])
        #expect(DayTimelineZoomPolicy.defaultScale == 1)
        #expect(DayTimelineZoomPolicy.baseHourHeight == 38)
        #expect(DayTimelineZoomPolicy.hourHeight(for: 0.75) == 28.5)
        #expect(DayTimelineZoomPolicy.hourHeight(for: 1) == 38)
        #expect(DayTimelineZoomPolicy.hourHeight(for: 1.5) == 57)
        #expect(DayTimelineZoomPolicy.hourHeight(for: 2) == 76)
        #expect(DayTimelineZoomPolicy.hourHeight(for: 3) == 114)
    }

    @Test("共通zoom計算は週間の29pt基準にも再利用できる")
    func sharedPolicySupportsWeekHourHeight() {
        #expect(TimelineZoomPolicy.weekBaseHourHeight == 29)
        #expect(TimelineZoomPolicy.hourHeight(for: 0.75, base: 29) == 21.75)
        #expect(TimelineZoomPolicy.hourHeight(for: 1, base: 29) == 29)
        #expect(TimelineZoomPolicy.hourHeight(for: 2, base: 29) == 58)
        #expect(TimelineZoomPolicy.hourHeight(for: 3, base: 29) == 87)
        #expect(TimelineZoomPolicy.weekUserDefaultsKey != TimelineZoomPolicy.userDefaultsKey)
    }

    @Test("非有限・不正値は1へ戻し未知の有限値は最寄りへ丸める")
    func normalizesInvalidAndUnknownScales() {
        #expect(DayTimelineZoomPolicy.normalizedScale(.nan) == 1)
        #expect(DayTimelineZoomPolicy.normalizedScale(.infinity) == 1)
        #expect(DayTimelineZoomPolicy.normalizedScale(-1) == 1)
        #expect(DayTimelineZoomPolicy.normalizedScale(0) == 1)
        #expect(DayTimelineZoomPolicy.normalizedScale(0.8) == 0.75)
        #expect(DayTimelineZoomPolicy.normalizedScale(1.4) == 1.5)
        #expect(DayTimelineZoomPolicy.normalizedScale(1.8) == 2)
        #expect(DayTimelineZoomPolicy.normalizedScale(1.25) == 1)
    }

    @Test("pinch中は連続値を許し対応範囲の上下端でclampする")
    func clampsScaleDuringMagnification() {
        #expect(DayTimelineZoomPolicy.magnifiedScale(baseScale: 1, magnification: 1.2) == 1.2)
        #expect(DayTimelineZoomPolicy.magnifiedScale(baseScale: 1.5, magnification: 2) == 3)
        #expect(DayTimelineZoomPolicy.magnifiedScale(baseScale: 1, magnification: 0.2) == 0.75)
        #expect(DayTimelineZoomPolicy.magnifiedScale(baseScale: 1.5, magnification: .nan) == 1.5)
    }

    @Test("pinch終了時は最寄りの対応scaleへsnapする")
    func snapsToNearestSupportedScale() {
        #expect(DayTimelineZoomPolicy.snappedScale(0.9) == 1)
        #expect(DayTimelineZoomPolicy.snappedScale(1.35) == 1.5)
        #expect(DayTimelineZoomPolicy.snappedScale(1.9) == 2)
        #expect(DayTimelineZoomPolicy.snappedScale(2.6) == 3)
        #expect(DayTimelineZoomPolicy.snappedScale(.infinity) == 1)
    }

    @Test("iPhone 13相当viewportで全tier間のscale変更が中央時刻を保つ")
    func preservesCenterMinuteAcrossEveryTierTransition() {
        let viewportHeight: CGFloat = 560
        let topInset: CGFloat = 30
        let expectedCenter: CGFloat = 713.25
        let transitions = DayTimelineZoomPolicy.supportedScales.flatMap { sourceScale in
            DayTimelineZoomPolicy.supportedScales.compactMap { destinationScale in
                sourceScale == destinationScale ? nil : (sourceScale, destinationScale)
            }
        }
        #expect(transitions.count == 20)

        for (sourceScale, destinationScale) in transitions {
            let sourceHourHeight = DayTimelineZoomPolicy.hourHeight(for: sourceScale)
            let sourceScrollY = DayTimelineZoomPolicy.scrollY(
                preservingCenterMinute: expectedCenter,
                viewportHeight: viewportHeight,
                hourHeight: sourceHourHeight,
                contentHeight: contentHeight(hourHeight: sourceHourHeight),
                timelineTopInset: topInset
            )
            let sourceCenter = DayTimelineZoomPolicy.centerMinute(
                visibleMinY: -sourceScrollY,
                viewportHeight: viewportHeight,
                hourHeight: sourceHourHeight,
                timelineTopInset: topInset
            )

            let destinationHourHeight = DayTimelineZoomPolicy.hourHeight(for: destinationScale)
            let destinationScrollY = DayTimelineZoomPolicy.scrollY(
                preservingCenterMinute: sourceCenter,
                viewportHeight: viewportHeight,
                hourHeight: destinationHourHeight,
                contentHeight: contentHeight(hourHeight: destinationHourHeight),
                timelineTopInset: topInset
            )
            let restoredCenter = DayTimelineZoomPolicy.centerMinute(
                visibleMinY: -destinationScrollY,
                viewportHeight: viewportHeight,
                hourHeight: destinationHourHeight,
                timelineTopInset: topInset
            )

            #expect(abs(restoredCenter - expectedCenter) < 0.000_001)
        }
    }

    @Test("複数回のscale往復後も中央時刻に累積driftが発生しない")
    func repeatedTierRoundTripsDoNotAccumulateDrift() {
        let viewportHeight: CGFloat = 560
        let topInset: CGFloat = 30
        let expectedCenter: CGFloat = 713.25
        let scaleSequence: [CGFloat] = [0.75, 3, 2, 1, 1.5, 1, 3, 0.75]
        var currentCenter = expectedCenter

        for _ in 0..<20 {
            for scale in scaleSequence {
                let hourHeight = DayTimelineZoomPolicy.hourHeight(for: scale)
                let scrollY = DayTimelineZoomPolicy.scrollY(
                    preservingCenterMinute: currentCenter,
                    viewportHeight: viewportHeight,
                    hourHeight: hourHeight,
                    contentHeight: contentHeight(hourHeight: hourHeight),
                    timelineTopInset: topInset
                )
                currentCenter = DayTimelineZoomPolicy.centerMinute(
                    visibleMinY: -scrollY,
                    viewportHeight: viewportHeight,
                    hourHeight: hourHeight,
                    timelineTopInset: topInset
                )
            }
        }

        #expect(abs(currentCenter - expectedCenter) < 0.000_001)
    }

    @Test("iPhone 13相当viewportで全tierの復元scrollYを上下端へclampする")
    func clampsCenterMinuteAndScrollOffsetAtEdges() {
        #expect(DayTimelineZoomPolicy.centerMinute(
            visibleMinY: 0,
            viewportHeight: 20,
            hourHeight: 38,
            timelineTopInset: 30
        ) == 0)
        #expect(DayTimelineZoomPolicy.centerMinute(
            visibleMinY: -10_000,
            viewportHeight: 200,
            hourHeight: 38
        ) == 1_440)

        let viewportHeight: CGFloat = 560
        for scale in DayTimelineZoomPolicy.supportedScales {
            let hourHeight = DayTimelineZoomPolicy.hourHeight(for: scale)
            let height = contentHeight(hourHeight: hourHeight)
            #expect(DayTimelineZoomPolicy.scrollY(
                preservingCenterMinute: 0,
                viewportHeight: viewportHeight,
                hourHeight: hourHeight,
                contentHeight: height,
                timelineTopInset: 30
            ) == 0)
            #expect(DayTimelineZoomPolicy.scrollY(
                preservingCenterMinute: 1_440,
                viewportHeight: viewportHeight,
                hourHeight: hourHeight,
                contentHeight: height,
                timelineTopInset: 30
            ) == max(0, height - viewportHeight))
        }
    }

    private func contentHeight(hourHeight: CGFloat) -> CGFloat {
        30 + hourHeight * 24 + 24
    }
}

@Suite("Day timeline zoom persistence", .serialized)
struct DayTimelineZoomPersistenceTests {
    @Test("5tierすべてを標準キーへ保存しUserDefaults再生成後に読み込む")
    func everyTierRoundTripsAfterDefaultsRecreation() throws {
        let suiteName = "DayTimelineZoomPersistenceTests.\(UUID().uuidString)"
        let writer = try #require(UserDefaults(suiteName: suiteName))
        writer.removePersistentDomain(forName: suiteName)
        defer { writer.removePersistentDomain(forName: suiteName) }

        for scale in DayTimelineZoomPolicy.supportedScales {
            DayTimelineZoomPolicy.save(scale, to: writer)
            #expect(writer.double(forKey: "timeline.day.hourScale") == Double(scale))

            let reader = try #require(UserDefaults(suiteName: suiteName))
            #expect(DayTimelineZoomPolicy.load(from: reader) == scale)
        }
    }

    @Test("欠損・NaN・Infinity・負値・不正型は1へ復旧し未知有限値は最寄りで読む")
    func recoversMalformedStoredValues() throws {
        let suiteName = "DayTimelineZoomPersistenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(DayTimelineZoomPolicy.load(from: defaults) == 1)

        defaults.set(-4.0, forKey: DayTimelineZoomPolicy.userDefaultsKey)
        #expect(DayTimelineZoomPolicy.load(from: defaults) == 1)

        defaults.set(Double.nan, forKey: DayTimelineZoomPolicy.userDefaultsKey)
        #expect(DayTimelineZoomPolicy.load(from: defaults) == 1)

        defaults.set(Double.infinity, forKey: DayTimelineZoomPolicy.userDefaultsKey)
        #expect(DayTimelineZoomPolicy.load(from: defaults) == 1)

        defaults.set(["invalid-type"], forKey: DayTimelineZoomPolicy.userDefaultsKey)
        #expect(DayTimelineZoomPolicy.load(from: defaults) == 1)

        defaults.set(1.7, forKey: DayTimelineZoomPolicy.userDefaultsKey)
        #expect(DayTimelineZoomPolicy.load(from: defaults) == 1.5)
    }

    @Test("保存時は対応scaleへsnapしてから永続化する")
    func saveSnapsBeforePersistence() throws {
        let suiteName = "DayTimelineZoomPersistenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        DayTimelineZoomPolicy.save(1.8, to: defaults)

        #expect(defaults.double(forKey: DayTimelineZoomPolicy.userDefaultsKey) == 2)
        #expect(DayTimelineZoomPolicy.load(from: defaults) == 2)
    }
}
