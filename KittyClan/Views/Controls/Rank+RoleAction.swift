import Foundation

extension Rank {
    /// The Role Screen's button for moving a cat into this rank.
    var roleAction: String {
        switch self {
        case .leader: "Make leader"
        case .deputy: "Make deputy"
        case .medicineCat: "Make medicine cat"
        case .warrior: "Make warrior"
        case .elder: "Retire to the elders' den"
        case .medicineApprentice: "Switch to medicine cat apprentice"
        case .mediator: "Make mediator"
        case .mediatorApprentice: "Switch to mediator apprentice"
        case .apprentice: "Switch to warrior apprentice"
        case .newborn, .kitten: label
        }
    }

    var roleSymbol: String {
        switch self {
        case .leader: "star.fill"
        case .deputy: "shield.fill"
        case .medicineCat, .medicineApprentice: "cross.case.fill"
        case .mediator, .mediatorApprentice: "bubble.left.and.bubble.right.fill"
        case .warrior, .apprentice: "figure.walk"
        case .elder: "moon.zzz.fill"
        case .newborn, .kitten: "pawprint.fill"
        }
    }

    /// Changes that can't easily be undone and are confirmed first.
    var needsRoleConfirmation: Bool {
        self == .leader || self == .elder
    }
}
