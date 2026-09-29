import SwiftUI

struct ClanCatCell: View {
    let cat: Cat
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                CatSprite(cat: cat)
                    .padding(6)
                    .background(.background, in: .rect(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        HealthBadges(cat: cat)
                    }
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(cat.moonsText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        var parts = [name, cat.rank.label, cat.moonsText]
        if cat.has("pregnant") { parts.append("expecting kits") }
        if cat.has("recovering from birth") { parts.append("recovering from birth") }
        if cat.hasVisibleSickness { parts.append("unwell") }
        if cat.hasVisiblePermanentCondition { parts.append("has a lasting condition") }
        return parts.joined(separator: ", ")
    }
}
