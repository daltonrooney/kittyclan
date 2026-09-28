import Foundation

struct SpriteKey: Hashable, Sendable {
    let cat: Cat.ID
    let age: CatAge
    let appearance: CatAppearance
    /// Changes when the cat is sick or paralyzed, which uses a different pose.
    let pose: String
    /// Set for dead cats, whose sprites change with their afterlife and fading.
    var ghost: CatRenderer.Ghost? = nil
}
