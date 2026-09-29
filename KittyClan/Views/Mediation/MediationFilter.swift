import Foundation

/// Which cats the mediation picker shows, by how the other chosen cat feels about them.
enum MediationFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case positive = "Positive"
    case negative = "Negative"

    var id: Self { self }

    func includes(_ relationship: Relationship?) -> Bool {
        let total = relationship?.total ?? 0
        switch self {
        case .all: return true
        case .positive: return total > 0
        case .negative: return total < 0
        }
    }
}
