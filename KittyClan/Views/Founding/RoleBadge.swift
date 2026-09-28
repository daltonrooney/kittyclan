import SwiftUI

struct RoleBadge: View {
    let role: ClanFounding.Role

    var body: some View {
        Label(role.title, systemImage: symbol)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color, in: .capsule)
            .foregroundStyle(.white)
    }

    private var symbol: String {
        switch role {
        case .leader: "crown.fill"
        case .deputy: "shield.fill"
        case .medicineCat: "leaf.fill"
        case .member: "pawprint.fill"
        }
    }

    private var color: Color {
        switch role {
        case .leader: .orange
        case .deputy: .blue
        case .medicineCat: .green
        case .member: .gray
        }
    }
}
