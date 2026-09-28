import SwiftUI

struct WarBadge: View {
    var body: some View {
        Label("At war", systemImage: "flag.2.crossed.fill")
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.red, in: .capsule)
            .foregroundStyle(.white)
    }
}
