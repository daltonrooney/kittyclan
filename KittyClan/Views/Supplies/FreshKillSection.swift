import SwiftUI

struct FreshKillSection: View {
    @Environment(AppModel.self) private var model
    let pile: FreshKillPile

    var body: some View {
        let needed = model.preyNeeded
        let isLow = model.isLowOnPrey
        Section {
            HStack(spacing: 16) {
                Image(systemName: "fish.fill")
                    .font(.largeTitle)
                    .foregroundStyle(isLow ? .red : .green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(pile.total.preyAmount) pieces of prey")
                        .font(.title2.bold())
                    Text("The Clan eats about \(needed.preyAmount) each moon.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            if isLow {
                Label("The Clan is low on prey. Send a hunting patrol to catch more!", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.headline)
            }
            LabeledContent("Needed each moon", value: needed.preyAmount)
            LabeledContent("Spoiling next moon", value: pile.expiresIn1.preyAmount)
        } header: {
            Text("Fresh-kill pile")
        } footer: {
            Text("Prey stays fresh for three moons, then spoils.")
        }

        if !pile.log.isEmpty {
            Section("This moon at the fresh-kill pile") {
                ForEach(Array(pile.log.enumerated()), id: \.offset) { _, line in
                    Text(line.storyText)
                }
            }
        }
    }
}
