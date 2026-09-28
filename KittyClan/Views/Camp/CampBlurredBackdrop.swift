import SwiftUI

/// The camp art enlarged and blurred to fill the space around the canvas.
struct CampBlurredBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    let image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 24)
            }
            Color(white: colorScheme == .dark ? 0.1 : 0.6)
                .opacity(colorScheme == .dark ? 0.45 : 0.25)
        }
        .accessibilityHidden(true)
    }
}
