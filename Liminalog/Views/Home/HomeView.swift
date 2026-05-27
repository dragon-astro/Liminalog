import SwiftUI

struct HomeView: View {
    @Environment(ChapterStore.self) private var store
    @State private var editingChapter: Chapter? = nil
    @State private var showingAddSheet = false
    @State private var addSheetStart = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    CurrentChapterCard()
                    // CategoryGrid 内のチェブロンで折りたたみを行う。
                    CategoryGrid()
                    Divider()
                    TimelineView(
                        date: Date(),
                        title: "今日のタイムライン",
                        editingChapter: $editingChapter
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(Date().japaneseMonthDayShortWeekday)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityLabel("今日の日付 \(Date().japaneseMonthDayShortWeekday)")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: CategorySettingsView()) {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(item: $editingChapter) { chapter in
                ChapterEditSheet(chapter: chapter)
            }
            .sheet(isPresented: $showingAddSheet) {
                ChapterCreateSheet(initialDate: addSheetStart)
            }
            .onAppear {
                store.seedDefaultCategorySetsIfNeeded()
            }
        }
    }
}

#Preview("Home") {
    HomeView()
        .liminalogPreviewEnvironment()
}
