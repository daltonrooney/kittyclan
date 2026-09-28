import Foundation

/// A leader's den choice, named by the engine's interaction strings.
enum DenAction: String, CaseIterable, Identifiable {
    case befriend, provoke, praise, offend, appease, antagonize
    case hunt, drive, invite, search

    var id: Self { self }

    var title: String {
        switch self {
        case .hunt: "Hunt down"
        case .drive: "Drive off"
        case .invite: "Invite in"
        case .search: "Search for"
        default: rawValue.capitalized
        }
    }

    var explanation: String {
        switch self {
        case .befriend: "Be kind at the next Gathering to grow closer."
        case .provoke: "Stir up trouble at the Gathering. They'll like your Clan less."
        case .praise: "Say nice things about your allies to stay good friends."
        case .offend: "Insult your allies. They might stop trusting you."
        case .appease: "Try to calm things down and make peace."
        case .antagonize: "Pick a fight. This could lead to war!"
        case .hunt: "This cat will be killed if found."
        case .drive: "This cat will be driven out of the area if found."
        case .invite: "This cat will join the Clan if found."
        case .search: "This cat will come home to the Clan if found."
        }
    }

    var systemImage: String {
        switch self {
        case .befriend: "hand.wave.fill"
        case .provoke: "flame.fill"
        case .praise: "star.fill"
        case .offend: "hand.thumbsdown.fill"
        case .appease: "leaf.fill"
        case .antagonize: "bolt.fill"
        case .hunt: "scope"
        case .drive: "arrow.up.right.circle.fill"
        case .invite: "house.fill"
        case .search: "magnifyingglass"
        }
    }

    var isFriendly: Bool {
        [.befriend, .praise, .appease, .invite, .search].contains(self)
    }

    /// Clangen's phrasing after "has decided to", e.g. "hunt Mothfur down".
    func phrase(_ target: String) -> String {
        switch self {
        case .hunt: "hunt \(target) down"
        case .drive: "drive \(target) off"
        case .invite: "invite \(target) in"
        case .search: "search for \(target)"
        default: "\(rawValue) \(target)"
        }
    }
}
