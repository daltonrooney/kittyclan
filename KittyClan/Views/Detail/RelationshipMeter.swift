import SwiftUI

/// A compact bar for one relationship value: centred on zero for −100…100, left-anchored for romance.
struct RelationshipMeter: View {
    let value: RelationshipValue
    let amount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.rawValue.capitalized)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            ZStack {
                Capsule()
                    .fill(.quaternary)
                RelationshipBarShape(fraction: fraction, isCentred: value != .romance)
                    .fill(color)
                if value != .romance {
                    Rectangle()
                        .fill(.secondary)
                        .frame(width: 1)
                }
            }
            .frame(height: 6)
            Text(value.tierText(for: amount))
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: 110, alignment: .leading)
    }

    private var fraction: Double {
        let range = value.range
        return Double(amount) / Double(value == .romance ? range.upperBound : max(abs(range.lowerBound), range.upperBound))
    }

    private var color: Color {
        if value == .romance { return .pink }
        return amount >= 0 ? .green : .red
    }
}
