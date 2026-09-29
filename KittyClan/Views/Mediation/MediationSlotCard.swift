import SwiftUI

/// One side of the pair being mediated, tapped to choose which slot the picker fills.
struct MediationSlotCard: View {
    @Environment(AppModel.self) private var model
    let slot: MediationSlot
    let cat: Cat?
    let isActive: Bool
    let select: () -> Void
    let clear: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                Text(slot.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Group {
                    if let cat {
                        CatSprite(cat: cat)
                    } else {
                        Image(systemName: "questionmark")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 80, height: 80)
                Text(cat.map(model.displayName) ?? "Choose a cat")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(cat?.rank.label ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(isActive ? AnyShapeStyle(Color.teal.opacity(0.15)) : AnyShapeStyle(.background), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isActive ? Color.teal : .clear, lineWidth: 2)
            }
            .overlay(alignment: .topTrailing) {
                if cat != nil {
                    Button("Clear", systemImage: "xmark.circle.fill", action: clear)
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
