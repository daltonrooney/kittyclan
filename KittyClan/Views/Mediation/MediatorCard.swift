import SwiftUI

/// The chosen mediator: who they are, how experienced, and whether they can work.
struct MediatorCard: View {
    @Environment(AppModel.self) private var model
    let mediator: Cat
    let status: String
    let isBlocked: Bool

    var body: some View {
        HStack(spacing: 16) {
            CatSprite(cat: mediator)
                .frame(width: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName(mediator))
                    .font(.title3.bold())
                Text("\(mediator.rank.label) · \(mediator.personality.trait.capitalized) · \(PatrolSlot.experienceLevel(mediator.experience).capitalized) experience")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label(status, systemImage: isBlocked ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isBlocked ? .red : .green)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(.background, in: .rect(cornerRadius: 16))
    }
}
