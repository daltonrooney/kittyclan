import Foundation

/// A player control opened from a cat's profile.
enum CatAction: String, Identifiable {
    case role, mentor, mate
    case adoptiveParents = "adopt"
    case gender, rename, mediate

    var id: Self { self }
}
