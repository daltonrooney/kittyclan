import SwiftUI

/// Small corner badges for a cat who is hurt or ill, or lives with a permanent condition.
struct HealthBadges: View {
    let cat: Cat

    var body: some View {
        HStack(spacing: 2) {
            if cat.hasVisibleSickness {
                badge("cross.case.fill", .red)
            }
            if cat.hasVisiblePermanentCondition {
                badge(ConditionKind.permanent.symbol, ConditionKind.permanent.color)
            }
        }
        .font(.caption.bold())
        .padding(2)
        .accessibilityHidden(true)
    }

    private func badge(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(color, in: .circle)
    }
}
