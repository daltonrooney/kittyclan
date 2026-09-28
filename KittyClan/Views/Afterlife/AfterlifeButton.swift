import SwiftUI

/// Opens the afterlife at the Clan's own: wherever its guide resides.
struct AfterlifeButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let afterlife = model.clan?.guideAfterlife ?? .starClan
        Button(afterlife.label, systemImage: afterlife.symbol, action: model.showAfterlife)
            .font(.headline)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(afterlife.tint)
            .accessibilityHint("See the Clan's dead and its guide")
    }
}
