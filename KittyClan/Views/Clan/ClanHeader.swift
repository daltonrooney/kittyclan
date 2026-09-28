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
                    HStack(spacing: 16) {
                        Label("Moon \(clan.age) · \(clan.season.rawValue)", systemImage: clan.season.symbol)
                        if clan.isAlive(clan.leader) {
                            Label("^[\(clan.leaderLives) life](inflect: true) left", systemImage: "heart.fill")
                                .foregroundStyle(.red)
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
