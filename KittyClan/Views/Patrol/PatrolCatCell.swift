import SwiftUI

struct PatrolCatCell: View {
    @Environment(AppModel.self) private var model
    let cat: Cat
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        let name = model.displayName(cat)
        let skills = model.shortSkills(of: cat)
        Button(action: action) {
            VStack(spacing: 4) {
                CatSprite(cat: cat)
                    .padding(6)
                    .background(isSelected ? AnyShapeStyle(Color.brown.opacity(0.25)) : AnyShapeStyle(.background), in: .rect(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? Color.brown : .clear, lineWidth: 3)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .brown)
                                .padding(4)
                        }
                    }
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(cat.rank.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                SkillLabel(text: skills)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(cat.rank.label), \(skills)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
