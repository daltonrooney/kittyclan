import SwiftUI

struct LeaderDenButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Leader's Den", systemImage: "crown.fill", action: show)
            .font(.headline)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(.orange)
            .accessibilityHint("Choose how to treat other Clans and outsiders")
    }

    private func show() {
        model.leaderDenTab = .clans
        model.isShowingLeaderDen = true
    }
}
