import SwiftUI

/// Supplies, the leader's den, the afterlife, and the war banner, wrapping onto more lines when space is short.
struct ClanHeaderActions: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                SuppliesButton()
                LeaderDenButton()
                AfterlifeButton()
                WarBanner()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    SuppliesButton()
                    LeaderDenButton()
                    AfterlifeButton()
                }
                WarBanner()
            }
            VStack(alignment: .leading, spacing: 8) {
                SuppliesButton()
                LeaderDenButton()
                AfterlifeButton()
                WarBanner()
            }
        }
    }
}
