import Foundation

extension Cat {
    /// An outsider's way of life, e.g. "Loner".
    var socialLabel: String {
        social.rawValue.capitalized
    }

    /// Why a former Clan cat is outside the Clan.
    var outsiderNote: String? {
        if isExiled { return "Exiled" }
        if isLost { return "Lost from the Clan" }
        return nil
    }
}
