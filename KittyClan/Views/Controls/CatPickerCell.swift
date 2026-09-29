import SwiftUI

/// A selectable cat in a picker grid, with an optional tag such as "Current mentor".
struct CatPickerCell: View {
    @Environment(AppModel.self) private var model
    let cat: Cat
    let caption: String
    var tag: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let name = model.displayName(cat)
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
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let tag {
                    Text(tag)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.brown.opacity(0.2), in: .capsule)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([name, caption, tag].compactMap(\.self).joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
