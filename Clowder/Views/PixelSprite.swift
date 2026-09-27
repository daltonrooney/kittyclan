import SwiftUI

/// A 50×50 cat sprite scaled up with nearest-neighbour sampling so pixels stay crisp.
struct PixelSprite: View {
    let image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .resizable()
                    .foregroundStyle(.tertiary)
                    .padding()
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
