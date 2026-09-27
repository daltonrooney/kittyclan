import Foundation

enum CatAge: String, Codable, CaseIterable, Sendable {
    case newborn
    case kitten
    case adolescent
    case youngAdult = "young adult"
    case adult
    case seniorAdult = "senior adult"
    case senior

    var moons: ClosedRange<Int> {
        switch self {
        case .newborn: 0...0
        case .kitten: 1...5
        case .adolescent: 6...11
        case .youngAdult: 12...47
        case .adult: 48...95
        case .seniorAdult: 96...119
        case .senior: 120...Int.max
        }
    }

    var label: String { rawValue.capitalized }
}

enum PeltLength: String, Codable, CaseIterable, Sendable {
    case short, medium, long
}

/// Everything that determines how a cat looks. Field values are Clangen's identifiers
/// (e.g. pattern "Tabby", colour "GINGER"), so the sprite data can be used unchanged.
struct CatAppearance: Codable, Hashable, Sendable {
    var pattern: String
    var colour: String
    var length: PeltLength
    var eyeColour: String
    var eyeColour2: String?
    var whitePatches: String?
    var points: String?
    var vitiligo: String?
    var tortieBase: String?
    var tortiePattern: String?
    var tortieColour: String?
    var tortieMarking: String?
    var skin: String
    var scars: [String] = []
    var accessories: [String] = []
    var tint: String
    var whitePatchesTint: String?
    var reverse: Bool
    /// Pose name per age, e.g. "adult" → "adult_long1".
    var poses: [String: String]

    var isTortie: Bool { pattern == "Tortie" || pattern == "Calico" }

    func pose(for age: CatAge) -> String {
        poses[age.rawValue] ?? "adult_short0"
    }

    /// Resolves a recipe `{field}` placeholder.
    func field(_ name: String) -> String? {
        switch name {
        case "colour": colour
        case "tortie_base": tortieBase
        case "tortie_pattern": tortiePattern
        case "tortie_colour": tortieColour
        case "tortie_marking": tortieMarking
        default: nil
        }
    }
}
