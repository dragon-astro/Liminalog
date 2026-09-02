import Foundation
import Testing
@testable import Liminalog

@Suite("PlanTemplateSnapshot")
struct PlanTemplateSnapshotTests {
    @Test("一日プリセットitemsはversion付きenvelopeで往復する")
    func codecRoundTrip() throws {
        let items = [
            makeSnapshot(
                title: "ジム",
                categoryID: UUID(),
                startMinute: 19 * 60,
                endMinute: 20 * 60 + 30,
                note: "脚の日"
            ),
            makeSnapshot(
                title: "睡眠",
                startMinute: 23 * 60,
                endMinute: 31 * 60,
                isPublic: false
            )
        ]

        let data = try DayPresetItemsCodec.encode(items)

        #expect(try DayPresetItemsCodec.decode(data) == items)
    }

    @Test("未知versionは壊れたデータと区別して拒否する")
    func unsupportedVersion() throws {
        let data = try JSONEncoder().encode(
            DayPresetItemsEnvelope(version: 99, items: [makeSnapshot()])
        )

        #expect(throws: DayPresetItemsCodec.CodecError.unsupportedVersion(99)) {
            try DayPresetItemsCodec.decode(data)
        }
    }

    @Test("破損データはinvalidPayloadとして拒否する")
    func corruptPayload() {
        #expect(throws: DayPresetItemsCodec.CodecError.invalidPayload) {
            try DayPresetItemsCodec.decode(Data("not-json".utf8))
        }
    }

    @Test("日跨ぎは翌日の壁時計時刻へ復元する")
    func overnightInterval() throws {
        let calendar = Calendar.liminalogTest
        let target = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 3,
            hour: 12
        )))
        let snapshot = makeSnapshot(
            startMinute: 23 * 60,
            endMinute: 31 * 60
        )

        let interval = try #require(snapshot.interval(on: target, calendar: calendar))
        let start = calendar.dateComponents([.day, .hour, .minute], from: interval.start)
        let end = calendar.dateComponents([.day, .hour, .minute], from: interval.end)

        #expect(start.day == 3)
        #expect(start.hour == 23)
        #expect(start.minute == 0)
        #expect(end.day == 4)
        #expect(end.hour == 7)
        #expect(end.minute == 0)
    }

    @Test("DST開始日も9時を9時として復元する")
    func wallClockTimeSurvivesDSTStart() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let target = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 8,
            hour: 12
        )))
        let snapshot = makeSnapshot(startMinute: 9 * 60, endMinute: 10 * 60)

        let interval = try #require(snapshot.interval(on: target, calendar: calendar))
        let start = calendar.dateComponents([.hour, .minute], from: interval.start)
        let end = calendar.dateComponents([.hour, .minute], from: interval.end)

        #expect(start.hour == 9)
        #expect(start.minute == 0)
        #expect(end.hour == 10)
        #expect(end.minute == 0)
    }

    @Test("終日はDST日でもcalendar上の一日を使う")
    func allDayUsesCalendarBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let target = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 8,
            hour: 12
        )))
        let snapshot = makeSnapshot(isAllDay: true)

        let interval = try #require(snapshot.interval(on: target, calendar: calendar))

        #expect(interval.duration == 23 * 60 * 60)
    }

    private func makeSnapshot(
        title: String = "予定",
        categoryID: UUID? = nil,
        startMinute: Int = 9 * 60,
        endMinute: Int = 10 * 60,
        isAllDay: Bool = false,
        note: String? = nil,
        isPublic: Bool = true
    ) -> PlanTemplateSnapshot {
        PlanTemplateSnapshot(
            title: title,
            categoryID: categoryID,
            startMinute: startMinute,
            endMinute: endMinute,
            isAllDay: isAllDay,
            isImportant: false,
            note: note,
            isPublic: isPublic
        )
    }
}
