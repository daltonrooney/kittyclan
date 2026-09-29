import Foundation

enum MateTab: String, CaseIterable, Identifiable {
    case potential = "Potential mates"
    case mates = "Mates"

    var id: Self { self }
}
