import CoreGraphics
import Foundation

/// Loaded game data and the engines built on it, shared by the whole app.
struct GameAssets: Sendable {
    let renderer: CatRenderer
    let factory: CatFactory
    let founding: ClanFounding
    let engine: MoonEngine

    static func loadBundled() throws -> GameAssets {
        let renderer = try CatRenderer.bundled()
        let names = try NameGenerator.bundled()
        guard let text = Bundle.main.url(forResource: "Text", withExtension: nil) else {
            throw SpriteError.missingSheet("Text")
        }
        let factory = CatFactory(
            appearance: AppearanceGenerator(index: renderer.atlas.index),
            names: names,
            traits: try TraitTable(url: text.appending(path: "trait_ranges.json"))
        )
        let library = try EventLibrary(directory: text)
        let narrator = ClangenNarrator(
            library: library,
            template: TextTemplate(pronouns: try PronounTable(url: text.appending(path: "pronouns.en.json")), names: names),
            fallback: BasicNarrator(names: names)
        )
        return GameAssets(
            renderer: renderer,
            factory: factory,
            founding: ClanFounding(factory: factory),
            engine: MoonEngine(factory: factory, narrator: narrator, library: library)
        )
    }

    var names: NameGenerator { factory.names }

    func displayName(_ cat: Cat) -> String {
        names.display(cat.name, rank: cat.rank)
    }

    func sprite(for cat: Cat, age: CatAge? = nil) -> CGImage? {
        try? renderer.render(cat.appearance, age: age ?? cat.age).cgImage()
    }
}
