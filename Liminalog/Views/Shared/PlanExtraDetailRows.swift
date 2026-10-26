import SwiftUI

struct PlanExtraDetailRows: View {
    @Environment(\.openURL) private var openURL
    let locationName: String?
    let urlString: String?

    var body: some View {
        if PlanExtraDetails.normalized(locationName) != nil || PlanExtraDetails.normalized(urlString) != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let location = PlanExtraDetails.normalized(locationName) {
                    Label(location, systemImage: "mappin.and.ellipse")
                }
                if let text = PlanExtraDetails.normalized(urlString) {
                    Button {
                        PlanExtraDetails.openWebURL(text) { openURL($0) }
                    } label: {
                        Label(text, systemImage: "link").lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PlanExtraDetails.webURL(text) == nil ? LiminalTheme.secondaryText : LiminalTheme.accent)
                    .disabled(PlanExtraDetails.webURL(text) == nil)
                    .accessibilityIdentifier("plan-detail-url")
                }
            }
            .font(.subheadline)
        }
    }
}
