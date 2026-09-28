import SwiftUI

struct CatLinkRow: View {
    let cat: Cat
    let name: String
    let relation: String

    var body: some View {
        HStack(spacing: 12) {
            CatSprite(cat: cat)
                .frame(width: 44)
                .grayscale(cat.isDead && cat.afterlife == nil ? 0.7 : 0)
            VStack(alignment: .leading) {
                Text(name)
                    .font(.headline)
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(relation): \(name)")
    }

    private var caption: String {
        if cat.isDead { return "\(relation) · \(cat.afterlife?.label ?? "Remembered")" }
        return relation == cat.rank.label ? relation : "\(relation) · \(cat.rank.label)"
    }
}
