import SwiftUI

extension Den {
    /// Dens with something to open get a symbol and colour; the rest are plain labels.
    var campSymbol: String? {
        switch self {
        case .leader: "crown.fill"
        case .medicine: "leaf.fill"
        case .clearing: "person.2.wave.2.fill"
        case .warrior: "shield.fill"
        default: nil
        }
    }

    var campTint: Color {
        switch self {
        case .leader: .orange
        case .medicine: .green
        case .clearing: .teal
        case .warrior: .indigo
        default: .secondary
        }
    }

    var campHint: String? {
        switch self {
        case .leader: "Choose how to treat other Clans and outsiders"
        case .medicine: "See the herbs in the medicine den"
        case .clearing: "Have a mediator settle a quarrel"
        case .warrior: "Choose what the warriors focus on"
        default: nil
        }
    }
}
