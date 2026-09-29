import CoreGraphics
import Foundation

/// A den in Clangen's camp screen.
enum Den: String, CaseIterable, Sendable {
    case nursery, leader = "leader den", elder = "elder den", medicine = "medicine den"
    case apprentice = "apprentice den", clearing, warrior = "warrior den"
}

/// One of Clangen's forest camps: den label positions and the spots cats sit in,
/// in the 800×700 canvas the backgrounds are stretched to.
struct CampLayout: Sendable {
    struct Spot: Hashable, Sendable {
        let point: CGPoint
        /// "x", "y" or "xy": which way a second cat on this spot is nudged.
        let tag: String
    }

    static let canvas = CGSize(width: 800, height: 700)

    let labels: [Den: CGPoint]
    let spots: [Den: [Spot]]

    init?(_ json: [String: Any]) {
        var labels: [Den: CGPoint] = [:]
        var spots: [Den: [Spot]] = [:]
        for den in Den.allCases {
            if let point = json[den.rawValue] as? [Double], point.count == 2 {
                labels[den] = CGPoint(x: point[0], y: point[1])
            }
            let places = json["\(den.rawValue) place"] as? [[Any]] ?? []
            spots[den] = places.compactMap { entry in
                guard entry.count == 2, let point = entry[0] as? [Double], point.count == 2, let tag = entry[1] as? String else { return nil }
                return Spot(point: CGPoint(x: point[0], y: point[1]), tag: tag)
            }
            // Clangen has a nursery spot off the canvas that silently swallows a kitten.
            .filter { $0.point.x >= 0 && $0.point.x + 50 <= Self.canvas.width && $0.point.y >= 0 && $0.point.y + 50 <= Self.canvas.height }
        }
        guard !spots.isEmpty else { return nil }
        self.labels = labels
        self.spots = spots
    }
}

/// Clangen's forest camps (Classic, Gully, Grotto, Lakeside) and their seasonal backgrounds.
struct CampLibrary: Sendable {
    static let names = ["Classic", "Gully", "Grotto", "Lakeside"]

    let layouts: [Int: CampLayout]
    private let directory: URL

    init(directory: URL) throws {
        self.directory = directory
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: "layouts.json"))) as? [String: [String: Any]] ?? [:]
        let fallback = json["default"].flatMap(CampLayout.init)
        var layouts: [Int: CampLayout] = [:]
        for camp in 1...4 {
            layouts[camp] = json["Forestcamp\(camp)"].flatMap(CampLayout.init) ?? fallback
        }
        self.layouts = layouts
    }

    static func bundled() throws -> CampLibrary {
        guard let url = Bundle.main.url(forResource: "Camps", withExtension: nil) else { throw SpriteError.missingSheet("Camps") }
        return try CampLibrary(directory: url)
    }

    /// The background for a camp in a season, light or dark.
    func background(camp: Int, season: Season, dark: Bool) -> URL {
        let seasonKey = season.rawValue.lowercased().replacingOccurrences(of: "-", with: "")
        return directory.appending(path: "\(seasonKey)_camp\(camp)_\(dark ? "dark" : "light").png")
    }

    /// Clangen's `choose_cat_positions`: each spot holds up to two cats, dens are chosen by
    /// rank weights, and when a den fills, cats spill into others. Newborns hide.
    func place(_ cats: [Cat], camp: Int, using rng: inout some RandomNumberGenerator) -> [(cat: UUID, point: CGPoint)] {
        guard let layout = layouts[camp] ?? layouts[1] else { return [] }
        let order: [Den] = [.nursery, .leader, .elder, .medicine, .apprentice, .clearing, .warrior]
        var free = layout.spots.mapValues { $0 + $0 }
        var placed: [(UUID, CGPoint)] = []

        for cat in cats where cat.isAlive && cat.rank != .newborn {
            let weights: [Int] = switch cat.rank {
            case .apprentice, .mediatorApprentice: [1, 50, 1, 1, 100, 100, 1]
            case .deputy: [1, 50, 1, 1, 1, 50, 1]
            case .elder: [1, 1, 2000, 1, 1, 1, 1]
            case .kitten: [60, 8, 1, 1, 1, 1, 1]
            case .medicineCat, .medicineApprentice: [20, 20, 20, 400, 1, 1, 1]
            case .leader: [1, 200, 1, 1, 1, 1, 1]
            default: [1, 1, 1, 1, 1, 60, 60]
            }
            var dens = Array(zip(order, weights))
            var spot: CampLayout.Spot?
            var second = false
            while spot == nil, !dens.isEmpty {
                let index = weighted(Array(zip(dens.indices, dens.map(\.1))), &rng)
                let den = dens[index].0
                guard var list = free[den], !list.isEmpty else {
                    dens.remove(at: index)
                    continue
                }
                let chosen = list.remove(at: Int.random(in: 0..<list.count, using: &rng))
                second = !list.contains(chosen)
                free[den] = list
                spot = chosen
            }
            guard let spot else { break }
            var point = spot.point
            if second {
                if spot.tag.contains("x"), !spot.tag.contains("y") || Int.random(in: 0..<4, using: &rng) != 0 {
                    point.x += 15 * (Bool.random(using: &rng) ? 1 : -1)
                }
                if spot.tag.contains("y") { point.y += 15 }
            }
            placed.append((cat.id, point))
        }
        return placed
    }
}
