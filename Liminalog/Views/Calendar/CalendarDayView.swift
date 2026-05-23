import SwiftUI

struct CalendarDayView: View {
    @Environment(ChapterStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var editingChapter: Chapter?
    @State private var showingAddSheet = false
    @State private var addSheetStart: Date

    init(date: Date) {
        _date = State(initialValue: date)
        _addSheetStart = State(initialValue: date)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                dayHeader
                allDayArea
                timelineArea
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label("戻る", systemImage: "chevron.left")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addSheetStart = defaultChapterStart
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    if value.translation.width < -50 {
                        shiftDay(1)
                    } else if value.translation.width > 50 {
                        shiftDay(-1)
                    }
                }
        )
        .sheet(item: $editingChapter) { chapter in
            ChapterEditSheet(chapter: chapter)
        }
        .sheet(isPresented: $showingAddSheet) {
            ChapterCreateSheet(initialDate: addSheetStart)
        }
    }

    private var dayHeader: some View {
        HStack(spacing: 12) {
            Button {
                shiftDay(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 3) {
                Text(date.japaneseMonthDayWeekday)
                    .font(.title3.bold())
                Text("\(store.chapters(on: date).count)件の記録 / \(store.plannedBlocks(on: date).count)件の予定")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                shiftDay(1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
        .id(store.revision)
    }

    private var allDayArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("終日・時間未指定")
                .font(.headline)

            let plans = store.plannedBlocks(on: date).filter(\.isAllDay)
            if plans.isEmpty {
                Text("予定はありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(plans) { plan in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(plan.category?.color ?? Color(.systemGray3))
                            .frame(width: 5)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(plan.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("\(plan.startTime.shortTime) - \(plan.endTime.shortTime)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .frame(minHeight: 42)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill((plan.category?.color ?? Color(.systemGray3)).opacity(0.08))
                    )
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
        .id(store.revision)
    }

    private var timelineArea: some View {
        TimelineView(
            date: date,
            title: "タイムライン",
            compactEmptyState: true,
            editingChapter: $editingChapter
        ) { start in
            addSheetStart = start
            showingAddSheet = true
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var defaultChapterStart: Date {
        let calendar = Calendar.japanese
        let now = Date()
        if calendar.isDateInToday(date) {
            return now
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }

    private func shiftDay(_ value: Int) {
        date = Calendar.japanese.date(byAdding: .day, value: value, to: date) ?? date
    }
}

#Preview("Day") {
    NavigationStack {
        CalendarDayView(date: Date())
    }
    .liminalogPreviewEnvironment()
}
