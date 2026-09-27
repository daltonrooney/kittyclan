import Foundation

extension ClanFounding.Role {
    var title: String {
        switch self {
        case .leader: "Leader"
        case .deputy: "Deputy"
        case .medicineCat: "Medicine cat"
        case .member: "Member"
        }
    }

    var requiresExperience: Bool { self != .member }

    /// The rank a cat shows while holding this role, for name display.
    func displayRank(for cat: Cat) -> Rank {
        switch self {
        case .leader: .leader
        case .deputy: .deputy
        case .medicineCat: .medicineCat
        case .member: cat.rank
        }
    }
}
