import SwiftData
import SwiftUI

/// Only mounted in a visible preset library, keeping history observation bounded.
struct RecentPlanPresetShelf<Card: View>: View {
    let presets: [PlanPreset]
    @ViewBuilder let card: (PlanPreset) -> Card
    @Query private var plans: [PlanBlock]

    init(presets: [PlanPreset], @ViewBuilder card: @escaping (PlanPreset) -> Card) {
        self.presets = presets
        self.card = card
        var descriptor = FetchDescriptor<PlanBlock>(predicate: #Predicate { $0.recurrenceSeriesID == nil }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 100
        _plans = Query(descriptor)
    }

    var body: some View {
        let candidates = RecentPlanPresetCandidates.make(plans: plans, presets: presets)
        VStack(alignment: .leading, spacing: 8) {
            Label("最近作った予定", systemImage: "clock.arrow.circlepath")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
            if candidates.isEmpty {
                Text("最近作った未登録の予定はありません")
                    .font(.caption)
                    .foregroundStyle(LiminalTheme.secondaryText)
                    .padding(.horizontal, 14)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(candidates) { candidate in card(candidate) }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 1)
                }
            }
        }
        .accessibilityIdentifier("recent-unregistered-plan-shelf")
    }
}
