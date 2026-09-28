import SwiftUI

/// A cat sitting in camp. Tapping it opens the cat's profile.
struct CampCatButton: View {
    @Environment(AppModel.self) private var model
    let cat: Cat
    let shade: Color?
    let size: CGFloat

    var body: some View {
        Button(action: select) {
            CatSprite(cat: cat, shade: shade, shadeStrength: CampBackdrop.shadeStrength)
                .frame(width: size, height: size)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.displayName(cat)), \(cat.rank.label)")
    }

    private func select() {
        model.selectedCat = cat
    }
}
