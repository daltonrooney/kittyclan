import Foundation

enum LeaderDenTab: String, CaseIterable, Identifiable {
    case clans, outsiders

    var id: Self { self }

    var title: String {
        switch self {
        case .clans: "Other Clans"
        case .outsiders: "Outsiders"
        }
    }
}
