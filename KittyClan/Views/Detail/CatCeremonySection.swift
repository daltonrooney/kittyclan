import SwiftUI

/// The leader's nine-lives ceremony, folded away until asked for.
struct CatCeremonySection: View {
    @Environment(AppModel.self) private var model
    let cat: Cat
    @State private var isExpanded = Self.expandsByDefault

    var body: some View {
        let paragraphs = model.ceremony(of: cat)
        if !paragraphs.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $isExpanded) {
                    ForEach(paragraphs.indices, id: \.self) { index in
                        Text(paragraphs[index])
                            .padding(.vertical, 4)
                    }
                } label: {
                    Label("Nine Lives Ceremony", systemImage: "sparkles")
                        .font(.headline)
                }
            }
        }
    }

    private static var expandsByDefault: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "detailSection") == DetailSection.ceremony.rawValue
        #else
        false
        #endif
    }
}
