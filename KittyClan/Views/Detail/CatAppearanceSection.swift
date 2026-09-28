import SwiftUI

struct CatAppearanceSection: View {
    let appearance: CatAppearance

    var body: some View {
        let a = appearance
        Section("Appearance") {
            LabeledContent("Pelt", value: "\(a.length.rawValue.capitalized) \(pretty(a.pattern))")
            LabeledContent("Colour", value: pretty(a.colour))
            if a.isTortie {
                LabeledContent("Tortie patches", value: "\(pretty(a.tortieColour)) \(pretty(a.tortiePattern)), \(pretty(a.tortieMarking))")
            }
            LabeledContent("Eyes", value: a.eyeColour2.map { "\(pretty(a.eyeColour)) and \(pretty($0))" } ?? pretty(a.eyeColour))
            if let white = a.whitePatches { LabeledContent("White markings", value: pretty(white)) }
            if let points = a.points { LabeledContent("Points", value: pretty(points)) }
            if let vitiligo = a.vitiligo { LabeledContent("Vitiligo", value: pretty(vitiligo)) }
            LabeledContent("Skin", value: pretty(a.skin))
            if !a.scars.isEmpty { LabeledContent("Scars", value: a.scars.map(pretty).joined(separator: ", ")) }
            if !a.accessories.isEmpty { LabeledContent("Wearing", value: a.accessories.map(pretty).joined(separator: ", ")) }
        }
    }

    private func pretty(_ id: String?) -> String {
        guard let id else { return "—" }
        return id.replacing("_", with: " ").replacing("-", with: " ").capitalized
    }
}
