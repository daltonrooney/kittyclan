import SwiftUI

/// Clangen's herb stock rating (empty, low, adequate, full, excess) as a coloured capsule.
struct HerbRatingChip: View {
    let rating: String

    var body: some View {
        Text(rating.capitalized)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.2), in: .capsule)
            .foregroundStyle(color)
    }

    private var color: Color {
        switch rating {
        case "empty": .red
        case "low": .orange
        case "adequate": .green
        case "full": .teal
        default: .blue
        }
    }
}
