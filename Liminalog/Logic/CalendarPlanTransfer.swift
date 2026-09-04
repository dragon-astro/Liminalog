import Foundation

enum CalendarPlanTransferMode: String {
    case copy, move

    var title: String { self == .copy ? "複製" : "移動" }
    var symbol: String { self == .copy ? "doc.on.doc" : "arrow.up.right" }
}

enum CalendarPlanTransferError: Error, LocalizedError {
    case missingPlan, locked, externalPlan, noDates, invalidTime, unavailableDay, overlap, persistence
    case protectedOverlap, sourceOverlap, incomingOverlap, changed

    var errorDescription: String? {
        switch self {
        case .missingPlan: "元の予定が見つかりません。"
        case .locked: "今日以前の時間指定の予定は移動できません。複製はできます。"
        case .externalPlan: "連携元の予定は元のカレンダーで移動してください。複製はできます。"
        case .noDates: "日付を選んでください。"
        case .invalidTime: "移動先の日付では元の開始・終了時刻を保てません。"
        case .unavailableDay: "時間指定の予定は明日以降の日付を選んでください。"
        case .overlap: "選んだ日付に重なる予定があります。日付を選び直してください。予定は変更していません。"
        case .persistence: "予定を保存できませんでした。予定は変更していません。"
        case .protectedOverlap: "移動先には、履歴としてロックされた予定か外部連携の予定があります。これらは置換できません。"
        case .sourceOverlap: "複製元の予定と重なります。元の予定を残すため、別の日付を選んでください。"
        case .incomingOverlap: "追加する予定同士が重なります。日付の間隔を空けてください。"
        case .changed: "確認中に予定が変更されました。内容を確認し直してから実行してください。"
        }
    }
}

struct CalendarPlanTransferPreview: Equatable {
    let sourceID: UUID
    let sourceUpdatedAt: Date
    let sourceTitle: String
    let sourceStart: Date
    let sourceEnd: Date
    let isAllDay: Bool
    let dates: Set<Date>
    let mode: CalendarPlanTransferMode
    let intervals: [DateInterval]
    let replacement: PlanTemplateReplacement
}

enum CalendarPlanTransferDayStatus: Equatable {
    case available
    case replacement(Int)
    case blocked(String)

    var warning: String? {
        switch self {
        case .available: nil
        case .replacement(let count): "\(count)件の予定と重複。確認後に置換できます。"
        case .blocked(let reason): reason
        }
    }
}

enum CalendarPlanTransfer {
    /// Shift both endpoints by calendar days, retaining wall-clock times and multi-day spans.
    static func interval(start: Date, end: Date, to day: Date, calendar: Calendar = .current) -> DateInterval? {
        guard start < end,
              let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                                  to: calendar.startOfDay(for: day)).day,
              let shiftedStart = calendar.date(byAdding: .day, value: days, to: start),
              let shiftedEnd = calendar.date(byAdding: .day, value: days, to: end),
              shiftedStart < shiftedEnd,
              calendar.dateComponents([.hour, .minute, .second], from: start)
                == calendar.dateComponents([.hour, .minute, .second], from: shiftedStart),
              calendar.dateComponents([.hour, .minute, .second], from: end)
                == calendar.dateComponents([.hour, .minute, .second], from: shiftedEnd)
        else { return nil }
        return DateInterval(start: shiftedStart, end: shiftedEnd)
    }
}
