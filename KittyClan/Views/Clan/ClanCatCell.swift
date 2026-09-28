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
                    .grayscale(cat.isDead ? 0.7 : 0)
                    .opacity(cat.isDead ? 0.8 : 1)
                    .overlay(alignment: .topTrailing) {
                        if !cat.isDead {
                            HealthBadges(cat: cat)
                        }
                    }
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail)
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
        var parts = [name, cat.rank.label, detail]
        if !cat.isDead {
            if cat.hasVisibleSickness { parts.append("unwell") }
            if cat.hasVisiblePermanentCondition { parts.append("has a lasting condition") }
        }
        return parts.joined(separator: ", ")
    }

    private var detail: String {
        if cat.isDead, let moon = cat.diedAtClanAge {
            return "Died moon \(moon)"
        }
        return cat.moonsText
    }
}
