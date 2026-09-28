import SwiftUI

/// Shown in the header while the Clan is at war. Opens the leader's den.
struct WarBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let enemy = model.enemyClan {
            Button(action: show) {
                Label("At war with \(enemy.name)", systemImage: "flag.2.crossed.fill")
                    .font(.headline)
                    .lineLimit(1)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.red)
            .accessibilityHint("Opens the leader's den")
        }
    }

    private func show() {
        model.leaderDenTab = .clans
        model.isShowingLeaderDen = true
    }
}
