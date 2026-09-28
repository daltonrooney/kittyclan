import Foundation

/// Renders a living cat's 50×50 sprite following Clangen's `display_sprites` pipeline.
final class CatRenderer: @unchecked Sendable {
    let atlas: SpriteAtlas
    private let recipes: [String: Recipe]

    init(atlas: SpriteAtlas, recipeDirectory: URL) throws {
        self.atlas = atlas
        var recipes: [String: Recipe] = [:]
        let files = try FileManager.default.contentsOfDirectory(at: recipeDirectory, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "json" {
            let recipe = try Recipe(json: JSONSerialization.jsonObject(with: Data(contentsOf: file)))
            recipes[recipe.name] = recipe
        }
        self.recipes = recipes
    }

    static func bundled() throws -> CatRenderer {
        let atlas = try SpriteAtlas.bundled()
        guard let recipes = Bundle.main.url(forResource: "Sprites/recipes", withExtension: nil) else {
            throw SpriteError.missingSheet("recipes")
        }
        return try CatRenderer(atlas: atlas, recipeDirectory: recipes)
    }

    func render(_ cat: CatAppearance, age: CatAge) throws -> PixelBuffer {
        try render(cat, poseName: cat.pose(for: age))
    }

    func render(_ cat: CatAppearance, poseName: String) throws -> PixelBuffer {
        let index = atlas.index
        guard let pose = index.poseIndex(poseName) else {
            throw SpriteError.unknownSprite(sheet: "poses", name: poseName)
        }

        var sprite = try buildPelt(cat.pattern, colour: cat.colour, pose: pose, poseName: poseName, cat: cat)

        if let tint = index.tint.tint_colours[cat.tint], let color = RGB(components: tint) {
            sprite.apply(color, .multiplyRGB)
        }
        if let tint = index.tint.dilute_tint_colours?[cat.tint], let color = RGB(components: tint) {
            sprite.apply(color, .addRGB)
        }
        if let tint = index.tint.remove_tone_tint_colours?[cat.tint], let color = RGB(components: tint) {
            sprite.apply(color, .subtractRGB)
        }

        let whiteTint = cat.whitePatchesTint
            .flatMap { index.whitePatchesTint.tint_colours[$0] ?? nil }
            .flatMap { RGB(components: $0) }

        if let patch = cat.whitePatches {
            let category = index.whitePatchCategory(of: patch) ?? "little"
            var white = try atlas.sprite("patches_white_\(category)", patch, pose: pose)
            if let whiteTint { white.apply(whiteTint, .multiplyRGB) }
            sprite.blit(white)
        }
        if let points = cat.points {
            var layer = try atlas.sprite("patches_points", points, pose: pose)
            if let whiteTint { layer.apply(whiteTint, .multiplyRGB) }
            sprite.blit(layer)
        }
        if let vitiligo = cat.vitiligo {
            sprite.blit(try atlas.sprite("patches_vitiligo", vitiligo, pose: pose))
        }

        sprite.blit(try atlas.sprite("eyes", cat.eyeColour, pose: pose))
        if let second = cat.eyeColour2 {
            var eye = try atlas.sprite("eyes", second, pose: pose)
            eye.blit(try atlas.sprite("heterochromiamask", "", pose: pose), .maskRGBA)
            sprite.blit(eye)
        }

        let missingParts = Set(index.missingPartScars)
        for scar in cat.scars where !missingParts.contains(scar) {
            sprite.blit(try atlas.sprite("scars", scar, pose: pose))
        }

        sprite.blit(try atlas.sprite("lineart", "", pose: pose))
        sprite.blit(try atlas.sprite("skin", cat.skin, pose: pose))

        for scar in cat.scars where missingParts.contains(scar) {
            sprite.blit(try atlas.sprite("scars_missing_part", scar, pose: pose), .minRGBA)
        }

        // Clangen files "head" accessories under body, so only three categories draw.
        for parts in [["tail"], ["body", "head"], ["paw"]] {
            for accessory in cat.accessories {
                guard let part = index.accessoryBodyParts[accessory], parts.contains(part) else { continue }
                let sheet = index.plants.contains(accessory) ? "acc_plants" : "acc_wilds"
                sprite.blit(try atlas.sprite(sheet, accessory, pose: pose))
            }
        }

        return cat.reverse ? sprite.flippedHorizontally() : sprite
    }

    // MARK: - Pelt recipes

    private func buildPelt(_ pattern: String, colour: String, pose: Int, poseName: String, cat: CatAppearance) throws -> PixelBuffer {
        let key = pattern.prefix(1).uppercased() + pattern.dropFirst()
        guard let recipeName = atlas.index.peltToRecipe[key], let base = recipes[recipeName] else {
            throw SpriteError.unknownSprite(sheet: "recipes", name: pattern)
        }
        let recipe = base.applyingException(colour: colour, pose: poseName)
        let context = LayerContext(recipe: recipe, colour: colour, pose: pose, poseName: poseName, cat: cat)
        return try buildLayers(recipe.layerOrder, context).buffer
    }

    private struct LayerContext {
        let recipe: Recipe
        let colour: String
        let pose: Int
        let poseName: String
        let cat: CatAppearance
    }

    private struct Layer {
        var buffer: PixelBuffer
        var blend: PixelBuffer.Blend
    }

    private func buildLayers(_ node: Any, _ context: LayerContext) throws -> Layer {
        if var children = node as? [Any] {
            var blendName = "normal"
            var opacity = 100
            if let last = children.last as? String, last.hasPrefix("+") {
                children.removeLast()
                for pair in last.dropFirst().split(separator: ",") {
                    let kv = pair.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    guard kv.count == 2 else { continue }
                    if kv[0] == "blend_mode" { blendName = kv[1] }
                    if kv[0] == "opacity", let value = Int(kv[1]) { opacity = value }
                }
            }
            var group = PixelBuffer()
            for child in children {
                let layer = try buildLayers(child, context)
                group.blit(layer.buffer, layer.blend)
            }
            return Layer(buffer: group, blend: Self.blend(blendName, opacity: opacity))
        }

        guard let key = node as? String, let info = context.recipe.layers[key] else {
            throw SpriteError.unknownSprite(sheet: context.recipe.name, name: "\(node)")
        }
        return try buildSingleLayer(info, context)
    }

    private func buildSingleLayer(_ info: [String: Any], _ context: LayerContext) throws -> Layer {
        func resolve(_ value: Any?) -> String? {
            guard let string = value as? String else { return nil }
            if string.hasPrefix("{"), string.hasSuffix("}") {
                return context.cat.field(String(string.dropFirst().dropLast()))
            }
            return string
        }
        let opacity = (info["opacity"] as? NSNumber)?.intValue ?? 100

        if let peltName = resolve(info["pelt_name"]) {
            let palette = resolve(info["palette"]) ?? context.colour
            let pelt = try buildPelt(peltName, colour: palette, pose: context.pose, poseName: context.poseName, cat: context.cat)
            // Clangen reads the misspelled key "blendmode" here, so nested pelts always blend normally.
            return Layer(buffer: pelt, blend: .normal(opacity: opacity))
        }

        let sheet = (info["spritesheet"] as? String) ?? "pelt_parts_masks"
        guard let group = resolve(info["group_name"]) else {
            throw SpriteError.unknownSprite(sheet: sheet, name: "\(info)")
        }
        var mask = try atlas.sprite(sheet, group, pose: context.pose)
        if let colorKey = info["color"] as? String {
            guard let hex = atlas.index.palettes[context.colour]?[colorKey], let color = RGB(hex: hex) else {
                throw SpriteError.unknownSprite(sheet: "palette \(context.colour)", name: colorKey)
            }
            var fill = PixelBuffer.fill(color)
            fill.blit(mask, .maskRGBA)
            mask = fill
        }
        return Layer(buffer: mask, blend: Self.blend(info["blend_mode"] as? String ?? "normal", opacity: opacity))
    }

    private static func blend(_ name: String, opacity: Int) -> PixelBuffer.Blend {
        switch name {
        case "mask": .maskRGBA
        case "multiply": .multiplyRGB
        default: .normal(opacity: opacity)
        }
    }
}

/// A Clangen pelt recipe: a tree of recoloured mask layers plus colour/pose exceptions.
struct Recipe: @unchecked Sendable {
    let name: String
    let layerOrder: [Any]
    let layers: [String: [String: Any]]
    let exceptions: [[String: Any]]

