import SwiftUI

/// How well a neighbouring Clan gets on with the player's Clan, out of Clangen's maximum of 30.
struct ClanRelationsMeter: View {
    let clan: OtherClan

    private static let maximum = 30.0

    var body: some View {
        ProgressView(value: min(max(Double(clan.relations), 0), Self.maximum), total: Self.maximum)
            .tint(clan.standing.color)
            .accessibilityLabel("Relations")
            .accessibilityValue("\(clan.relations) out of 30")
    }
}
