import SwiftUI

/// The cat's big sprite standing on Clangen's profile platform for its biome and season,
/// a nest when it's a newborn or too unwell to work, or its afterlife once it has died.
struct CatProfilePortrait: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let cat: Cat

    var body: some View {
        let size = ProfilePlatform.size
        let origin = ProfilePlatform.spriteOrigin
        let platform = model.clan.map { ProfilePlatform(for: cat, in: $0, dark: colorScheme == .dark) }
        GeometryReader { proxy in
            let scale = proxy.size.width / Double(size.width)
            ZStack(alignment: .topLeading) {
                if let platform, let image = PresentationArt.shared.platform(platform) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                CatSprite(cat: cat)
                    .frame(width: 50 * scale, height: 50 * scale)
                    .offset(x: Double(origin.x) * scale, y: Double(origin.y) * scale)
            }
        }
        .aspectRatio(Double(size.width) / Double(size.height), contentMode: .fit)
    }
}
