import SwiftUI

struct ClanHeader: View {
    @Environment(AppModel.self) private var model
    let showsLogButton: Bool
    let showLog: () -> Void

    var body: some View {
        if let clan = model.clan {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(clan.displayName)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            ClanStatusLabels(clan: clan)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            ClanStatusLabels(clan: clan)
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if showsLogButton {
                    Button("Moon log", systemImage: "book.pages", action: showLog)
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                }
                PatrolButton()
                TimeskipButton()
                ClanMenu()
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }
}
