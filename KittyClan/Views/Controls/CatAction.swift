import Foundation

/// A player control opened from a cat's profile.
enum CatAction: String, Identifiable {
    case role, mentor, mate, rename

    var id: Self { self }
}
