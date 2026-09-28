import SwiftUI

/// Red "Lost" or "Exiled" tags for cats who used to be in the Clan.
struct OutsiderTags: View {
    let cat: Cat

    var body: some View {
        HStack(spacing: 4) {
            if cat.isLost { tag("Lost") }
            if cat.isExiled { tag("Exiled") }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.red, in: .capsule)
            .foregroundStyle(.white)
    }
}
