import SwiftUI

struct PatrolTypePicker: View {
    let patrol: PatrolModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kind of patrol")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    PatrolTypeChip(title: "Any", symbol: "dice.fill", isSelected: patrol.type == nil, isEnabled: patrol.allows(nil)) {
                        patrol.selectType(nil)
                    }
                    ForEach(PatrolType.allCases, id: \.self) { type in
                        PatrolTypeChip(title: type.label, symbol: type.symbol, isSelected: patrol.type == type, isEnabled: patrol.allows(type)) {
                            patrol.selectType(type)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            Text(hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var hint: String {
        if patrol.hasHealer { return "A medicine cat on the patrol means it's for gathering herbs." }
        return switch patrol.type {
        case nil: "The Clan will decide between hunting, border and training."
        case .herbGathering: "Herb gathering needs a medicine cat or medicine cat apprentice."
        default: "Medicine cats can only go herb gathering."
        }
    }
}
