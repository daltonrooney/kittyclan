import SwiftUI

struct ClanHeader: View {
    @Environment(AppModel.self) private var model
    let showsLogButton: Bool
    let showLog: () -> Void

    var body: some View {
        if let clan = model.clan {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 20) {
                    ClanSymbolImage(symbol: clan.symbol)
                        .frame(width: 100, height: 100)
                    info(clan)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    buttons
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 16) {
                        ClanSymbolImage(symbol: clan.symbol)
                            .frame(width: 72, height: 72)
                        info(clan)
                    }
                    HStack(spacing: 12) {
                        Spacer(minLength: 0)
                        buttons
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    private func info(_ clan: Clan) -> some View {
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
            ClanHeaderActions()
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if showsLogButton {
            Button("Moon log", systemImage: "book.pages", action: showLog)
                .labelStyle(.iconOnly)
                .font(.title2)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
        }
        PatrolButton()
            .fixedSize()
        TimeskipButton()
            .fixedSize()
        ClanMenu()
            .labelStyle(.iconOnly)
            .font(.title2)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
    }
}
