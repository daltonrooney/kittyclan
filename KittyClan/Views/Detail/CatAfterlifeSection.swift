import SwiftUI

/// Where a dead cat rests, how long they've been gone, and whether they may fade.
struct CatAfterlifeSection: View {
    @Environment(AppModel.self) private var model
    let cat: Cat

    var body: some View {
        let isGuide = model.isGuide(cat)
        Section {
            if isGuide {
                Label("Guiding ghost", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
            }
            if let afterlife = cat.afterlife {
                LabeledContent("Resides in") {
                    Text("\(Image(systemName: afterlife.symbol)) \(afterlife.label)")
                }
            }
            if let rank = model.pastRank(of: cat) {
                LabeledContent("Rank", value: rank.capitalizedFirst)
            }
            if let deadFor = model.deadFor(cat) {
                LabeledContent("Gone", value: deadFor.capitalizedFirst)
            }
            if isGuide, let backstory = model.backstory(of: cat) {
                Text(backstory)
                    .font(.callout)
            }
            if !isGuide {
                Toggle("Prevent fading", isOn: preventFading)
                    .disabled(model.isAdvancing)
            }
        } header: {
            Text("Afterlife")
        } footer: {
            if !isGuide {
                Text(model.clan?.fading == false
                     ? "Fading is turned off for the Clan."
                     : "Cats fade from the afterlife after \(Afterlife.ageToFade) moons unless kept.")
            }
        }
    }

    private var preventFading: Binding<Bool> {
        Binding {
            cat.preventFading
        } set: { prevent in
            Task { await model.setPreventFading(prevent, for: cat.id) }
        }
    }
}
