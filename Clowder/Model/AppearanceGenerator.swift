import Foundation

/// Rolls a cat's appearance with Clangen's `Pelt.generate_new_pelt` rules, either at
/// random or inherited from parents.
struct AppearanceGenerator: Sendable {
    let index: SpriteIndex

    private static let patternCategories = ["tabbies", "spotted", "plain", "exotic"]
    private static let colourCategories = ["ginger", "black", "white", "brown"]
    private static let whiteCategories = ["little", "mid", "high", "mostly"]
    private static let disablingScars: Set<String> = [
        "NOPAW", "NOTAIL", "HALFTAIL", "NOEAR", "BOTHBLIND", "RIGHTBLIND", "LEFTBLIND",
        "BRIGHTHEART", "NOLEFTEAR", "NORIGHTEAR", "MANLEG",
    ]

    func generate(
        female: Bool,
        age: CatAge,
        parents: [CatAppearance] = [],
        using rng: inout some RandomNumberGenerator
    ) -> CatAppearance {
        var (pattern, colour, length, tortieBase, hasWhite) = parents.isEmpty
            ? randomPattern(female: female, &rng)
            : inheritedPattern(female: female, parents: parents, &rng)

        if pattern == "TwoColour" || pattern == "SingleColour" {
            pattern = hasWhite ? "TwoColour" : "SingleColour"
        } else if pattern == "Calico", !hasWhite {
            pattern = "Tortie"
        }

        // White patches, points, vitiligo
        let vitiligoParents = parents.filter { $0.vitiligo != nil }.count
        let vitiligoOdds = 1 << max(8 - vitiligoParents, 0)
        let vitiligo = oneIn(vitiligoOdds, &rng) ? pick(index.vitiligo, &rng) : nil
        var whitePatches: String?
        var points: String?
        if hasWhite {
            (whitePatches, points) = parents.isEmpty
                ? randomWhitePatches(pattern: pattern, &rng)
                : inheritedWhitePatches(pattern: pattern, parents: parents, &rng)
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

        // Scars and accessories: newly generated cats never get disabling scars
        var scars: [String] = []
        let scarOdds: Int? = switch age {
        case .newborn: nil
        case .kitten, .adolescent: 51
        case .youngAdult, .adult: 21
        case .seniorAdult, .senior: 16
        }
        if let scarOdds, oneIn(scarOdds, &rng) {
            let scar = pick(index.scars, &rng)
            if !Self.disablingScars.contains(scar) { scars.append(scar) }
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
        let eyeColour = pick(parents.map(\.eyeColour) + [pick(allEyes, &rng)], &rng)
        var heteroOdds = 120
        let highWhite = whitePatches.map { isWhite($0, in: "high") || isWhite($0, in: "mostly") } ?? false
        let fullWhite = whitePatches == "FULLWHITE" || colour == "WHITE"
        if highWhite || fullWhite { heteroOdds -= 90 }
        if fullWhite { heteroOdds -= 10 }
        heteroOdds -= 10 * parents.filter { $0.eyeColour2 != nil }.count
        if heteroOdds < 0 { heteroOdds = 1 }
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
            let base = tortieBase ?? pick(index.generation.pattern_types.keys.sorted(), &rng)
            tortieBase = base
            tortieMarking = pick(index.tortiePatches, &rng)
            if oneIn(512, &rng) {
                let nonTortie = Self.patternCategories.flatMap { index.patterns(inCategory: $0) }
                tortiePattern = pick(nonTortie, &rng)
                tortieColour = pick(index.generation.colors.keys.filter { $0 != colour }.sorted(), &rng)
            } else {
                if base == "Smoke" {
                    tortiePattern = pick(["Tabby", "Mackerel", "Classic", "SingleColour", "Smoke", "Agouti", "Ticked"], &rng)
                } else {
                    tortiePattern = weighted([(base, 97), ("SingleColour", 3)], &rng)
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
        } else {
            tortieBase = nil
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

    // MARK: - Pattern and colour

    private typealias PatternRoll = (pattern: String, colour: String, length: PeltLength, tortieBase: String?, hasWhite: Bool)

    private func randomPattern(female: Bool, _ rng: inout some RandomNumberGenerator) -> PatternRoll {
        let category = weighted(Array(zip(Self.patternCategories, [35, 20, 30, 15])), &rng)
        var pattern = pick(index.patterns(inCategory: category), &rng)
        var tortieBase: String?
        if oneIn(female ? 8 : 8192, &rng) {
            tortieBase = pattern
            pattern = pick(["Tortie", "Calico"], &rng)
        }
        let colour = pick(index.colours(inCategory: pick(Self.colourCategories, &rng)), &rng)
        let length = pick(PeltLength.allCases, &rng)
        let hasWhite = Int.random(in: 1...100, using: &rng) <= 40
        return (pattern, colour, length, tortieBase, hasWhite)
    }

    private func inheritedPattern(female: Bool, parents: [CatAppearance], _ rng: inout some RandomNumberGenerator) -> PatternRoll {
        if oneIn(16, &rng) {
            let parent = pick(parents, &rng)
            return (parent.pattern, parent.colour, parent.length, parent.tortieBase,
                    parent.whitePatches != nil || parent.points != nil)
        }

        let patternWeights: [String: [Int]] = [
            "tabbies": [50, 10, 5, 7], "spotted": [10, 50, 5, 5], "plain": [5, 5, 50, 0], "exotic": [15, 15, 1, 45],
        ]
        let colourWeights: [String: [Int]] = [
            "ginger": [40, 0, 0, 10], "black": [0, 40, 2, 5], "white": [0, 5, 40, 0], "brown": [10, 5, 0, 35],
        ]
        let lengthWeights: [PeltLength: [Int]] = [.short: [50, 10, 2], .medium: [25, 50, 25], .long: [2, 10, 50]]

        var patternTotals = [0, 0, 0, 0]
        var colourTotals = [0, 0, 0, 0]
        var lengthTotals = [0, 0, 0]
        for parent in parents {
            let base = parent.isTortie ? (parent.tortieBase ?? parent.pattern) : parent.pattern
            let category = index.generation.pattern_types[base] ?? "plain"
            add(patternWeights[category] ?? [1, 1, 1, 1], to: &patternTotals)
            add(colourWeights[index.generation.colors[parent.colour] ?? "ginger"] ?? [1, 1, 1, 1], to: &colourTotals)
            add(lengthWeights[parent.length] ?? [1, 1, 1], to: &lengthTotals)
        }

        var pattern = pick(index.patterns(inCategory: weighted(Array(zip(Self.patternCategories, nonZero(patternTotals))), &rng)), &rng)
        var tortieBase: String?
        let tortieParent = parents.contains(where: \.isTortie)
        let tortieOdds = female ? (tortieParent ? 4 : 16) : (tortieParent ? 4096 : 8192)
        if oneIn(tortieOdds, &rng) {
            tortieBase = pattern
            pattern = pick(["Tortie", "Calico"], &rng)
        }
        let colourCategory = weighted(Array(zip(Self.colourCategories, nonZero(colourTotals))), &rng)
        let colour = pick(index.colours(inCategory: colourCategory), &rng)
        let length = weighted(Array(zip(PeltLength.allCases, nonZero(lengthTotals))), &rng)

        let whiteParents = parents.filter { $0.whitePatches != nil || $0.points != nil }.count
        let whiteChance = 3 + whiteParents * (94 / parents.count)
        let hasWhite = Int.random(in: 1...100, using: &rng) <= whiteChance
        return (pattern, colour, length, tortieBase, hasWhite)
    }

    // MARK: - White patches

    private func whiteLists() -> [[String]] {
        Self.whiteCategories.map { index.whitePatches[$0] ?? [] } + [["FULLWHITE"]]
    }

    private func isWhite(_ patch: String, in category: String) -> Bool {
        (index.whitePatches[category] ?? []).contains(patch)
    }

    private func randomWhitePatches(pattern: String, _ rng: inout some RandomNumberGenerator) -> (String?, String?) {
        var points = pattern != "Tortie" && oneIn(32, &rng) ? pick(index.points, &rng) : nil
        let weights: [Int] = switch pattern {
        case "Tortie": [2, 1, 0, 0, 0]
        case "Calico": [0, 0, 20, 15, 1]
        default: [10, 10, 10, 10, 1]
        }
        let patch = pick(weighted(Array(zip(whiteLists(), weights)), &rng), &rng)
        if patch == "FULLWHITE" { points = nil }
        return (patch, points)
    }

    private func inheritedWhitePatches(pattern: String, parents: [CatAppearance], _ rng: inout some RandomNumberGenerator) -> (String?, String?) {
        let parentPatches = parents.compactMap(\.whitePatches)
        let parentPoints = parents.compactMap(\.points)

        if oneIn(16, &rng), !parentPatches.isEmpty {
            let allowed = parentPatches.filter { patch in
                switch pattern {
                case "Tortie": !isWhite(patch, in: "high") && !isWhite(patch, in: "mostly") && patch != "FULLWHITE"
                case "Calico": !isWhite(patch, in: "little") && !isWhite(patch, in: "mid")
                default: true
                }
            }
            if let patch = allowed.randomElement(using: &rng) {
                return (patch, parentPoints.randomElement(using: &rng))
            }
        }

        let pointOdds = parentPoints.isEmpty ? 40 : 10 - parentPoints.count
        var points = pattern != "Tortie" && oneIn(pointOdds, &rng)
            ? (parentPoints.randomElement(using: &rng) ?? pick(index.points, &rng))
            : nil

        var weights = [0, 0, 0, 0, 0]
        for patch in parentPatches {
            let add: [Int] = if patch == "FULLWHITE" { [0, 5, 15, 40, 10] }
                else if isWhite(patch, in: "mostly") { [5, 15, 20, 40, 5] }
                else if isWhite(patch, in: "high") { [15, 20, 40, 10, 1] }
                else if isWhite(patch, in: "mid") { [10, 40, 15, 10, 0] }
                else { [40, 20, 15, 5, 0] }
            self.add(add, to: &weights)
        }
        if parentPatches.isEmpty { weights = [50, 5, 0, 0, 0] }
        if pattern == "Tortie" { weights = Array(weights.prefix(2)) + [0, 0, 0] }
        if pattern == "Calico" { weights = [0, 0, 0] + Array(weights.suffix(2)) }

        let patch = pick(weighted(Array(zip(whiteLists(), nonZero(weights))), &rng), &rng)
        if patch == "FULLWHITE" { points = nil }
        return (patch, points)
    }

    private func add(_ values: [Int], to totals: inout [Int]) {
        for i in totals.indices where i < values.count { totals[i] += values[i] }
    }

    private func nonZero(_ weights: [Int]) -> [Int] {
        weights.allSatisfy { $0 == 0 } ? weights.map { _ in 1 } : weights
    }
}

func pick<T>(_ items: [T], _ rng: inout some RandomNumberGenerator) -> T {
    items.randomElement(using: &rng)!
}

func oneIn(_ n: Int, _ rng: inout some RandomNumberGenerator) -> Bool {
    Int.random(in: 0..<max(n, 1), using: &rng) == 0
}

func weighted<T>(_ options: [(T, Int)], _ rng: inout some RandomNumberGenerator) -> T {
    let total = options.reduce(0) { $0 + $1.1 }
    guard total > 0 else { return options[0].0 }
    var roll = Int.random(in: 0..<total, using: &rng)
    for (value, weight) in options {
        if roll < weight { return value }
        roll -= weight
    }
    return options[options.count - 1].0
}
