import Foundation

/// A heading in the family tree and the kinds of kin listed under it.
enum FamilyGroup: String, CaseIterable, Identifiable {
    case parents = "Parents"
    case mates = "Mates"
    case kits = "Kits"
    case siblings = "Siblings"
    case grandparents = "Grandparents"
    case grandkits = "Grandkits"
    case auntsAndUncles = "Aunts & Uncles"
    case nephewsAndNieces = "Nephews & Nieces"
    case cousins = "Cousins"
    case formerMates = "Former mates"

    var id: Self { self }

    /// Closest kind first.
    var kinds: [Kin.Kind] {
        switch self {
        case .parents: [.parent]
        case .mates: [.mate]
        case .kits: [.kit]
        case .siblings: [.littermate, .sibling, .halfSibling]
        case .grandparents: [.grandparent]
        case .grandkits: [.grandkit]
        case .auntsAndUncles: [.auntOrUncle]
        case .nephewsAndNieces: [.siblingsKit]
        case .cousins: [.cousin]
        case .formerMates: [.formerMate]
        }
    }

    /// This group's relatives from a family tree, closest kind first.
    func members(of family: [Kin]) -> [Kin] {
        kinds.flatMap { kind in family.filter { $0.kind == kind } }
    }

    /// The groups shown on the profile itself; the rest wait in the full tree.
    static let close: [FamilyGroup] = [.parents, .mates, .kits, .siblings]
}
