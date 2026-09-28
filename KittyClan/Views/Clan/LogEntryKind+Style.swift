import SwiftUI

extension LogEntry.Kind {
    var symbol: String {
        switch self {
        case .ceremony: "star.fill"
        case .birth: "sparkles"
        case .death: "moon.zzz.fill"
        case .join: "pawprint.fill"
        case .relationship: "heart.fill"
        case .info: "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .ceremony: .purple
        case .birth: .pink
        case .death: .gray
        case .join: .teal
        case .relationship: .red
        case .info: .blue
        }
    }

    var label: String {
        switch self {
        case .ceremony: "Ceremony"
        case .birth: "Birth"
        case .death: "Death"
        case .join: "New arrival"
        case .relationship: "Relationship"
        case .info: "News"
        }
    }
}
