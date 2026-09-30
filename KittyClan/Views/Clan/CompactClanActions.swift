import SwiftUI

/// Patrol and Timeskip along the bottom of the clan screen on narrow screens, within reach of a thumb.
struct CompactClanActions: View {
    var body: some View {
        HStack(spacing: 12) {
            PatrolButton()
                .frame(maxWidth: .infinity)
            TimeskipButton()
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
