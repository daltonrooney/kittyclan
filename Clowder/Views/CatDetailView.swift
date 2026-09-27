import SwiftUI

struct CatDetailView: View {
    let cat: Cat
    let assets: GameAssets
    let model: ClanModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PixelSprite(image: assets.sprite(for: cat))
                        .frame(maxWidth: 300)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }

                Section("Through the moons") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 16) {
                            ForEach(CatAge.allCases, id: \.self) { age in
                                VStack {
                                    PixelSprite(image: assets.sprite(for: cat, age: age))
                                        .frame(width: 100)
                                    Text(model.displayName(cat, age: age))
                                        .font(.caption.bold())
                                    Text(age.label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                Section("About") {
                    LabeledContent("Sex", value: cat.sex.rawValue.capitalized)
                    LabeledContent("Age", value: "\(cat.age.label), \(cat.moons) moons")
                }

                Section("Appearance") {
                    let a = cat.appearance
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
            .navigationTitle(model.displayName(cat))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func pretty(_ id: String?) -> String {
        guard let id else { return "—" }
        return id.replacing("_", with: " ").replacing("-", with: " ").capitalized
    }
}
