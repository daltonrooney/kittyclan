import SwiftUI

struct AfterlifeCatCell: View {
    @Environment(AppModel.self) private var model
    let cat: Cat
    let action: () -> Void

    var body: some View {
        let name = model.displayName(cat)
        let isGuide = model.isGuide(cat)
        Button(action: action) {
            VStack(spacing: 4) {
                CatSprite(cat: cat)
                    .padding(4)
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if isGuide {
                    Label("Guiding ghost", systemImage: "star.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: .rect(cornerRadius: 14))
            .overlay {
                if isGuide {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.orange.opacity(0.9), lineWidth: 2)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(name: name, isGuide: isGuide))
        .accessibilityAddTraits(.isButton)
    }

    private func accessibilityText(name: String, isGuide: Bool) -> String {
        var parts = [name]
        if isGuide { parts.append("guiding ghost") }
        parts.append(detail)
        return parts.joined(separator: ", ")
    }

    private var detail: String {
        [model.pastRank(of: cat)?.capitalizedFirst, model.deadFor(cat)].compactMap(\.self).joined(separator: "\n")
    }
}
