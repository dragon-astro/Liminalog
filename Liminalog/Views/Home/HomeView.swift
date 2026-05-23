import SwiftUI

struct HomeView: View {
    @Environment(ChapterStore.self) private var store
    @State private var editingChapter: Chapter? = nil
    @State private var showingAddSheet = false
    @State private var addSheetStart = Date()

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            CurrentChapterCard()
                        }
                        CategoryGrid()
                        Divider()
                        TimelineView(
                            date: Date(),
                            title: "今日のタイムライン",
                            editingChapter: $editingChapter
                        ) { start in
                            addSheetStart = start
                            showingAddSheet = true
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .background(Color(.systemGroupedBackground))
                .onAppear {
                    scrollToNow(proxy)
                }
                .onChange(of: store.revision) { _, _ in
                    scrollToNow(proxy)
                }
            }
            .navigationTitle("ホーム")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
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

    private func scrollToNow(_ proxy: ScrollViewProxy) {
        guard Calendar.current.isDateInToday(Date()) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(currentTimeMarkerID, anchor: .center)
            }
        }
    }
}

#Preview("Home") {
    HomeView()
        .liminalogPreviewEnvironment()
}
