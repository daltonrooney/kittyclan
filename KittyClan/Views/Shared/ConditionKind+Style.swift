import SwiftUI

extension ConditionKind {
    var symbol: String {
        switch self {
        case .injury: "bandage.fill"
        case .illness: "facemask.fill"
        case .permanent: "figure.roll"
        }
    }

    var color: Color {
        switch self {
        case .injury: .orange
        case .illness: .green
        case .permanent: .purple
        }
    }

    var label: String {
        switch self {
        case .injury: "Injury"
        case .illness: "Illness"
        case .permanent: "Permanent condition"
        }
    }
}
