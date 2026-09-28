import Foundation

/// One herb in the medicine den, with how well stocked it is for the Clan's size.
struct HerbStock: Identifiable {
    /// The herb's key, e.g. "cobwebs".
    let id: String
    let name: String
    let count: Int
    /// Clangen's rating: empty, low, adequate, full or excess.
    let rating: String
}
