import SwiftUI

/// One camp to choose at founding: its Newleaf art and its name.
struct CampPreviewCard: View {
    let name: String
    let url: URL
    let isSelected: Bool
    let select: () -> Void

    @State private var image: CGImage?

    var body: some View {
        Button(action: select) {
            VStack(spacing: 10) {
                Group {
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .interpolation(.none)
                    } else {
                        Color.secondary.opacity(0.2)
                    }
                }
                .aspectRatio(CampLayout.canvas.width / CampLayout.canvas.height, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 14))
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .tint)
                            .padding(10)
                    }
                }
                Text(name)
                    .font(.title2.bold())
            }
            .padding(12)
            .background(.background, in: .rect(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 4)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) camp")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .task(id: url) {
            image = await CampBackdrop.loadImage(url)
        }
    }
}
