import Foundation

struct SpriteKey: Hashable, Sendable {
    let cat: Cat.ID
    let age: CatAge
    let appearance: CatAppearance
}
