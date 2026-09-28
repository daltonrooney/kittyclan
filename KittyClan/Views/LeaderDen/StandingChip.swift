import SwiftUI

struct StandingChip: View {
    let standing: OtherClan.Standing

    var body: some View {
        Label(standing.label, systemImage: standing.symbol)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(standing.color.opacity(0.2), in: .capsule)
            .foregroundStyle(standing.color)
    }
}
