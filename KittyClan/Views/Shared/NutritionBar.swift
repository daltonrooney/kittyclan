import SwiftUI

/// How full a cat is: Clangen's word ("hungry", "full"…) over a coloured bar.
struct NutritionBar: View {
    let nutrition: Nutrition

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(nutrition.label.capitalized)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            ProgressView(value: min(max(nutrition.percentage, 0), 100), total: 100)
                .tint(color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Food")
        .accessibilityValue("\(nutrition.label), \(Int(nutrition.percentage.rounded())) percent")
    }

    private var color: Color {
        switch nutrition.percentage {
        case ..<41: .red
        case ..<61: .orange
        default: .green
        }
    }
}
