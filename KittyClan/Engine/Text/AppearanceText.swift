import Foundation

/// Clangen's `describe_appearance` and `describe_cat`, e.g. "a scarred, long-furred, brown tabby tom, with vitiligo".
struct AppearanceText: Sendable {
    private let strings: [String: Entry]

    private enum Entry: Decodable, Sendable {
        case plain(String)
        case plural(one: String, many: String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .plain(text)
            } else {
                let forms = try container.decode([String: String].self)
                self = .plural(one: forms["one"] ?? "", many: forms["many"] ?? forms["one"] ?? "")
            }
        }
    }

    static let blackColours: Set = ["GREY", "DARKGREY", "GHOST", "BLACK"]
    static let brownColours: Set = ["LIGHTBROWN", "LILAC", "BROWN", "GOLDEN-BROWN", "MALLOW", "DARKBROWN", "CHOCOLATE", "RUST"]
    static let whiteColours: Set = ["WHITE", "PALEGREY", "SILVER"]
    static let mostlyWhite: Set = [
        "VAN", "APRON", "BLACKSTAR", "CAPSADDLE", "EYESPOT", "LIGHTSONG", "ONEEAR", "PETAL", "FULLWHITE", "TAILTWO",
        "BUTLESS", "PEBBLESHINE", "TAIL", "HEART", "MOORISH", "CHESTSPECK", "HEARTTWO", "BOOTS", "COW", "COWTWO",
        "LOVEBUG", "SHOOTINGSTAR", "PEBBLE", "BUDDY", "KROPKA",
    ]
    static let tabbyBases: Set = ["tabby", "ticked", "mackerel", "classic", "sokoke", "agouti", "bengal", "rosette", "speckled"]
    /// Missing parts, in the order they're listed.
    static let amputations = ["NOTAIL", "HALFTAIL", "NOPAW", "NOLEFTEAR", "NORIGHTEAR", "NOEAR"]

    init(url: URL) throws {
        strings = try JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: url))
    }

    /// The description with "a" or "an" in front, as Clangen's `describe_cat` gives it.
    func describeCat(_ cat: Cat, short: Bool = false) -> String {
        let text = describe(cat, short: short)
        guard let first = text.first else { return text }
        return ("aeiou".contains(first.lowercased()) ? "an " : "a ") + text
    }

    /// Clangen's `describe_appearance`. `short` leaves out colours and details, e.g. "tabby she-cat".
    func describe(_ cat: Cat, short: Bool = false) -> String {
        let a = cat.appearance
        let (patternKey, colour) = pattern(of: a, short: short)
        let pelt = string(patternKey, many: !short).replacing("%{color}", with: colour)

        let details = short ? [] : [
            a.scars.count >= 3 ? string("scarred") : nil,
            a.length == .long ? string("long_furred") : nil,
        ].compactMap(\.self)
        var extras: [String] = []
        if !short {
            if a.vitiligo != nil { extras.append(string("vitiligo")) }
            let missing = Self.amputations.filter(a.scars.contains).map { string($0) }
            let unique = missing.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            if !unique.isEmpty { extras.append(Self.list(unique)) }
        }

        var output = details.isEmpty ? "" : details.joined(separator: ", ") + ", "
        output += [pelt, cat.genderAlign.noun].filter { !$0.isEmpty }.joined(separator: " ")
        if !extras.isEmpty { output += ", with " + Self.list(extras) }
        return output
    }

    /// Clangen's `adjust_list_text`: "a", "a and b", "a, b and c".
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    private func pattern(of a: CatAppearance, short: Bool) -> (key: String, colour: String) {
        var key = short ? a.pattern : a.pattern + "_long"
        var colour = string(a.colour, many: false)
        if a.isTortie {
            let dark = Self.blackColours.union(Self.brownColours).union(Self.whiteColours)
            let mottled = dark.contains(a.colour) && dark.contains(a.tortieColour ?? "")
            if short {
                key = mottled ? "mottled" : a.pattern
                colour = ""
            } else if mottled {
                colour += "/" + string(a.tortieColour ?? "", many: false)
                key = "mottled_long"
            } else {
                colour += "/" + string(a.tortieColour ?? "", many: false)
                if Self.tabbyBases.contains((a.tortieBase ?? "").lowercased()) {
                    key = a.pattern + "_tabby_long"
                }
            }
        }

        if let white = a.whitePatches {
            let fullWhite = string("FULLWHITE")
            if white == "FULLWHITE" {
                return ("SingleColour_long", fullWhite)
            } else if a.pattern != "Calico" {
                if colour.contains(string("WHITE", many: false)) {
                    colour = fullWhite
                } else if Self.mostlyWhite.contains(white) {
                    colour = Self.list([fullWhite, colour])
                } else {
                    colour = Self.list([colour, fullWhite])
                }
            }
        }
        if a.points != nil {
            colour = string("point").replacing("%{color}", with: colour).replacing("ginger point", with: "flame point")
        }
        return (key, colour)
    }

    private func string(_ key: String, many: Bool = false) -> String {
        switch strings[key] {
        case .plain(let text): text
        case .plural(let one, let many2): many ? many2 : one
        case nil: key
        }
    }
}
