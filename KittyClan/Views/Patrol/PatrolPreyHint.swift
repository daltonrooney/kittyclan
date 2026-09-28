import SwiftUI

/// The fresh-kill pile at a glance, nudging toward a hunting patrol when prey runs low.
struct PatrolPreyHint: View {
    @Environment(AppModel.self) private var model
    let patrol: PatrolModel

    var body: some View {
        if let clan = model.clan, clan.preyAndHerbs {
            let isLow = model.isLowOnPrey
            HStack(spacing: 12) {
                Image(systemName: isLow ? "exclamationmark.triangle.fill" : "fish.fill")
                    .font(.title2)
                    .foregroundStyle(isLow ? .red : .green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prey: \(clan.freshKill.total.preyAmount) / \(model.preyNeeded.preyAmount) needed")
                        .font(.headline.monospacedDigit())
                    if isLow {
                        Text("The Clan is low on prey — try a hunting patrol.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if isLow, patrol.type != .hunting, patrol.allows(.hunting) {
                    Button("Go hunting", systemImage: PatrolType.hunting.symbol) {
                        patrol.selectType(.hunting)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }
            .padding(12)
            .background((isLow ? Color.red : Color.green).opacity(0.12), in: .rect(cornerRadius: 14))
        }
    }
}
