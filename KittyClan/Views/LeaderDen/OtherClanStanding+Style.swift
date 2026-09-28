import SwiftUI

extension OtherClan.Standing {
    var label: String {
        switch self {
        case .ally: "Allies"
        case .neutral: "Neutral"
        case .hostile: "Hostile"
        }
    }

    var color: Color {
        switch self {
        case .ally: .green
        case .neutral: .blue
        case .hostile: .red
        }
    }

    var symbol: String {
        switch self {
        case .ally: "heart.fill"
        case .neutral: "circle.dashed"
        case .hostile: "exclamationmark.triangle.fill"
        }
    }
}
