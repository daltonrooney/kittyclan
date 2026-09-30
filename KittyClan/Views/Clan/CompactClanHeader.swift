import SwiftUI

/// The clan screen's header on narrow screens: the Clan's name and status beside the options menu,
/// its supplies, den and afterlife buttons in a scrolling row, and the camp, cats and moons switch.
struct CompactClanHeader: View {
    @Environment(AppModel.self) private var model
    @Binding var tab: CompactClanTab

    var body: some View {
        if let clan = model.clan {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    ClanSymbolImage(symbol: clan.symbol)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(clan.displayName)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                ClanStatusLabels(clan: clan)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                ClanStatusLabels(clan: clan)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    ClanMenu()
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                }
                .padding(.horizontal)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        SuppliesButton()
                        LeaderDenButton()
                        AfterlifeButton()
                        WarBanner()
                    }
                    .controlSize(.small)
                    .padding(.horizontal)
                }
                .scrollIndicators(.hidden)
                Picker("View", selection: $tab) {
                    ForEach(CompactClanTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }
            .padding(.vertical, 10)
            .background(.bar)
        }
    }
}
