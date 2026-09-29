import Foundation

extension Rank {
    var sectionTitle: String {
        switch self {
        case .leader: "Leader"
        case .deputy: "Deputy"
        case .medicineCat: "Medicine Cats"
        case .medicineApprentice: "Medicine Cat Apprentices"
        case .mediator: "Mediators"
        case .mediatorApprentice: "Mediator Apprentices"
        case .warrior: "Warriors"
        case .apprentice: "Apprentices"
        case .elder: "Elders"
        case .kitten: "Kits"
        case .newborn: "Newborns"
        }
    }
}
