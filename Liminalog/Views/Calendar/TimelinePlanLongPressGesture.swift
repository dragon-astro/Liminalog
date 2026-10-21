import SwiftUI

/// One recognizer owns the complete press/drag/release sequence, even outside the source card.
struct TimelinePlanLongPressGesture: UIGestureRecognizerRepresentable {
    let onEvent: (UIGestureRecognizer.State, CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = TimelinePresetLongPressRecognizer()
        recognizer.minimumPressDuration = 0.65
        recognizer.allowableMovement = 8
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        onEvent(recognizer.state, recognizer.location(in: recognizer.view?.window))
    }
}

/// The press fixes one edge; dragging chooses the other, just like empty-space creation.
struct TimelineMemoCreationDraft {
    let sourceID: UUID
    let dayIndex: Int
    let anchorMinute: Int
    let minimumDuration: Int
    private var currentMinute: Int
    private(set) var range: PlanTimelineCreationPolicy.MinuteRange
    var startMinute: Int { range.start }
    var endMinute: Int { range.end }

    init(sourceID: UUID, dayIndex: Int = 0, anchorMinute: Int, minimumDuration: Int) {
        self.sourceID = sourceID
        self.dayIndex = dayIndex
        let anchor = min(1440, max(0, anchorMinute))
        let minimum = min(1440, max(1, minimumDuration))
        self.anchorMinute = anchor
        self.minimumDuration = minimum
        self.currentMinute = anchor
        self.range = .init(start: anchor, end: anchor)
    }

    var committedRange: PlanTimelineCreationPolicy.MinuteRange {
        PlanTimelineCreationPolicy.range(anchorMinute: anchorMinute, currentMinute: currentMinute,
            minimumDuration: minimumDuration, intervals: [])
            ?? .init(start: max(0, anchorMinute - minimumDuration), end: anchorMinute)
    }

    mutating func extend(to minute: Int) {
        currentMinute = min(1440, max(0, minute))
        if let range = PlanTimelineCreationPolicy.range(anchorMinute: anchorMinute, currentMinute: minute,
            minimumDuration: minimumDuration, intervals: [], enforcesMinimumDuration: false) {
            self.range = range
        }
    }
}

struct TimelineMemoCreationCard: View {
    let title: String
    let start: Date
    let end: Date
    let color: Color
    var body: some View {
        // The shape, not its labels, defines the draft height. A short draft must
        // stay under the finger; the saved plan expands the shared axis afterwards.
        RoundedRectangle(cornerRadius: 7)
            .fill(Color(uiColor: .secondarySystemBackground))
            .overlay {
                GeometryReader { proxy in
                    if proxy.size.height >= 14 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(start.shortTime)–\(end.shortTime)").font(.caption2.bold())
                            if proxy.size.height >= 32 {
                                Text(title).font(.caption.weight(.semibold)).lineLimit(2)
                            }
                        }.foregroundStyle(color).padding(.horizontal, 5).padding(.vertical, 2)
                    }
                }
            }
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: [4, 3])) }
            .clipped()
            .accessibilityLabel("予定メモ、\(start.shortTime)から\(end.shortTime)")
            .accessibilityIdentifier("timeline-memo-creation-draft")
            .allowsHitTesting(false)
    }
}
