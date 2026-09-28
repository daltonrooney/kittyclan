import SwiftUI

extension Den {
    /// Dens with something to open get a symbol and colour; the rest are plain labels.
    var campSymbol: String? {
        switch self {
        case .leader: "crown.fill"
        case .medicine: "leaf.fill"
        default: nil
        }
    }

    var campTint: Color {
        switch self {
        case .leader: .orange
        case .medicine: .green
        default: .secondary
        }
    }
}
