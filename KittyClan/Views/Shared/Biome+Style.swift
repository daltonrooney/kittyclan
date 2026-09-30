import Foundation

extension Biome {
    var symbol: String {
        switch self {
        case .forest: "tree.fill"
        case .mountainous: "mountain.2.fill"
        case .plains: "sun.horizon.fill"
        case .beach: "beach.umbrella.fill"
        case .wetlands: "drop.fill"
        case .desert: "sun.dust.fill"
        }
    }

    var blurb: String {
        switch self {
        case .forest: "Tall trees, thick undergrowth and plenty of shelter."
        case .mountainous: "Rocky peaks, hidden caves and bitter winters."
        case .plains: "Open grassland under a wide sky, with nowhere to hide."
        case .beach: "Sand, tide pools and the endless roar of the sea."
        case .wetlands: "Reed beds, still water and soft mud that hides every paw print."
        case .desert: "Scorching sun, cold nights and prey that is hard to come by."
        }
    }

    func campName(_ camp: Int) -> String {
        campNames.indices.contains(camp - 1) ? campNames[camp - 1] : campNames[0]
    }

    /// "Mountains · Cavern camp"
    func label(camp: Int) -> String {
        "\(displayName) · \(campName(camp)) camp"
    }
}
