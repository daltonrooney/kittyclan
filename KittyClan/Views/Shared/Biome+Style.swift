import Foundation

extension Biome {
    var symbol: String {
        switch self {
        case .forest: "tree.fill"
        case .mountainous: "mountain.2.fill"
        case .plains: "sun.horizon.fill"
        case .beach: "beach.umbrella.fill"
        }
    }

    var blurb: String {
        switch self {
        case .forest: "Tall trees, thick undergrowth and plenty of shelter."
        case .mountainous: "Rocky peaks, hidden caves and bitter winters."
        case .plains: "Open grassland under a wide sky, with nowhere to hide."
        case .beach: "Sand, tide pools and the endless roar of the sea."
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
