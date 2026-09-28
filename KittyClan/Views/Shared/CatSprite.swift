import SwiftUI

/// A cat's pixel sprite, rendered in the background and cached.
struct CatSprite: View {
    @Environment(AppModel.self) private var model
    let cat: Cat
    var age: CatAge?
    /// A colour blended over the sprite's pixels, like light from its surroundings.
    var shade: Color?
    var shadeStrength = 0.0

    @State private var image: CGImage?

    var body: some View {
        let key = SpriteCache.key(for: cat, age: age)
        let shown = model.sprites?.cached(key) ?? image
        Group {
            if let shown {
                PixelSprite(image: shown)
                    .overlay {
                        if let shade {
                            shade
                                .opacity(shadeStrength)
                                .mask { PixelSprite(image: shown) }
                        }
                    }
            } else {
                Color.clear.aspectRatio(1, contentMode: .fit)
            }
        }
        .task(id: key) {
            image = await model.sprites?.image(for: cat, age: age)
        }
    }
}
