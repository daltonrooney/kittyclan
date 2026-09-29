import SwiftUI

/// A den's name in camp. The leader's, medicine and warriors' dens and the clearing open their sheets; the others are just labels.
struct CampDenLabel: View {
    @Environment(AppModel.self) private var model
    let den: Den

    var body: some View {
        if let symbol = den.campSymbol {
            Button(action: open) {
                Label(den.rawValue, systemImage: symbol)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(den.campTint.gradient, in: .capsule)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityHint(den.campHint ?? "")
        } else {
            Text(den.rawValue)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.75))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: .capsule)
        }
    }

    private func open() {
        switch den {
        case .leader:
            model.leaderDenTab = .clans
            model.isShowingLeaderDen = true
        case .medicine:
            model.suppliesStartsAtHerbs = true
            model.isShowingSupplies = true
        case .clearing:
            model.showMediation()
        case .warrior:
            model.isShowingFocus = true
        default:
            break
        }
    }
}
