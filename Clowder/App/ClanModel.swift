import CoreGraphics
import Foundation
import Observation

/// Loaded game data shared by the whole app.
struct GameAssets: Sendable {
    let renderer: CatRenderer
    let factory: CatFactory

    static func loadBundled() throws -> GameAssets {
        let renderer = try CatRenderer.bundled()
        let factory = CatFactory(
            appearance: AppearanceGenerator(index: renderer.atlas.index),
            names: try NameGenerator.bundled()
        )
        return GameAssets(renderer: renderer, factory: factory)
    }

    func sprite(for cat: Cat, age: CatAge? = nil) -> CGImage? {
        try? renderer.render(cat.appearance, age: age ?? cat.age).cgImage()
    }
}

struct RenderedCat: Identifiable, Sendable {
    let cat: Cat
    let sprite: CGImage?

    var id: Cat.ID { cat.id }
}

@MainActor
@Observable
final class ClanModel {
    enum State {
        case loading
        case failed(String)
        case ready
    }

    private(set) var state = State.loading
    private(set) var cats: [RenderedCat] = []
    private(set) var assets: GameAssets?
    private(set) var isGenerating = false

    var ageFilter: CatAge?
    var catCount = 24

    func load() async {
        guard assets == nil else { return }
        do {
            assets = try await Task.detached(priority: .userInitiated) { try GameAssets.loadBundled() }.value
            state = .ready
            await generate()
        } catch {
            state = .failed(String(describing: error))
        }
    }

    func generate() async {
        guard let assets, !isGenerating else { return }
        isGenerating = true
        defer { isGenerating = false }
        let count = catCount
        let age = ageFilter
        cats = await Task.detached(priority: .userInitiated) {
            var rng = SystemRandomNumberGenerator()
            return (0..<count).map { _ in
                let cat = assets.factory.make(age: age, using: &rng)
                return RenderedCat(cat: cat, sprite: assets.sprite(for: cat))
            }
        }.value
    }

    func displayName(_ cat: Cat, age: CatAge? = nil) -> String {
        assets?.factory.names.display(cat.name, age: age ?? cat.age) ?? cat.name.prefix
    }
}
