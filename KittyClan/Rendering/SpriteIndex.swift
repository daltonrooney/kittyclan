import Foundation

/// Decoded `Sprites/index.json`, produced by `tools/export_assets.py` from Clangen's sprite tables.
struct SpriteIndex: Decodable, Sendable {
    struct Generation: Decodable, Sendable {
        /// Colour name → category (white, black, ginger, brown).
        let colors: [String: String]
        /// Pattern name → category (tabbies, spotted, plain, exotic, torties).
        let pattern_types: [String: String]
    }

    struct TintTable: Decodable, Sendable {
        let colour_groups: [String: String]
        let possible_tints: [String: [String]]
        let tint_colours: [String: [Int]?]
        let dilute_tint_colours: [String: [Int]?]?
        let remove_tone_tint_colours: [String: [Int]?]?
    }

    /// A collar style's group on `acc_collars` and its palette: every colour row is applied
    /// over `base` column by column, like Clangen's `apply_palettes`.
    struct CollarStyle: Decodable, Sendable {
        let style: String
        let row: Int
        let col: Int
        /// RGBA per palette column.
        let base: [[UInt8]]
        /// Colour name → RGBA per palette column.
        let colours: [String: [[UInt8]]]
    }

    /// Clangen's display forms for an accessory or collar style: `zero` on the profile, `one` and `many` in events.
    struct AccessoryName: Decodable, Sendable {
        let zero: String
        let one: String
        let many: String
    }

    let poses: [String]
    /// Sheet → [[name, row, col]] where the first element is a string and the rest ints.
    let sheets: [String: [SheetEntry]]
    let accessoryBodyParts: [String: String]
    let plants: [String]
    let wild: [String]
    /// Every collar id (`STYLE_colour`) in Clangen's `Pelt.collar_accessories` order.
    let collars: [String]
    let collarStyles: [CollarStyle]
    let accessoryNames: [String: AccessoryName]
    let eyeGroups: [String: [String]]
    let whitePatches: [String: [String]]
    let whitePatchCombos: [String: [String]]
    let tortiePatches: [String]
    let tortiePatchCombos: [String: [String]]
    let points: [String]
    let vitiligo: [String]
    let skins: [String]
    let scars: [String]
    let missingPartScars: [String]
    let generation: Generation
    let peltToRecipe: [String: String]
    let palettes: [String: [String: String]]
    let tint: TintTable
    let whitePatchesTint: TintTable

    struct SheetEntry: Decodable, Sendable {
        let name: String
        let row: Int
        let col: Int

        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            name = try c.decode(String.self)
            row = try c.decode(Int.self)
            col = try c.decode(Int.self)
        }
    }

    static func load(from directory: URL) throws -> SpriteIndex {
        let data = try Data(contentsOf: directory.appending(path: "index.json"))
        return try JSONDecoder().decode(SpriteIndex.self, from: data)
    }

    func poseIndex(_ pose: String) -> Int? {
        poses.firstIndex(of: pose)
    }

    func colours(inCategory category: String) -> [String] {
        generation.colors.filter { $0.value == category }.map(\.key).sorted()
    }

    func patterns(inCategory category: String) -> [String] {
        generation.pattern_types.filter { $0.value == category }.map(\.key).sorted()
    }

    /// The style of a collar id, e.g. "LEATHER_BELL" for "LEATHER_BELL_crimson1".
    func collarStyle(of id: String) -> CollarStyle? {
        collarStyles.first { id.hasPrefix($0.style + "_") && $0.colours[String(id.dropFirst($0.style.count + 1))] != nil }
    }

    /// Clangen's display name for an accessory; collars are named by their style.
    func accessoryName(_ id: String, form: KeyPath<AccessoryName, String> = \.zero) -> String {
        let key = collarStyle(of: id)?.style ?? id
        return accessoryNames[key]?[keyPath: form] ?? id.replacing("_", with: " ").lowercased()
    }

    func whitePatchCategory(of patch: String) -> String? {
        ["mostly", "high", "mid", "little"].first { whitePatches[$0]?.contains(patch) == true }
    }
}
