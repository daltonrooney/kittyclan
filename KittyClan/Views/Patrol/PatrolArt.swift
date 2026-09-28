import ImageIO
import SwiftUI

/// Patrol pixel art loaded from the bundle and scaled up without smoothing.
struct PatrolArt: View {
    @Environment(AppModel.self) private var model
    let name: String?

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
            } else {
                Color(.tertiarySystemFill)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 16))
        .accessibilityHidden(true)
        .task(id: name) {
            image = await Self.load(model.patrolArtURL(name))
        }
    }

    @concurrent
    private static func load(_ url: URL?) async -> CGImage? {
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
