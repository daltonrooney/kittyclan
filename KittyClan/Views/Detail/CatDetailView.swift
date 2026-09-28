import SwiftUI

struct CatDetailView: View {
    @Environment(AppModel.self) private var model
    let catID: Cat.ID

    var body: some View {
        if let cat = model.cat(catID) {
            let isOutsider = model.isOutsider(cat)
            ScrollViewReader { proxy in
            List {
                Section {
                    CatSprite(cat: cat)
                        .frame(maxWidth: 220)
                        .frame(maxWidth: .infinity)
                        .grayscale(cat.isDead && cat.afterlife == nil ? 0.7 : 0)
                        .accessibilityLabel("\(model.displayName(cat)), \(cat.age.label)")
                        .listRowBackground(Color.clear)
                }
                if cat.isDead {
                    CatAfterlifeSection(cat: cat)
                        .id(DetailSection.afterlife)
                }
                if model.isLeader(cat) {
                    CatCeremonySection(cat: cat)
                        .id(DetailSection.ceremony)
                }
                CatAgesSection(cat: cat)
                CatAboutSection(cat: cat, isOutsider: isOutsider)
                if cat.isDead {
                    CatDeathHistorySection(cat: cat)
                        .id(DetailSection.history)
                } else {
                    CatHealthSection(cat: cat)
                }
                CatFamilySection(cat: cat)
                if !isOutsider, cat.isAlive {
                    CatRelationshipsSection(cat: cat)
                        .id(DetailSection.relationships)
                }
                CatAppearanceSection(appearance: cat.appearance)
                if !model.isGuide(cat) {
                    CatLifeStorySection(cat: cat)
                        .id(DetailSection.lifeStory)
                }
                if !isOutsider, cat.isAlive {
                    CatExileSection(cat: cat)
                        .id(DetailSection.exile)
                }
            }
            #if DEBUG
            .task { scrollToDebugSection(proxy) }
            #endif
            }
            .navigationTitle(cat.isDead ? "\(model.displayName(cat)) (dead)" : model.displayName(cat))
            .toolbarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("This cat has wandered off", systemImage: "questionmark.circle")
        }
    }

    #if DEBUG
    /// `-detailSection afterlife|history|ceremony|relationships|lifeStory|exile` scrolls the detail sheet for screenshots.
    private func scrollToDebugSection(_ proxy: ScrollViewProxy) {
        guard let name = UserDefaults.standard.string(forKey: "detailSection"),
              let section = DetailSection(rawValue: name) else { return }
        proxy.scrollTo(section, anchor: .top)
    }
    #endif
}
