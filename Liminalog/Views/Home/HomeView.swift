import SwiftUI

struct HomeView: View {
    @Environment(ChapterStore.self) private var store
    @State private var editingChapter: Chapter? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    CurrentChapterCard()

                    CategoryGrid()

                    Divider()

                    TimelineView(editingChapter: $editingChapter)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("今日")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: CategorySettingsView()) {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(item: $editingChapter) { chapter in
                ChapterEditSheet(chapter: chapter)
            }
            .onAppear {
                store.seedDefaultCategoriesIfNeeded()
            }
        }
    }
}
