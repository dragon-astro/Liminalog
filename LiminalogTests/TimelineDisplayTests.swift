import CoreGraphics
import Foundation
import Testing
@testable import Liminalog

@MainActor
struct TimelineDisplayTests {
    @Test
    func readOnlyEntriesClipCrossDaySnapshotsAndKeepContinuationMetadata() throws {
        let calendar = Calendar.current
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 12)))
        let dayStart = DayBoundary.dayStart(for: date)
        let start = try #require(calendar.date(byAdding: .hour, value: -1, to: dayStart))
        let end = try #require(calendar.date(byAdding: .minute, value: 30, to: dayStart))
        let snapshot = TimelineDisplaySnapshot(
            id: "actual-overnight",
            start: start,
            end: end,
            title: "睡眠",
            categoryIconName: "moon.fill",
            categoryColorHex: "#1F2937"
        )
        let view = SharedTimelineReadOnlyView(
            date: date,
            title: "",
            planSnapshots: [],
            actualSnapshots: [snapshot]
        )

        let entries = view.entries(from: [snapshot], kind: .actual, tab: .actual)
        let event = try #require(entries.first(where: { !$0.kind.isGap }))

        #expect(event.clippedStart == dayStart)
        #expect(event.clippedEnd == end)
        #expect(event.metadata.continuesFromPreviousDay)
        #expect(!event.metadata.continuesToNextDay)
        #expect(entries.filter { $0.kind.isGap }.count == 1)
    }

    @Test
    func readOnlyEntriesKeepShortRecordsButDoNotInsertSubFiveMinuteGaps() throws {
        let calendar = Calendar.current
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 12)))
        let dayStart = DayBoundary.dayStart(for: date)
        let firstStart = try #require(calendar.date(byAdding: .hour, value: 9, to: dayStart))
        let firstEnd = try #require(calendar.date(byAdding: .second, value: 30, to: firstStart))
        let secondStart = try #require(calendar.date(byAdding: .minute, value: 4, to: firstEnd))
        let secondEnd = try #require(calendar.date(byAdding: .hour, value: 1, to: secondStart))
        let shortRecord = TimelineDisplaySnapshot(
            id: "short-record",
            start: firstStart,
            end: firstEnd,
            title: "切替",
            categoryIconName: "bolt.fill",
            categoryColorHex: "#F2C94C"
        )
        let nextRecord = TimelineDisplaySnapshot(
            id: "next-record",
            start: secondStart,
            end: secondEnd,
            title: "勉強",
            categoryIconName: "book.fill",
            categoryColorHex: "#2F80ED"
        )
        let view = SharedTimelineReadOnlyView(
            date: date,
            title: "",
            planSnapshots: [],
            actualSnapshots: [shortRecord, nextRecord]
        )

        let entries = view.entries(from: [nextRecord, shortRecord], kind: .actual, tab: .actual)
        let events = entries.filter { !$0.kind.isGap }

        #expect(events.map(\.id) == ["short-record", "next-record"])
        #expect(events[0].metadata.isShort)
        #expect(events[0].clippedDuration == 30)
        #expect(entries.count == 4)
    }

    @Test
    func timelineBarLayoutClipsOffsetsAndUsesMinimumSegmentWidth() throws {
        let calendar = Calendar.current
        let dayStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let dayEnd = try #require(calendar.date(byAdding: .day, value: 1, to: dayStart))
        let beforeDay = try #require(calendar.date(byAdding: .hour, value: -2, to: dayStart))
        let noon = try #require(calendar.date(byAdding: .hour, value: 12, to: dayStart))
        let afterDay = try #require(calendar.date(byAdding: .hour, value: 2, to: dayEnd))
        let shortEnd = try #require(calendar.date(byAdding: .second, value: 30, to: noon))

        #expect(TimelineBarLayout.xOffset(for: beforeDay, dayStart: dayStart, dayEnd: dayEnd, width: 240) == 0)
        #expect(TimelineBarLayout.xOffset(for: noon, dayStart: dayStart, dayEnd: dayEnd, width: 240) == 120)
        #expect(TimelineBarLayout.xOffset(for: afterDay, dayStart: dayStart, dayEnd: dayEnd, width: 240) == 240)
        #expect(
            TimelineBarLayout.segmentWidth(
                start: noon,
                end: shortEnd,
                dayStart: dayStart,
                dayEnd: dayEnd,
                width: 240
            ) == 1
        )
    }

    @Test
    func timelineBarLayoutShowsIconsOnlyForReadableSegments() {
        #expect(!TimelineBarLayout.shouldShowIcon(duration: 14 * 60 + 59, width: 40))
        #expect(!TimelineBarLayout.shouldShowIcon(duration: 15 * 60, width: 23))
        #expect(TimelineBarLayout.shouldShowIcon(duration: 15 * 60, width: 24))
    }
}
