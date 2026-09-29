import Foundation

/// Where the Clan lives. Raw values are Clangen's save strings.
enum Biome: String, Codable, CaseIterable, Sendable {
    case forest = "Forest", mountainous = "Mountainous", plains = "Plains", beach = "Beach"

    /// Folder, file and location-tag name, e.g. "mountainous".
    var key: String { rawValue.lowercased() }
    var displayName: String { self == .mountainous ? "Mountains" : rawValue }

    var campNames: [String] {
        switch self {
        case .forest: ["Classic", "Gully", "Grotto", "Lakeside"]
        case .mountainous: ["Cliff", "Cavern", "Crystal River", "Ruins"]
        case .plains: ["Grasslands", "Tunnels", "Wastelands", "Bridge"]
        case .beach: ["Tidepools", "Tidal Cave", "Shipwreck", "Fjord"]
        }
    }
}
