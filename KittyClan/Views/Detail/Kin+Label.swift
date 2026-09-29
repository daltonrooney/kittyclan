import Foundation

extension Kin.Kind {
    /// The row caption for a relative, e.g. "Half-sibling" or "Aunt", worded by their pronouns.
    func label(for relative: Cat) -> String {
        let pick = { (she: String, he: String, they: String) in
            switch relative.pronouns {
            case .she: she
            case .he: he
            case .they: they
            }
        }
        return switch self {
        case .parent: pick("Mother", "Father", "Parent")
        case .grandparent: pick("Grandmother", "Grandfather", "Grandparent")
        case .siblingsKit: pick("Niece", "Nephew", "Sibling's kit")
        case .auntOrUncle: pick("Aunt", "Uncle", "Parent's sibling")
        case .mate: "Mate"
        case .formerMate: "Former mate"
        case .kit: "Kit"
        case .grandkit: "Grandkit"
        case .sibling: "Sibling"
        case .halfSibling: "Half-sibling"
        case .littermate: "Littermate"
        case .cousin: "Cousin"
        }
    }
}
