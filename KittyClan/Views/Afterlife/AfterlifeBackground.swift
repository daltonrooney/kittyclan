import SwiftUI

/// An afterlife's art filling the screen, pixels kept crisp, dimmed so the cats stand out.
struct AfterlifeBackground: View {
    let afterlife: Afterlife
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
            }
            Color.black.opacity(0.2)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task(id: afterlife) {
            image = nil
            if let url = afterlife.backgroundURL {
                image = await CampBackdrop.loadImage(url)
            }
        }
    }
}
