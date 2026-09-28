import SwiftUI

struct ConditionRow: View {
    let condition: CatCondition
    let name: String
    let moons: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: condition.kind.symbol)
                .font(.title3)
                .foregroundStyle(condition.kind.color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(condition.kind.label): \(name)")
        .accessibilityValue(detail)
    }

    private var detail: String {
        var parts = [condition.kind.label]
        if condition.kind != .permanent { parts.append("\(condition.severity.capitalized)") }
        if let complication = condition.complication { parts.append(complication.capitalized) }
        parts.append(moons <= 0 ? "Since this moon" : moons == 1 ? "For 1 moon" : "For \(moons) moons")
        return parts.joined(separator: " · ")
    }
}
