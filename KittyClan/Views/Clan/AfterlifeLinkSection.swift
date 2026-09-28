import SwiftUI

/// The end of the roster: the Clan's dead live in the afterlife screen, not among the living.
struct AfterlifeLinkSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let clan = model.clan {
            let afterlife = clan.guideAfterlife
            let count = clan.residents(of: afterlife).count
            Button(action: model.showAfterlife) {
                HStack {
                    Label(afterlife.label, systemImage: afterlife.symbol)
                        .font(.title2.bold())
                    Text(count, format: .number)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("The Clan's dead and its guide")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding()
                .background(.background, in: .rect(cornerRadius: 12))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(afterlife.label)")
            .padding(.top, 8)
        }
    }
}
