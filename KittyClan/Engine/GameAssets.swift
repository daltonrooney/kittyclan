import CoreGraphics
import Foundation

/// Loaded game data and the engines built on it, shared by the whole app.
struct GameAssets: Sendable {
    let renderer: CatRenderer
    let factory: CatFactory
    let founding: ClanFounding
    let engine: MoonEngine
    let patrols: PatrolEngine
    let skillText: SkillText

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
        let engine = MoonEngine(
            factory: factory, narrator: narrator, library: library, relationships: relationships,
            conditions: try ConditionLibrary(directory: text),
            herbLibrary: try HerbLibrary(directory: text)
        )
        let patrolLibrary = try PatrolLibrary(directory: text, artDirectory: Bundle.main.url(forResource: "PatrolArt", withExtension: nil))
        return GameAssets(
            renderer: renderer,
            factory: factory,
            founding: ClanFounding(factory: factory),
            engine: engine,
            patrols: PatrolEngine(library: patrolLibrary, engine: engine, template: template),
            skillText: try SkillText(url: text.appending(path: "skills.en.json"))
        )
    }

    var names: NameGenerator { factory.names }

    func displayName(_ cat: Cat) -> String {
        names.display(cat.name, rank: cat.rank)
    }

    /// The cat's sprite at an age. At its current age a sick or paralyzed cat uses Clangen's special poses.
    func sprite(for cat: Cat, age: CatAge? = nil) -> CGImage? {
        try? renderer.render(cat.appearance, poseName: Self.poseName(for: cat, age: age ?? cat.age)).cgImage()
    }

    static func poseName(for cat: Cat, age: CatAge) -> String {
        guard age == cat.age, age != .newborn, cat.isAlive else { return cat.appearance.pose(for: age) }
        if cat.isNotWorking {
            return switch age {
            case .kitten: "sick_kitten0"
            case .adolescent: "sick_adolescent0"
            case .senior: "sick_senior0"
            default: "sick_adult0"
            }
        }
        if cat.isParalyzed {
            if age == .kitten || age == .adolescent { return "para_young0" }
            return cat.appearance.length == .long ? "para_adult_long0" : "para_adult_short0"
        }
        return cat.appearance.pose(for: age)
    }
}
