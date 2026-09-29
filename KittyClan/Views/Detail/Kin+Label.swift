import Foundation

extension Kin.Kind {
    /// The row caption for a relative, e.g. "Half-sibling" or "Aunt", worded by their gender.
    func label(for relative: Cat) -> String {
        let pick = { (she: String, he: String, they: String) in
            switch relative.genderAlign {
            case .female, .transFemale: she
            case .male, .transMale: he
            default: they
            }
        }
        return switch self {
        case .parent: pick("Mother", "Father", "Parent")
        case .adoptiveParent: pick("Adoptive mother", "Adoptive father", "Adoptive parent")
        case .grandparent: pick("Grandmother", "Grandfather", "Grandparent")
        case .siblingsKit: pick("Niece", "Nephew", "Sibling's kit")
        case .auntOrUncle: pick("Aunt", "Uncle", "Parent's sibling")
        case .mate: "Mate"
        case .formerMate: "Former mate"
        case .kit: "Kit"
        case .adoptiveKit: "Adopted kit"
        case .grandkit: "Grandkit"
        case .sibling: "Sibling"
        case .halfSibling: "Half-sibling"
        case .littermate: "Littermate"
        case .adoptiveSibling: "Adoptive sibling"
        case .cousin: "Cousin"
        }
    }
}
