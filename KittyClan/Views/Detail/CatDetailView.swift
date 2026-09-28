import SwiftUI

struct CatDetailView: View {
    @Environment(AppModel.self) private var model
    let catID: Cat.ID

    var body: some View {
        if let cat = model.cat(catID) {
            ScrollViewReader { proxy in
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
                CatHealthSection(cat: cat)
                CatFamilySection(cat: cat)
                CatRelationshipsSection(cat: cat)
                    .id(DetailSection.relationships)
                CatAppearanceSection(appearance: cat.appearance)
                CatLifeStorySection(cat: cat)
                    .id(DetailSection.lifeStory)
            }
            #if DEBUG
            .task { scrollToDebugSection(proxy) }
            #endif
            }
            .navigationTitle(model.displayName(cat))
            .toolbarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("This cat has wandered off", systemImage: "questionmark.circle")
        }
    }

    #if DEBUG
    /// `-detailSection relationships|lifeStory` scrolls the detail sheet for screenshots.
    private func scrollToDebugSection(_ proxy: ScrollViewProxy) {
        guard let name = UserDefaults.standard.string(forKey: "detailSection"),
              let section = DetailSection(rawValue: name) else { return }
        proxy.scrollTo(section, anchor: .top)
    }
    #endif
}
