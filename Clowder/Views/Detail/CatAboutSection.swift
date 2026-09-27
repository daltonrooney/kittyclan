import SwiftUI

struct CatAboutSection: View {
    let cat: Cat

    var body: some View {
        Section("About") {
            LabeledContent("Rank", value: cat.rank.label)
            LabeledContent("Age", value: "\(cat.age.label), \(cat.moonsText)")
            LabeledContent("Sex", value: cat.sex.rawValue.capitalized)
            LabeledContent("Personality", value: cat.personality.trait.capitalized)
            LabeledContent("Origin", value: cat.origin.rawValue.capitalized)
            LabeledContent("Experience", value: cat.experience, format: .number)
            if cat.isDead {
                LabeledContent("Remembered", value: cat.diedAtClanAge.map { "Since moon \($0)" } ?? "Yes")
            }
        }
    }
}
