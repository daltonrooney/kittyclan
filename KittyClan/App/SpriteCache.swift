import CoreGraphics
import Foundation

/// Rendered sprites keyed by cat and age, rendered off the main actor and shared across views.
@MainActor
final class SpriteCache {
    private let assets: GameAssets
    private var images: [SpriteKey: CGImage] = [:]
    private var pending: [SpriteKey: Task<CGImage?, Never>] = [:]

    init(assets: GameAssets) {
        self.assets = assets
    }

    static func key(for cat: Cat, age: CatAge?) -> SpriteKey {
        SpriteKey(cat: cat.id, age: age ?? cat.age, appearance: cat.appearance)
    }

    func cached(_ key: SpriteKey) -> CGImage? {
        images[key]
    }

    func image(for cat: Cat, age: CatAge?) async -> CGImage? {
        let key = Self.key(for: cat, age: age)
        if let image = images[key] { return image }
        if let task = pending[key] { return await task.value }

        let assets = assets
        let task = Task { await Self.render(cat, age: key.age, assets: assets) }
        pending[key] = task
        let image = await task.value
        pending[key] = nil
        images[key] = image
        return image
    }

    @concurrent
    private static func render(_ cat: Cat, age: CatAge, assets: GameAssets) async -> CGImage? {
        assets.sprite(for: cat, age: age)
    }
}
