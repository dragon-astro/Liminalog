import SwiftUI
import WidgetKit

@main
struct LiminalogWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecordingGridWidget()
        LiminalogLiveActivityWidget()
    }
}
