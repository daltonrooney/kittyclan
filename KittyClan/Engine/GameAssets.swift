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
        let template = TextTemplate(pronouns: try PronounTable(url: text.appending(path: "pronouns.en.json")), names: names)
        let narrator = ClangenNarrator(library: library, template: template, fallback: BasicNarrator(names: names))
        let relationships = RelationshipEngine(library: try InteractionLibrary(directory: text), template: template)
        return GameAssets(
            renderer: renderer,
            factory: factory,
            founding: ClanFounding(factory: factory),
            engine: MoonEngine(factory: factory, narrator: narrator, library: library, relationships: relationships)
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
