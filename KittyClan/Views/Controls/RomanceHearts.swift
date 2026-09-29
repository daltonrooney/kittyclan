import SwiftUI

/// Clangen's 0–3 romance hearts from one cat toward another.
struct RomanceHearts: View {
    let count: Int
    let direction: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index < count ? "heart.fill" : "heart")
                    .foregroundStyle(index < count ? AnyShapeStyle(.pink) : AnyShapeStyle(.tertiary))
            }
        }
        .font(.title3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(direction): \(count) of 3 hearts")
    }
}
