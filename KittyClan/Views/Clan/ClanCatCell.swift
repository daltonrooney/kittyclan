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
        .accessibilityLabel("\(name), \(cat.rank.label), \(detail)")
        .accessibilityAddTraits(.isButton)
    }

    private var detail: String {
        if cat.isDead, let moon = cat.diedAtClanAge {
            return "Died moon \(moon)"
        }
        return cat.moonsText
    }
}
