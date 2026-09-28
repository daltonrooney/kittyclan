import SwiftUI

struct CatDetailView: View {
    @Environment(AppModel.self) private var model
    let catID: Cat.ID

    var body: some View {
        if let cat = model.cat(catID) {
            List {
                Section {
                    CatSprite(cat: cat)
                        .frame(maxWidth: 220)
                        .frame(maxWidth: .infinity)
                        .grayscale(cat.isDead ? 0.7 : 0)
                        .accessibilityLabel("\(model.displayName(cat)), \(cat.age.label)")
                        .listRowBackground(Color.clear)
                }
                CatAgesSection(cat: cat)
                CatAboutSection(cat: cat)
                CatFamilySection(cat: cat)
                CatAppearanceSection(appearance: cat.appearance)
                CatLifeStorySection(cat: cat)
            }
            .navigationTitle(model.displayName(cat))
            .toolbarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("This cat has wandered off", systemImage: "questionmark.circle")
        }
    }
}
