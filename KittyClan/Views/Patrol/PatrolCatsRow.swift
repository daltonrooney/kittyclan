import SwiftUI

struct PatrolCatsRow: View {
    @Environment(AppModel.self) private var model
    let catIDs: [Cat.ID]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(model.cats(catIDs)) { cat in
                VStack(spacing: 2) {
                    CatSprite(cat: cat)
                        .frame(width: 72, height: 72)
                        .grayscale(cat.isDead ? 0.7 : 0)
                    Text(model.displayName(cat))
                        .font(.caption.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: 84)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
