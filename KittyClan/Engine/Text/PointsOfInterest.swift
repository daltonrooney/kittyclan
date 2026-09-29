import Foundation

/// An event's `poi` block: the points of interest it can take place at.
struct PoiRequirement: Sendable {
    let names: [String]
    let tags: [String]
    let category: String?

    init?(_ json: [String: Any]?) {
        guard let json else { return nil }
        names = json["name"] as? [String] ?? []
        tags = json["tags"] as? [String] ?? []
        category = (json["category"] as? [String])?.first ?? json["category"] as? String
        if names.isEmpty, tags.isEmpty, category == nil { return nil }
    }

    /// Clangen's patrol and text-pool weight: more for fewer named places, else for each tag.
    var weight: Int {
        if !names.isEmpty { return 8 - 2 * names.count }
        return min(4, tags.count)
    }
}

/// Clangen's points of interest (`points_of_interest.json`): gathering places, moonplaces and
/// landmarks, some found only in certain biomes. Each Clan knows one gathering place, one
/// moonplace and three landmarks.
struct PointsOfInterest: Sendable {
    struct Place: Sendable {
        let category: String
        let biomes: [String]
        let tags: [String]
    }

    let places: [String: Place]
    let names: [String: String]

    init(directory: URL) throws {
        let data = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: "points_of_interest.json"))) as? [String: [String: Any]] ?? [:]
        places = data.compactMapValues { json in
            guard let category = json["category"] as? String else { return nil }
            return Place(category: category, biomes: json["biome"] as? [String] ?? ["any"], tags: json["tags"] as? [String] ?? [])
        }
        names = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: "points_of_interest.en.json"))) as? [String: String] ?? [:]
    }

    /// The display name, e.g. "the Moonpool".
    func name(_ id: String) -> String { names[id] ?? id.replacingOccurrences(of: "_", with: " ") }

    /// Clangen's `generate_and_add_new_poi` for a new Clan: a gathering place, a moonplace and three landmarks.
    func generate(for biome: Biome, using rng: inout some RandomNumberGenerator) -> [String] {
        var chosen: [String] = []
        for category in ["gathering", "moonplace", "terrain", "terrain", "terrain"] {
            let options = places.filter { id, place in
                !chosen.contains(id) && place.category == category
                    && !Set(place.biomes).isDisjoint(with: ["any", biome.key])
            }
            .keys.sorted()
            if let id = options.randomElement(using: &rng) { chosen.append(id) }
        }
        return chosen
    }

    /// A place's tags, plus the part before ":" of tags like "water:still".
    private func tags(of id: String) -> Set<String> {
        let tags = places[id]?.tags ?? []
        return Set(tags + tags.compactMap { $0.split(separator: ":", maxSplits: 1).count > 1 ? String($0.split(separator: ":")[0]) : nil })
    }

    /// Clangen's `get_poi_from_constraints`: the Clan's places matching every given constraint.
    func matches(_ requirement: PoiRequirement, known: [String]) -> [String] {
        known.filter { id in
            (requirement.names.isEmpty || requirement.names.contains(id))
                && (requirement.tags.isEmpty || !tags(of: id).isDisjoint(with: requirement.tags))
                && (requirement.category.map { places[id]?.category == $0 } ?? true)
        }
    }

    /// Clangen's `event_for_poi`.
    func allows(_ requirement: PoiRequirement?, in clan: Clan) -> Bool {
        guard let requirement else { return true }
        return !matches(requirement, known: clan.pointsOfInterest).isEmpty
    }

    /// A place for this event, or nil if the Clan knows none that fit.
    func choose(_ requirement: PoiRequirement, in clan: Clan, using rng: inout some RandomNumberGenerator) -> String? {
        matches(requirement, known: clan.pointsOfInterest).randomElement(using: &rng)
    }
}

extension Clan {
    /// Points of interest for Clans from before KittyClan had them.
    mutating func ensurePointsOfInterest(_ places: PointsOfInterest?, using rng: inout some RandomNumberGenerator) {
        guard pointsOfInterest.isEmpty, let places else { return }
        pointsOfInterest = places.generate(for: biome, using: &rng)
    }
}
