import SwiftUI

/// The camp's den-label toggle and newborn and overflow notes, floating over the camp on narrow screens.
struct CompactCampBar: View {
    @Environment(AppModel.self) private var model
    @Binding var showsDenLabels: Bool
    let showCats: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            let newborns = model.clan?.living.count(where: { $0.rank == .newborn }) ?? 0
            if newborns > 0 {
                Label("\(newborns)", systemImage: "moon.zzz.fill")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: .capsule)
                    .accessibilityLabel(newborns == 1 ? "1 newborn in the nursery" : "\(newborns) newborns in the nursery")
            }
            if model.campOverflow > 0 {
                Button("+\(model.campOverflow) more", action: showCats)
                    .font(.subheadline.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: .capsule)
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows every cat in the list")
            }
            Spacer(minLength: 0)
            Toggle(isOn: $showsDenLabels) {
                Label("Den labels", systemImage: "tag.fill")
            }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .background(.regularMaterial, in: .circle)
        }
        .padding(10)
    }
}
