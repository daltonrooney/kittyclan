import SwiftUI

struct ClanStatusLabels: View {
    let clan: Clan

    var body: some View {
        Label("Moon \(clan.age) · \(clan.season.rawValue)", systemImage: clan.season.symbol)
            .lineLimit(1)
        if clan.isAlive(clan.leader) {
            Label("^[\(clan.leaderLives) life](inflect: true) left", systemImage: "heart.fill")
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }
}
