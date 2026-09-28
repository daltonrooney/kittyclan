import SwiftUI

struct MedicineDenSection: View {
    @Environment(AppModel.self) private var model
    let supply: HerbSupply
    let usesHerbs: Bool

    var body: some View {
        let stock = model.herbStock
        Section {
            if let status = model.herbStatus {
                Label {
                    Text(status.storyText)
                        .italic()
                } icon: {
                    Image(systemName: "quote.bubble.fill")
                        .foregroundStyle(.green)
                }
            }
            if stock.isEmpty {
                Text("The herb stores are empty.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(stock) { herb in
                    HStack(spacing: 12) {
                        Image(systemName: "leaf.fill")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        Text(herb.name.prefix(1).uppercased() + herb.name.dropFirst())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(herb.count, format: .number)
                            .font(.headline.monospacedDigit())
                        HerbRatingChip(rating: herb.rating)
                            .frame(width: 96, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text("Medicine den")
        } footer: {
            if usesHerbs {
                Text("Medicine cats use herbs to heal sick and hurt cats. Send herb gathering patrols to find more.")
            } else {
                Text("In classic mode, medicine cats treat cats without using herbs.")
            }
        }

        if !supply.log.isEmpty {
            Section("This moon in the medicine den") {
                ForEach(Array(supply.log.enumerated()), id: \.offset) { _, line in
                    Text(line.storyText)
                }
            }
        }
    }
}
