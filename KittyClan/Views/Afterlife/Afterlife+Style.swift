import SwiftUI

extension Afterlife {
    var symbol: String {
        switch self {
        case .starClan: "sparkles"
        case .darkForest: "moon.fill"
        case .unknownResidence: "cloud.fog.fill"
        }
    }

    var tint: Color {
        switch self {
        case .starClan: .indigo
        case .darkForest: .red
        case .unknownResidence: .gray
        }
    }

    var backgroundURL: URL? {
        let file = switch self {
        case .starClan: "starclanbg.png"
        case .darkForest: "darkforestbg.png"
        case .unknownResidence: "urbg.png"
        }
        return Bundle.main.url(forResource: "Afterlife", withExtension: nil)?.appending(path: file)
    }

    var emptyTitle: String {
        switch self {
        case .starClan: "StarClan is quiet"
        case .darkForest: "The Dark Forest is empty"
        case .unknownResidence: "No one wanders here"
        }
    }

    var emptyMessage: String {
        switch self {
        case .starClan: "No cats watch over the Clan from StarClan yet."
        case .darkForest: "No cats walk the Dark Forest. Cats who turn from the warrior code may end up here."
        case .unknownResidence: "Cats who die outside the Clans, and never reach StarClan or the Dark Forest, wander here."
        }
    }
}
