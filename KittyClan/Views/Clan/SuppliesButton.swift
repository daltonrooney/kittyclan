import SwiftUI

/// Opens the supplies sheet. With prey and herbs on it shows the fresh-kill pile against what the Clan needs.
struct SuppliesButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let clan = model.clan {
            if clan.preyAndHerbs {
                let isLow = model.isLowOnPrey
                Button(action: show) {
                    Label {
                        Text("Prey \(clan.freshKill.total.preyAmount) / \(model.preyNeeded.preyAmount) needed")
                            .monospacedDigit()
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: isLow ? "exclamationmark.triangle.fill" : "fish.fill")
                    }
                    .font(.headline)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(isLow ? .red : .green)
                .accessibilityLabel("Supplies")
                .accessibilityValue("\(clan.freshKill.total.preyAmount) prey, \(model.preyNeeded.preyAmount) needed each moon\(isLow ? ", low on prey" : "")")
            } else {
                Button("Herbs", systemImage: "leaf.fill", action: show)
                    .font(.headline)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(.green)
            }
        }
    }

    private func show() {
        model.isShowingSupplies = true
    }
}
