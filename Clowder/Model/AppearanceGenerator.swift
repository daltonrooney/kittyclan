import Foundation

/// Rolls a random cat's appearance with Clangen's `Pelt.generate_new_pelt` odds (no parents).
struct AppearanceGenerator: Sendable {
    let index: SpriteIndex

    private static let patternWeights: [(category: String, weight: Int)] = [
        ("tabbies", 35), ("spotted", 20), ("plain", 30), ("exotic", 15),
    ]
    private static let noDisablingScars: Set<String> = [
        "NOPAW", "NOTAIL", "HALFTAIL", "NOEAR", "BOTHBLIND", "RIGHTBLIND", "LEFTBLIND",
        "BRIGHTHEART", "NOLEFTEAR", "NORIGHTEAR", "MANLEG",
    ]

    func generate(female: Bool, age: CatAge, using rng: inout some RandomNumberGenerator) -> CatAppearance {
        // Pattern and colour
        var pattern = pick(index.patterns(inCategory: weighted(Self.patternWeights, &rng)), &rng)
        var tortieBase: String?
        if oneIn(female ? 8 : 8192, &rng) {
            tortieBase = pattern
            pattern = pick(["Tortie", "Calico"], &rng)
        }
        var colour = pick(index.colours(inCategory: pick(["ginger", "black", "white", "brown"], &rng)), &rng)
        let length = pick(PeltLength.allCases, &rng)
        let hasWhite = Int.random(in: 1...100, using: &rng) <= 40
        if pattern == "TwoColour" || pattern == "SingleColour" {
            pattern = hasWhite ? "TwoColour" : "SingleColour"
        } else if pattern == "Calico", !hasWhite {
            pattern = "Tortie"
        }

        // White patches, points, vitiligo
        let vitiligo = oneIn(256, &rng) ? pick(index.vitiligo, &rng) : nil
        var whitePatches: String?
        var points: String?
        if hasWhite {
            if pattern != "Tortie", oneIn(32, &rng) { points = pick(index.points, &rng) }
            let weights: [Int] = switch pattern {
            case "Tortie": [2, 1, 0, 0, 0]
            case "Calico": [0, 0, 20, 15, 1]
            default: [10, 10, 10, 10, 1]
            }
            let lists = ["little", "mid", "high", "mostly"].map { index.whitePatches[$0] ?? [] } + [["FULLWHITE"]]
            whitePatches = pick(weighted(Array(zip(lists, weights)), &rng), &rng)
            if whitePatches == "FULLWHITE" { points = nil }
        }

        // Poses, skin, reverse
        let reverse = Bool.random(using: &rng)
        let skin = pick(index.skins, &rng)
        let long = length == .long
        let adultPose = pick((0...2).map { long ? "adult_long\($0)" : "adult_short\($0)" }, &rng)
        let poses: [String: String] = [
            CatAge.newborn.rawValue: pick(["newborn0", "newborn1", "newborn2"], &rng),
            CatAge.kitten.rawValue: pick(["kitten0", "kitten1", "kitten2"], &rng),
            CatAge.adolescent.rawValue: pick((0...2).map { long ? "adolescent_long\($0)" : "adolescent_short\($0)" }, &rng),
            CatAge.youngAdult.rawValue: adultPose,
            CatAge.adult.rawValue: adultPose,
            CatAge.seniorAdult.rawValue: adultPose,
            CatAge.senior.rawValue: pick(["senior0", "senior1", "senior2"], &rng),
        ]

        // Scars and accessories (founding cats never get disabling scars)
        var scars: [String] = []
        let scarOdds: Int? = switch age {
        case .newborn: nil
        case .kitten, .adolescent: 51
        case .youngAdult, .adult: 21
        case .seniorAdult, .senior: 16
        }
        if let scarOdds, oneIn(scarOdds, &rng) {
            let scar = pick(index.scars, &rng)
            if !Self.noDisablingScars.contains(scar) { scars.append(scar) }
        }
        var accessories: [String] = []
        let accessoryOdds: Int? = switch age {
        case .newborn: nil
        case .kitten, .adolescent: 181
        case .youngAdult, .adult: 101
        case .seniorAdult, .senior: 81
        }
        if let accessoryOdds, oneIn(accessoryOdds, &rng) {
            accessories.append(pick(index.plants + index.wild, &rng))
        }

        // Eyes
        let eyeGroups = index.eyeGroups
        let allEyes = ["yellow", "green", "blue"].flatMap { eyeGroups[$0] ?? [] }
        let eyeColour = pick(allEyes, &rng)
        var heteroOdds = 120
        let highWhite = whitePatches.map { (index.whitePatches["high"] ?? []).contains($0) || (index.whitePatches["mostly"] ?? []).contains($0) } ?? false
        let fullWhite = whitePatches == "FULLWHITE" || colour == "WHITE"
        if highWhite || fullWhite { heteroOdds -= 90 }
        if fullWhite { heteroOdds -= 10 }
        var eyeColour2: String?
        if Int.random(in: 0...heteroOdds, using: &rng) == 0 {
            let otherGroups = ["yellow", "blue", "green"].filter { !(eyeGroups[$0] ?? []).contains(eyeColour) }
            eyeColour2 = pick(eyeGroups[pick(otherGroups, &rng)] ?? [eyeColour], &rng)
        }

        // Tortie details
        var tortiePattern: String?
        var tortieColour: String?
        var tortieMarking: String?
        if pattern == "Tortie" || pattern == "Calico" {
            let allPatterns = index.generation.pattern_types.keys.sorted()
            tortieBase = tortieBase ?? pick(allPatterns, &rng)
            tortieMarking = pick(index.tortiePatches, &rng)
            if oneIn(512, &rng) {
                let nonTortie = ["exotic", "tabbies", "spotted", "plain"].flatMap { index.patterns(inCategory: $0) }
                tortiePattern = pick(nonTortie, &rng)
                tortieColour = pick(index.generation.colors.keys.filter { $0 != colour }.sorted(), &rng)
            } else {
                if tortieBase == "Smoke" {
                    tortiePattern = pick(["Tabby", "Mackerel", "Classic", "SingleColour", "Smoke", "Agouti", "Ticked"], &rng)
                } else {
                    tortiePattern = weighted([(tortieBase!, 97), ("SingleColour", 3)], &rng)
                }
                if colour == "WHITE" { colour = pick(["PALEGREY", "SILVER"], &rng) }
                let ginger = index.colours(inCategory: "ginger")
                let brown = index.colours(inCategory: "brown")
                let black = index.colours(inCategory: "black")
                tortieColour = switch index.generation.colors[colour] {
                case "black", "white": pick(ginger + ginger + brown, &rng)
                case "ginger": pick(brown + black + black, &rng)
                default: pick(brown.filter { $0 != colour } + black + ginger + ginger, &rng)
                }
            }
        }

        // Tints
        let tintTable = index.tint
        let tintGroup = tintTable.colour_groups[colour].flatMap { tintTable.possible_tints[$0] } ?? []
        let tint = pick((tintTable.possible_tints["basic"] ?? []) + tintGroup, &rng)
        var whitePatchesTint: String?
        if whitePatches != nil || points != nil {
            let table = index.whitePatchesTint
            let group = table.colour_groups[colour] ?? "white"
            whitePatchesTint = pick((table.possible_tints["basic"] ?? []) + (table.possible_tints[group] ?? []), &rng)
        }

        return CatAppearance(
            pattern: pattern, colour: colour, length: length,
            eyeColour: eyeColour, eyeColour2: eyeColour2,
            whitePatches: whitePatches, points: points, vitiligo: vitiligo,
            tortieBase: tortieBase, tortiePattern: tortiePattern, tortieColour: tortieColour, tortieMarking: tortieMarking,
            skin: skin, scars: scars, accessories: accessories,
            tint: tint, whitePatchesTint: whitePatchesTint,
            reverse: reverse, poses: poses
        )
    }
}

func pick<T>(_ items: [T], _ rng: inout some RandomNumberGenerator) -> T {
    items.randomElement(using: &rng)!
}

func oneIn(_ n: Int, _ rng: inout some RandomNumberGenerator) -> Bool {
    Int.random(in: 0..<n, using: &rng) == 0
}

func weighted<T>(_ options: [(T, Int)], _ rng: inout some RandomNumberGenerator) -> T {
    let total = options.reduce(0) { $0 + $1.1 }
    var roll = Int.random(in: 0..<total, using: &rng)
    for (value, weight) in options {
        if roll < weight { return value }
        roll -= weight
    }
    return options[options.count - 1].0
}