    init(json: Any) throws {
        guard let dict = json as? [String: Any],
              let name = dict["name"] as? String,
              let order = dict["layer_order"] as? [Any],
              let layers = dict["layers"] as? [String: [String: Any]]
        else { throw SpriteError.unknownSprite(sheet: "recipes", name: "malformed recipe") }
        self.name = name
        layerOrder = order
        self.layers = layers
        exceptions = dict["exceptions"] as? [[String: Any]] ?? []
    }

    private init(name: String, layerOrder: [Any], layers: [String: [String: Any]]) {
        self.name = name
        self.layerOrder = layerOrder
        self.layers = layers
        exceptions = []
    }

    /// Picks the single best-matching exception (later ones win ties) and merges it in.
    func applyingException(colour: String, pose: String) -> Recipe {
        func matches(_ condition: Any?, _ value: String) -> Bool {
            if let s = condition as? String { return s == value }
            if let list = condition as? [String] { return list.contains(value) }
            return false
        }

        var best: [String: Any]?
        var bestCount = 0
        for exception in exceptions {
            var needed = 0
            var matched = 0
            if let colors = exception["colors"] {
                needed += 1
                if matches(colors, colour) { matched += 1 }
            }
            if let poses = exception["poses"] {
                needed += 1
                if matches(poses, pose) { matched += 1 }
            }
            if matched == needed, matched >= bestCount {
                best = exception
                bestCount = matched
            }
            if bestCount == 2 { break }
        }
        guard let best else { return self }

        var mergedLayers = layers
        for (key, value) in best["layers"] as? [String: [String: Any]] ?? [:] {
            mergedLayers[key, default: [:]].merge(value) { _, new in new }
        }
        return Recipe(name: name, layerOrder: best["layer_order"] as? [Any] ?? layerOrder, layers: mergedLayers)
    }
}
