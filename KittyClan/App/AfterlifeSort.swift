import Foundation

/// How the afterlife screen orders its residents. The guide always comes first.
enum AfterlifeSort: String, CaseIterable, Identifiable {
    case rank
    case death
    case name

    var id: Self { self }

    var title: String {
        switch self {
        case .rank: "Rank"
        case .death: "Longest dead"
        case .name: "Name"
        }
    }

    var symbol: String {
        switch self {
        case .rank: "list.number"
        case .death: "hourglass"
        case .name: "textformat"
        }
    }
}
